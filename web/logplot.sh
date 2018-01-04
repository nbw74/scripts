#!/bin/bash
#
# Apache log file plotter
# http://www.keepthingssimple.net/2012/10/creating-requests-per-time-graph-from-nginx-or-apache-access-log/
#
# version from web002 at 2015-10-20
 
FILE=$1
 
# FDATE=$(head -1 $FILE |awk '{print $4}'|sed -e 's/\[//'|sed -e 's/\//-/g'|sed -e 's/:/ /')
FDATE=$(head -1 $FILE |awk '{ sub(/\[/, "", $4); sub(/:/, " ", $4); gsub(/\//, "-", $4); print $4 }')
FDATE_S=$(date -d "$FDATE" '+%s');
FDATE_T=$((FDATE_S + 300));
COUNT=0
 
DATAFILE=logdata-$(date '+%FT%H%M').txt
RESULTFILE="result-"$(date -d "$FDATE" '+%Y-%m-%d')".png"

while read line
do
    LDATE=$(echo $line|awk '{print $4}'|sed -e 's/\[//'|sed -e 's/\//-/g'|sed -e 's/:/ /')
    LDATE_S=$(date -d "$LDATE" '+%s');
    if (( LDATE_S < FDATE_T )); then
        COUNT=$((COUNT + 1))
    else
        echo "$(date -d @"$((FDATE_T - 300))" '+%Y-%m-%d %H:%M:%S') $COUNT" >>$DATAFILE
        FDATE_T=$((FDATE_T + 300))
        COUNT=1;
    fi
done <$FILE
 
exit 0

gnuplot << EOF
reset
set xdata time
set timefmt "%Y-%m-%d %H:%M:%S"
set format x "%H:%M"
set autoscale
set ytics
set grid y
set auto y
set term png truecolor
set output "$RESULTFILE"
set xlabel "Time"
set ylabel "Request per 5min"
set grid
set boxwidth 0.95 relative
set style fill transparent solid 0.5 noborder
plot "$DATAFILE" using 1:3 w boxes lc rgb "green" notitle
EOF
 
# rm -v $DATAFILE
