# COVID-19 (corona) statistics script for Eggdrop

A script that displays realtime statistics about COVID-19 (corona).

## Requirements

* Eggdrop >= 1.6.18
* tcllib (<https://www.tcl.tk/software/tcllib/>)
* tcltls (<https://core.tcl-lang.org/tcltls/index>)

## Commands

__!corona [country]__ - Shows total statistics if no argument is given. If a country name is given as argument detailed statistics for that country is displayed. Ex: !corona Sweden

__!corona-&lt;XX&gt;__ -  Shortcut command to display detailed statistics for a specific country. XX is replaced by a short country name. Ex: !corona-se, !corona-us etc

__!coronatop5 [category]__ - Display top 5 country statistics. Provide an optional category to override the default (cases).

__!coronatop5 help__ - Display valid categories.
