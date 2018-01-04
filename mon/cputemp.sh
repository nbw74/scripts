#!/bin/bash
#
# lm_sensors CPU temp for Icinga2
# v.0.2
#
# Working with `sensors -Au` output:
#
#  coretemp-isa-0000
# Physical id 0:
#   temp1_input: 49.000
#   [...]
# Core 0:
#   temp2_input: 49.000
#   [...]
# Core 1:
#   temp3_input: 48.000
#   [...]
# [...]
#

PATH=/bin:/usr/bin:/sbin:/usr/sbin

readonly bn=$(basename $0)

LANG=C
LC_ALL=C
LC_MESSAGES=C

typeset MEGACLI_BIN="/opt/MegaRAID/MegaCli/MegaCli64"
typeset MSG="" MSG2="" PRF="" MODE="cpu"
typeset -i OK=0 WARN=0 CRIT=0 KEEPLOCK=0 PERFDATA=0 CPU_NO=0
typeset -i WARN_THR=50 CRIT_THR=60 WARN_THR_ROC=60 CRIT_THR_ROC=70 WARN_THR_BBU=30 CRIT_THR_BBU=40

set -o nounset
set -o errtrace

# hardcoded for CentOS 7
readonly ICINGA2_SPOOLDIR=/var/spool/icinga2/tmp
readonly ERRFILE=$(mktemp --tmpdir=$ICINGA2_SPOOLDIR -t ${bn%%\.*}.XXXX)
readonly TMPFILE=$(mktemp --tmpdir=$ICINGA2_SPOOLDIR -t ${bn%%\.*}.XXXX)

main() {

    trap except ERR
    trap myexit EXIT

    readonly LOCKFILE=$ICINGA2_SPOOLDIR/${bn%%\.*}-${MODE}.lock

    if [[ -f "$LOCKFILE" ]]; then
        local lock_time=$(stat --format="%Y" $LOCKFILE)
        local curr_time=$(date '+%s')

        if (( ((curr_time - lock_time)) < 280 )); then
            writeLg "Lock file found, exiting..."
            MSG=" Lock file found"
            KEEPLOCK=1
            exit
        fi
    else
        touch $LOCKFILE >$ERRFILE 2>&1

        if [[ "$MODE" == "cpu" ]]; then
            getCpuTemp
        elif [[ "$MODE" == "roc" ]]; then
            getRocTemp
            getBbuTemp
        else
            false
        fi
    fi

    exit
}

