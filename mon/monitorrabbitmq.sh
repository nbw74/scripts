#!/bin/bash
#
# SNMP extender for rabbitmq check
# v.0.0.3
#

PATH=/bin:/usr/bin:/sbin:/usr/sbin

# BEGIN CONFIG FILE FORMAT
# readonly QUEUE_NAME="string"
# readonly DBHOST="string"
# readonly DBNAME="string"
# readonly DBPASS="string"
# END CONFIG FILE FORMAT

LC_ALL=C
LC_MESSAGES=C

readonly bn=$(basename $0)
readonly CONFIG="/usr/local/etc/${bn%\.*}.conf"

if [[ -f $CONFIG ]]; then
    source $CONFIG
else
    echo "Configuration file not found" 1>&2
    exit 1
fi

LANG=C
typeset MODE="" MSG=""
typeset -i CHECK=0 CODE=666 KEEPLOCK=0 PERFDATA=0 QUEUES=11111 WARN_THR=0 CRIT_THR=0

set -o nounset
set -o errtrace

readonly LOCKFILE=/run/${bn%%\.*}.lock
# hardcoded for CentOS 7
readonly SNMPD_BASEDIR=/var/lib/net-snmp
readonly OUTFILE=$(mktemp --tmpdir=$SNMPD_BASEDIR -t ${bn%%\.*}.XXXX)

main() {

    trap except ERR
    trap myexit EXIT

    if [[ -f "$LOCKFILE" ]]; then
        local lock_time=$(stat --format="%Y" $LOCKFILE)
        local curr_time=$(date '+%s')

        if (( ((curr_time - lock_time)) < 280 )); then
            writeLg "Lock file found, exiting..."
            MSG="Lock file found"
            CODE=3
            KEEPLOCK=1
            exit
        fi
    else
        touch $LOCKFILE >$OUTFILE 2>&1
        getThresholds
        getQueues
    fi
    
    CODE=3; exit
}

getThresholds() {
    FN=$FUNCNAME
    # Получаем верхнюю границу нормы из базы
    WARN_THR=$(mysql -h $DBHOST -u $DBNAME -p$DBPASS -B -N -e "SELECT count(*) FROM clients WHERE enabled = 1 AND deleted = 0 AND StatusArch != 'Yes';" $DBNAME 2>$OUTFILE)
    # Критическое значение = 'верхняя граница' + 20%
    CRIT_THR=$(awk "BEGIN { pc=${WARN_THR}/100*20+${WARN_THR}; i=int(pc); print (pc-i<0.5)?i:i+1 }" 2>$OUTFILE)
}

getQueues() {
    FN=$FUNCNAME

    local -a Out=( $(rabbitmqctl -q list_queues 2>$OUTFILE | head -1 | awk '{ print $1, $2 }') )
    local QNAME="${Out[0]}"
    QUEUES=${Out[1]}

    MSG="rabbitmqctl list_queues: $QNAME $QUEUES"

    if [[ "$QNAME" == "$QUEUE_NAME" ]]; then

        if (( QUEUES > CRIT_THR )); then
            CODE=2
        elif (( QUEUES > WARN_THR )); then
            CODE=1
        else
            CODE=0
        fi

    else
        MSG="Unexpected queue name: $QNAME"
        CODE=2
    fi

    exit

}

usage() {
    echo -e "Usage: $(basename $0) option (REQUIRED)
        Options:
        -f          add performance data output
        "
}

except() {
    local -i RET=$?
    
    MSG="Error in function ${FN:-UNKNOWN}, exit code $RET. Program output: \"$(cat ${OUTFILE:-/dev/null})\""
    writeLg "$MSG"

    CODE=3; exit
}

myexit() {

    if (( PERFDATA )); then
        MSG="${MSG}|$(printf "%s" "list_queues=${QUEUES};${WARN_THR};${CRIT_THR}")"
    fi

    case $CODE in
        0) echo "OK: $MSG" ;;
        1) echo "WARNING: $MSG" ;;
        2) echo "CRITICAL: $MSG" ;;
        3) echo "UNKNOWN: $MSG" ;;
        *) echo "UNKNOWN: <Bad exit code: ${CODE}>; $MSG";
            CODE=3
    esac

    if (( ! KEEPLOCK )); then
        [[ -f "$LOCKFILE" ]] && rm "$LOCKFILE"
        [[ -f "$OUTFILE" ]] && rm "$OUTFILE"
    fi
    
    exit $CODE
}

writeLg() {
    logger -t "$bn" "$*"
}

while getopts "hf" OPTION; do
    case $OPTION in
        h) usage
            exit 0
            ;;
        f) PERFDATA=1
            ;;
        *) usage
            exit 1
    esac
done

main

### EOF ###
