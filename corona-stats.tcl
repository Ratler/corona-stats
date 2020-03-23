##
# corona-stats.tcl  Version 0.4  Author Stefan Wold <ratler@stderr.eu>
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
    variable version "0.4"
    variable files
    set files(countryFile) "scripts/corona-stats/countrylist.txt"
    set files(usStatesFile) "scripts/corona-stats/states.txt"
    variable countryMapping
    variable usStatesMapping
    variable cache

    foreach i [list country usStates] {
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
http::register https 443 [list ::tls::socket -autoservername true]

# Bindings
bind dcc - corona ::CovidStats::dccGetStats
bind pub - !corona ::CovidStats::pubGetStats
bind pub - !coronatop5 ::CovidStats::pubGetTop5Stats
bind pub - !coronaus ::CovidStats::pubGetUsStateStats

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

###
# Functions
###
proc CovidStats::getData { country sortby } {
    if {$country == ""} {
        set res [::rest::get https://corona.lmao.ninja/all {}]
    } elseif {$country == "all"} {
        set res [::rest::get https://corona.lmao.ninja/countries sort=$sortby]
    } else {
        set res [::rest::get https://corona.lmao.ninja/countries/$country {}]
    }

    set res [::rest::format_json $res]
    return $res
}

proc CovidStats::getUsStateData { state } {
    set res [::rest::get https://corona.lmao.ninja/states {}]
    set res [::rest::format_json $res]

    foreach st $res {
        if {[dict get $st state] == "$state"} {
            return $st
        }
    }
}

proc CovidStats::pubGetStats { nick host handle channel arg } {
    set data [::CovidStats::formatOutput [::CovidStats::getData $arg ""]]
    puthelp "PRIVMSG $channel :$data"
}

proc CovidStats::pubGetUsStateStats { nick host handle channel state } {
    set data [::CovidStats::]
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
    #set c 0

    for {set c 0} {$c < 5} {incr c} {
        set stats [lindex $data $c]
        append response "[expr $c + 1]. [dict get $stats country]: [dict get $stats $arg]"
        if {$c < 4} {
            append response " - "
        }
    }

    puthelp "PRIVMSG $channel :$response"
}

proc CovidStats::formatOutput { data } {
    if {[dict exists $data updated]} {
        foreach {var} [list cases deaths recovered updated] {
            set $var [dict get $data $var]
        }
        set res "Covid-19 stats - Total - Cases: $cases - Deaths: $deaths - Recovered: $recovered - Updated: [clock format [string range $updated 0 end-3] -format {%Y-%m-%d %R}]"
    } elseif {[dict exists $data state]} {
        foreach {var} [list state cases todayCases deaths todayDeaths recovered active] {
            set $var [dict get $data $var]
        }
        set res "Covid-19 stats - US: $state - Cases: $cases - Today cases: $todayCases - Deaths: $deaths - Today deaths: $todayDeaths - Recovered: $recovered - Active: $active"
    } else {
        foreach {var} [list country cases todayCases deaths todayDeaths recovered active critical casesPerOneMillion] {
            set $var [dict get $data $var]
        }
        set res "Covid-19 stats - $country - Cases: $cases - Today cases: $todayCases - Deaths: $deaths - Today deaths: $todayDeaths - Recovered: $recovered - Active: $active - Critical: $critical - Cases per one million: $casesPerOneMillion"
    }

    return $res
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