getCpuTemp() {
    local fn=$FUNCNAME

    local -a Temps=("")
    local -A Cpu_temps

    sensors -Au 2>$ERRFILE >$TMPFILE

    Cpu_temps[Physical_id_${CPU_NO}]=$(sed -n "/coretemp-isa-000${CPU_NO}/,/^ *$/p" $TMPFILE | awk '/temp1_input/ {sub(/\.[[:digit:]]*/, ""); print $2}')
    # Если счётчика Physical_id_# нет, присваиваем ему значение 0
    if [[ -z ${Cpu_temps[Physical_id_${CPU_NO}]} ]]; then
        Cpu_temps[Physical_id_${CPU_NO}]=0
    fi

    Temps=( $(sed -n "/coretemp-isa-000${CPU_NO}/,/^ *$/p" $TMPFILE | awk '/temp([2-9]|1[0-9])_input/ {sub(/\.[[:digit:]]*/, ""); print $2}') )

    local n=0
    for (( t=0; t<${#Temps[@]}; t++ )); do
        Cpu_temps[Core_${n}]=${Temps[$t]}
        (( n=n+1 ))
    done
    n=0

    for k in "${!Cpu_temps[@]}"; do
        MSG="${MSG} ${k}: ${Cpu_temps[$k]}°C;"
        PRF="${k}=${Cpu_temps[$k]};${WARN_THR};${CRIT_THR} ${PRF}"

        if (( ${Cpu_temps[$k]} >= CRIT_THR )); then
            CRIT=1
        elif (( ${Cpu_temps[$k]} >= WARN_THR )); then
            WARN=1
        else
            OK=1
        fi

    done
}

getRocTemp() {
    local fn=$FUNCNAME
    local out=""
    local -i roctemp=0

    out=$(sudo $MEGACLI_BIN -AdpAllinfo -a0 2>$ERRFILE | grep temperature)
    MSG=" $out"
    roctemp=$(echo "$out" | awk '{ print $4 }')
    PRF="ROC_temp=${roctemp};${WARN_THR_ROC};${CRIT_THR_ROC}"

    if (( roctemp >= CRIT_THR_ROC )); then
        CRIT=1
    elif (( roctemp >= WARN_THR_ROC )); then
        WARN=1
    elif (( roctemp == 0 )); then
        MSG=" Unexpected string$MSG"
        return
    else
        OK=1
    fi

}

getBbuTemp() {
    local fn=$FUNCNAME
    local out=""
    local -i bbutemp=0

    out=$(sudo $MEGACLI_BIN -AdpBbuCmd -GetBbuStatus -a0 2>$ERRFILE | grep Temperature | head -1)

    if [[ -n "$out" ]]; then
        MSG="${MSG}; BBU $out"
        bbutemp=$(echo "$out" | awk '{ print $2 }')
        PRF="$PRF BBU_temp=${bbutemp};${WARN_THR_BBU};${CRIT_THR_BBU}"

        if (( bbutemp >= CRIT_THR_BBU )); then
            CRIT=1
        elif (( bbutemp >= WARN_THR_BBU )); then
            WARN=1
        elif (( bbutemp == 0 )); then
            MSG=" Unexpected string$MSG"
            return
        else
            OK=1
        fi
    fi

}

usage() {
    echo -e "Usage: $(basename $0) option (REQUIRED)
        Options:
        -c <int>    critical threshold (default 60°C)
        -f          add performance data output
        -n <int>    CPU nubmer - 0 (default) or 1
        -w <int>    warning threshold (default 50°C)
        -M          MegaRAID ROC temperature metering mode (requires MegaCli64)
        -P          MegaCli64 full path (default: /opt/MegaRAID/MegaCli/MegaCli64)
        -W          warning threshold for ROC temperature (default 60°C)
        -C          critical threshold for ROC temperature (default 70°C)
        "
}

except() {
    local -i RET=$?

    MSG=" Error in function ${fn:-UNKNOWN}, exit code $RET. Program output: \"$(cat ${ERRFILE:-/dev/null})\""
    writeLg "$MSG"

    exit
}

myexit() {

    local -i CODE=3
    local STR=""

    if (( CRIT )); then
        CODE=2
        STR="CRITICAL -"
    elif (( WARN )); then
        CODE=1
        STR="WARNING -"
    elif (( OK )); then
        CODE=0
        STR="OK -"
    else
        STR="UNKNOWN -"
    fi

    if [[ "$MODE" == "cpu" ]]; then
        MSG="CPUTEMP ${STR}${MSG:- Internal error}"
    elif [[ "$MODE" == "roc" ]]; then
        MSG="ROCTEMP ${STR}${MSG:- Internal error}"
    else
        false
    fi

    if (( PERFDATA )); then
        MSG="${MSG}|${PRF}"
    fi

    if (( ! KEEPLOCK )); then
        [[ -f "$LOCKFILE" ]] && rm "$LOCKFILE"
        [[ -f "$ERRFILE" ]] && rm "$ERRFILE"
        [[ -f "$TMPFILE" ]] && rm "$TMPFILE"
    fi

    echo "$MSG"
    exit $CODE
}

writeLg() {
    logger -t "$bn" "$*"
}

while getopts "n:hfw:c:MP:W:C:" OPTION; do
    case $OPTION in
        f) PERFDATA=1
            ;;
        h) usage
            exit 0
            ;;
        n) CPU_NO=$OPTARG
            ;;
        w) WARN_THR=$OPTARG
            ;;
        c) CRIT_THR=$OPTARG
            ;;
        M) MODE=roc
            ;;
        P) MEGACLI_BIN=$OPTARG
            ;;
        W) WARN_THR_ROC=$OPTARG
            ;;
        C) CRIT_THR_ROC=$OPTARG
            ;;
        *) usage
            exit 1
    esac
done

main

### EOF ###
