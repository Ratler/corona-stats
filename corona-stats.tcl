##
# corona-stats.tcl  Version 0.8  Author Stefan Wold <ratler@stderr.eu>
###
# LICENSE:
# Copyright (C) 2020  Stefan Wold <ratler@stderr.eu>
#
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License
# as published by the Free Software Foundation; either version 2
# of the License, or (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program; if not, write to the Free Software
# Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA  02110-1301, USA.

if {[namespace exists CovidStats]} {namespace delete CovidStats}
namespace eval CovidStats {
    variable version "0.8"
    variable files
    set files(countryFile) "scripts/corona-stats/countrylist.txt"
    set files(usStatesFile) "scripts/corona-stats/states.txt"
    set files(caProvincesFile) "scripts/corona-stats/provinces.txt"
    variable ignoreResponseFields [list countryInfo city coordinates]
    variable countryMapping
    variable usStatesMapping
    variable caProvincesMapping

    # Cache data - in seconds, default 3600 seconds (1h)
    variable cacheTime 3600
    variable cache [dict create]

    foreach i [list country usStates caProvinces] {
        if {[file exists $::CovidStats::files(${i}File)]} {
            set fd [open $::CovidStats::files(${i}File) r]
            while { ![eof $fd] } {
                gets $fd line
                if {[regexp {^[a-z]{2}} $line]} {
                    regexp -nocase {^([a-z]{2})[[:space:]]+(.*)} $line -> alpha2 name
                    set ::CovidStats::${i}Mapping($alpha2) $name
                }
            }
            close $fd
            putlog "corona-stats - $i list loaded with [array size ::CovidStats::${i}Mapping] entries"
        }
    }
}

# Packages
package require Tcl 8.6
package require http
package require tls
package require rest

# Setup TLS
http::register https 443 [list ::tls::socket -tls1 1 -servername corona.lmao.ninja]

# Bindings
bind dcc - corona ::CovidStats::dccGetStats
bind pub - !corona ::CovidStats::pubGetStats
bind pub - !coronatop5 ::CovidStats::pubGetTop5Stats

# Automatic bindings and generated procs for each country
if {[array size ::CovidStats::countryMapping] > 0} {
    foreach k [array names ::CovidStats::countryMapping] {
        set cmd "proc CovidStats::${k}getStats "
        set cmd [concat $cmd "{ nick host handle channel arg } {\n"]
        set cmd [concat $cmd "set countryName \[::CovidStats::urlEncode \$::CovidStats::countryMapping($k)\];\n"]
        set cmd [concat $cmd "set data \[::CovidStats::formatOutput \[::CovidStats::getData \$countryName\ \"\"]\];\n"]
        set cmd [concat $cmd "puthelp \"PRIVMSG \$channel :\$data\";\n"]
        set cmd [concat $cmd "}"]
        eval $cmd
        bind pub - !corona-${k} ::CovidStats::${k}getStats
    }
}

if {[array size ::CovidStats::usStatesMapping] > 0} {
    foreach k [array names ::CovidStats::usStatesMapping] {
        set cmd "proc CovidStats::${k}UsStatesGetStats "
        set cmd [concat $cmd "{ nick host handle channel arg } {\n"]
        set cmd [concat $cmd "set stateName \$::CovidStats::usStatesMapping($k);\n"]
        set cmd [concat $cmd "set data \[::CovidStats::formatOutput \[::CovidStats::getUsStateData \$stateName\]\];\n"]
        set cmd [concat $cmd "puthelp \"PRIVMSG \$channel :\$data\";\n"]
        set cmd [concat $cmd "}"]
        eval $cmd
        bind pub - !coronaus-${k} ::CovidStats::${k}UsStatesGetStats
    }
}

if {[array size ::CovidStats::caProvincesMapping] > 0} {
    foreach k [array names ::CovidStats::caProvincesMapping] {
        set cmd "proc CovidStats::${k}CaProvinceGetStats "
        set cmd [concat $cmd "{ nick host handle channel arg } {\n"]
        set cmd [concat $cmd "set provinceName \$::CovidStats::caProvincesMapping($k);\n"]
        set cmd [concat $cmd "set data \[::CovidStats::formatOutput \[::CovidStats::getCaProvinceData \$provinceName\]\];\n"]
        set cmd [concat $cmd "puthelp \"PRIVMSG \$channel :\$data\";\n"]
        set cmd [concat $cmd "}"]
        eval $cmd
        bind pub - !coronaca-${k} ::CovidStats::${k}CaProvinceGetStats
    }
}

###
# Functions
###
proc CovidStats::setCache { cacheName data } {
    dict set ::CovidStats::cache $cacheName time [unixtime]
    dict set ::CovidStats::cache $cacheName data $data
}

proc CovidStats::getCache { cacheName } {
    set res ""
    if {[dict exists $::CovidStats::cache $cacheName time] && [expr [unixtime] - [dict get $::CovidStats::cache $cacheName time]] <= $::CovidStats::cacheTime} {
        set res [dict get $::CovidStats::cache $cacheName data]
    }
    return $res
}

proc CovidStats::sortCountryData { data sortby } {
    set x [list]

    foreach d $data {
        lappend x [dict get $d country]
        lappend x [dict get $d $sortby]
    }

    set x [lsort -integer -decreasing -stride 2 -index 1 $x]
    set res [list]

    # Recreate list of dicts :)
    foreach {k v} $x {
        lappend res [dict create country "$k" $sortby "$v"]
    }
    return $res
}

