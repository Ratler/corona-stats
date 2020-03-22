##
# corona-stats.tcl  Version 0.3  Author Stefan Wold <ratler@stderr.eu>
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
    variable version "0.3"
    variable countryFile "scripts/corona-stats/countrylist.txt"
    variable countryMapping

    if {[file exists $::CovidStats::countryFile]} {
        set fd [open $::CovidStats::countryFile r]
        while { ![eof $fd] } {
            gets $fd line
            if {[regexp {^[a-z]{2}} $line]} {
                regexp -nocase {^([a-z]{2})[[:space:]]+(.*)} $line -> alpha2 country
                set ::CovidStats::countryMapping($alpha2) $country
            }
        }
        close $fd
        putlog "Country list loaded with [array size ::CovidStats::countryMapping] entries"
    }

}

# Packages
package require Tcl 8.5
package require http
package require tls
package require rest

# Setup TLS
http::register https 443 [list ::tls::socket -autoservername true]

# Bindings
bind dcc - corona ::CovidStats::dccGetStats
bind pub - !corona ::CovidStats::pubGetStats

# Automatic bindings and generated procs for each country
if {[array size ::CovidStats::countryMapping] > 0} {
    foreach k [array names ::CovidStats::countryMapping] {
        set cmd "proc CovidStats::${k}getStats "
        set cmd [concat $cmd "{ nick host handle channel arg } {\n"]
        set cmd [concat $cmd "set countryName \[::CovidStats::urlEncode \$::CovidStats::countryMapping($k)\];\n"]
        set cmd [concat $cmd "set data \[::CovidStats::formatOutput \[::CovidStats::getData \$countryName\]\];\n"]
        set cmd [concat $cmd "puthelp \"PRIVMSG \$channel :\$data\";\n"]
        set cmd [concat $cmd "}"]
        eval $cmd
        bind pub - !corona-${k} ::CovidStats::${k}getStats
    }
}

###
# Functions
###
proc CovidStats::getData { country } {
    if {$country == "all" || $country == ""} {
        set res [::rest::get https://corona.lmao.ninja/all []]
    } else {
        set res [::rest::get https://corona.lmao.ninja/countries/$country []]
    }

    set res [::rest::format_json $res]
    return $res
}

proc CovidStats::pubGetStats { nick host handle channel arg } {
    set data [::CovidStats::formatOutput [::CovidStats::getData $arg]]
    puthelp "PRIVMSG $channel :$data"
}

proc CovidStats::formatOutput { data } {
    if {[dict exists $data updated]} {
        foreach {var} [list cases deaths recovered updated] {
            set $var [dict get $data $var]
        }
        set res "Covid-19 stats - Total - Cases: $cases - Deaths: $deaths - Recovered: $recovered - Updated: [clock format [string range $updated 0 end-3] -format {%Y-%m-%d %R}]"
    } else {
        foreach {var} [list country cases todayCases deaths todayDeaths recovered active critical casesPerOneMillion] {
            set $var [dict get $data $var]
        }
        set res "Covid-19 stats - $country - Cases: $cases - Today cases: $todayCases - Deaths: $deaths - Today deaths: $todayDeaths - Recovered: $recovered - Active: $active - Critical: $critical - Cases per one million: $casesPerOneMillion"
    }

    return $res
}

proc CovidStats::dccGetStats { nick idx arg } {
    set data [CovidStats::getData $arg]
    putidx $idx [::CovidStats::formatOutput $data]
}

proc CovidStats::urlEncode {str} {
    set uStr [encoding convertto utf-8 $str]
    set chRE {[^-A-Za-z0-9._~\n]}
    set replacement {%[format "%02X" [scan "\\\0" "%c"]]}
    return [string map {"\n" "%0A"} [subst [regsub -all $chRE $uStr $replacement]]]
}

putlog "\002Corona (Covid-19) Statistics v$CovidStats::version\002 by Ratler loaded"