proc CovidStats::getData { country sortby } {
    if {$country == ""} {
        set res [::rest::get https://corona.lmao.ninja/all {}]
        set res [::rest::format_json $res]
    } elseif {$country == "all"} {
        set res [::CovidStats::getCache countryAll]
        if {$res == ""} {
            set res [::rest::get https://corona.lmao.ninja/countries sort=$sortby]
            set res [::rest::format_json $res]
            ::CovidStats::setCache countryAll $res
        } else {
            # Need to re-sort cached data based on $sortby
            set res [::CovidStats::sortCountryData $res $sortby]
        }
    } else {
        set res [::rest::get https://corona.lmao.ninja/countries/$country {}]
        set res [::rest::format_json $res]
    }

    return $res
}

proc CovidStats::getUsStateData { state } {
    set res [::CovidStats::getCache usState]

    if {$res == ""} {
        set res [::rest::get https://corona.lmao.ninja/states {}]
        set res [::rest::format_json $res]
        ::CovidStats::setCache usState $res
    }

    foreach st $res {
        if {[dict get $st state] == "$state"} {
            return $st
        }
    }
}

proc CovidStats::getCaProvinceData { province } {
    set res [::CovidStats::getCache caProvince]

    if {$res == ""} {
        set res [::rest::get https://corona.lmao.ninja/jhucsse {}]
        set res [::rest::format_json $res]

        # Only store Canadian provinces in the cache to speed things up
        # and to reduce memory usage
        set res [lmap d $res {expr {[dict get $d country] == "Canada" ? $d : [continue]}}]
        ::CovidStats::setCache caProvince $res
    }

    foreach pr $res {
        if {[dict get $pr province] == $province} {
            return $pr
        }
    }
}

proc CovidStats::pubGetStats { nick host handle channel arg } {
    set country [::CovidStats::urlEncode $arg]
    set data [::CovidStats::formatOutput [::CovidStats::getData $country ""]]
    puthelp "PRIVMSG $channel :$data"
}

proc CovidStats::pubGetTop5Stats { nick host handle channel arg } {
    set validSortOptions [list cases todayCases deaths todayDeaths recovered active critical casesPerOneMillion]

    if {$arg == "help"} {
        puthelp "PRIVMSG $channel :$nick: Valid sort options are: [join $validSortOptions ", "]"
        return
    }

    if {$arg != "" && [lsearch -exact $validSortOptions $arg] == -1} {
        puthelp "PRIVMSG $channel :$nick: Invalid sort option '$arg'. Valid options are: [join $validSortOptions ", "]"
        return
    } elseif {$arg == ""} {
        set arg "cases"
    }

    set data [::CovidStats::getData all $arg]
    set response "Covid-19 stats (Top 5 - $arg): "

    for {set c 0} {$c < 5} {incr c} {
        set stats [lindex $data $c]
        append response "\00304[expr $c + 1]\003. \002[dict get $stats country]\002:\00307 [dict get $stats $arg]\003"
        if {$c < 4} {
            append response " - "
        }
    }

    puthelp "PRIVMSG $channel :$response"
}

proc CovidStats::formatOutput { data } {
    set res "Covid-19 stats "

    dict for {key value} $data {
        if {[lsearch -exact $::CovidStats::ignoreResponseFields $key] != -1} {
            continue
        }
        if {$key == "updated"} {
            append res "- Updated:\00311 [clock format [string range $value 0 end-3] -format {%Y-%m-%d %R}]\003 "
        } elseif {$key == "country" || $key == "state"} {
            append res "- \00312$value\003 "
        } elseif {$key == "stats"} {
            dict for {k v} $value {
                append res "[::CovidStats::ColorTheme $k $v]"
            }
        } else {
            append res "[::CovidStats::ColorTheme $key $value]"
        }
    }

    return $res
}

proc CovidStats::ColorTheme { key value } {
    set k1 [::CovidStats::readableText $key]
    if {($k1 == "Cases") || ($k1 == "Confirmed")} {
      return "- $k1:\00307 $value \003"
    } elseif {$k1 == "Today Cases"} {
      return "- $k1:\00308 $value \003"
    } elseif {($k1 == "Deaths") || ($k1 == "Deaths Per One Million")} {
      return "- $k1:\00304 $value \003"
    } elseif {$k1 == "Recovered"} {
      return "- $k1:\00303 $value \003"
    } elseif {$k1 == "Active"} {
      return "- $k1:\00313 $value \003"
    } elseif {($k1 == "Updated") || ($k1 == "Cases Per One Million") || ($k1 == "Updated At")} {
      return "- $k1:\00311 $value \003"
    } elseif {($k1 == "Affected Countries") || ($k1 == "Critical")} {
      return "- $k1:\00305 $value \003"
    } elseif {$k1 == "Today Deaths"} {
      return "- $k1:\00305 $value \003"
    } elseif {$k1 == "Province"} {
      return "- $k1:\00312 $value \003"
    } else {
      return "- $k1: $value "
    }
}

proc CovidStats::readableText { text } {
    set words [regexp -all -inline {[a-z]+|[A-Z][a-z]*} $text]
    set words [lmap word $words {string totitle $word}]
    return $words
}

proc CovidStats::dccGetStats { nick idx arg } {
    set data [CovidStats::getData $arg ""]
    putidx $idx [::CovidStats::formatOutput $data]
}

proc CovidStats::urlEncode {str} {
    set uStr [encoding convertto utf-8 $str]
    set chRE {[^-A-Za-z0-9._~\n]}
    set replacement {%[format "%02X" [scan "\\\0" "%c"]]}
    return [string map {"\n" "%0A"} [subst [regsub -all $chRE $uStr $replacement]]]
}

putlog "\002Corona (Covid-19) Statistics v$CovidStats::version\002 by Ratler loaded"
