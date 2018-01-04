#!/bin/bash
#
# Pruning old PostgreSQL WAL archive files
# Southbridge LLC, 2017 A.D.
#

set -E
set -o nounset

# CONSTANTS BEGIN
readonly PATH=/bin:/usr/bin:/sbin:/usr/sbin
readonly CONFIG_PATH=/usr/local/etc:/srv/southbridge/etc
readonly bn="$(basename $0)"
readonly LOGERR=$(mktemp --tmpdir ${bn%\.*}.XXXX)
readonly CONFIG=${bn%\.*}.conf
readonly BIN_REQUIRED="logger mailx"
# CONSTANTS END

# DEFAULTS BEGIN
typeset RUNUSER="walbackup"
typeset WALDIR="/srv/walbackup"
typeset MAILXTO="root"
typeset MAIL_SUBJ="ERRORS REPORTED: PostgreSQL Backup error Log"
typeset -i RM_COUNT=100
typeset -i MAX_USED_PERC=86
typeset -i MIN_WAL_AGE_DAYS=32
# DEFAULTS END

typeset OPTTAIL="" FILESYSTEM=""
typeset -i INIT=0 NOMAIL=0 warn=0 config_present=0

main() {
    local fn=$FUNCNAME
    local -i used=0 loop=0 pruned=0

    trap 'except $LINENO' ERR
    trap myexit EXIT

    for path in $(echo "$CONFIG_PATH"|tr ':' ' '); do
        if [[ -f "${path}/$CONFIG" ]]; then
            source "${path}/$CONFIG"
            config_present=1
        fi
    done

    checks
    # Поиск ФС, на которой расположена WALDIR
    find_filesystem
    # Проверяется занятое место, если оно больше MAX_USED_PERC - удаляется RM_COUNT
    # самых старых сегментов WAL
    while true; do

        if (( loop > 10000 )); then
            echo "Infinite loop apparently occured: cannot clear disk space" >$LOGERR
            false
        fi

        used=$(df -P | awk -v fs="^$FILESYSTEM" '$0 ~ fs { sub(/%/, ""); print $5 }')

        if (( ! used )); then
            echo "Cannot determine used space for '$WALDIR'" >$LOGERR
            false
        fi

        if (( used > MAX_USED_PERC )); then
            pruned=1
            find $WALDIR -type f -regextype sed -regex '.*/[0-9A-F]\{24\}.*' -printf '%T+ %p\n' | sort | head -n $RM_COUNT | awk '{ wal=$2; system( "rm -- " wal ) }' 2>$LOGERR
        else
            break
        fi

        loop=$(( loop + 1 ))
    done
    # Если проведена очистка, то проверяется возраст самого старого сегмента
    # из оставшихся и, если он превышает MIN_WAL_AGE_DAYS, то выдаётся алерт
    if (( pruned )); then
        local oldest_segment_time=""
        local -i oldest_segment_time_unix=0 min_segment_time_unix=0

        oldest_segment_time="$(find $WALDIR -type f -regextype sed -regex '.*/[0-9A-F]\{24\}.*' -printf '%T+ %p\n' | sort | head -n 1 | awk -F'[+. ]' '{ print $1, $2 }')"
        oldest_segment_time_unix=$(date -d "$oldest_segment_time" "+%s")
        min_segment_time_unix=$(date "+%s" -d "$MIN_WAL_AGE_DAYS days ago")

        if (( ! oldest_segment_time_unix || ! min_segment_time_unix )); then
            echo "Time cannot be 0. Check script commands" >$LOGERR
            false
        fi

        if (( oldest_segment_time_unix > min_segment_time_unix )); then
            warn=1
            echo "Oldest segment age (${oldest_segment_time}) less than $MIN_WAL_AGE_DAYS days!" >$LOGERR
            false
            warn=0
        fi
    fi

    exit 0
}

find_filesystem() {
    local fn=$FUNCNAME
    local check_path=$WALDIR
    local -i loop=0

    while true; do

        if (( loop > 10 )); then
            echo "Infinite loop apparently occured: cannot find FILESYSTEM" >$LOGERR
            false
        fi

        FILESYSTEM=$(df -P | awk -v path="$check_path" '$6 == path { print $1 }')

        if [[ -z "$FILESYSTEM" ]]; then
            check_path=${check_path%\/*}
            [[ -z "$check_path" ]] && check_path="/"
        else
            break
        fi

        loop=$(( loop + 1 ))
    done
}

checks() {
    local fn=$FUNCNAME
    # Проверка наличия нужных бинарников
    for i in $BIN_REQUIRED; do
        if ! hash $i 2>/dev/null
        then
            echo "Required binary '$i' is not installed" >$LOGERR
            false
        fi
    done

    if [[ `whoami` != $RUNUSER ]]; then
        echo "This script must be run as '$RUNUSER' user" >$LOGERR
        false
    fi

    if (( ! config_present )); then
        echo "Configuration file '$CONFIG' not found in '$CONFIG_PATH'" >$LOGERR
        false
    fi

}

except() {
    local -i ret=$?
    local -i no=${1:-666}

    if (( warn )); then
        MSG='WARNING!'
    else
        MSG='FATAL:'
    fi

    if (( ! NOMAIL )); then
        echo -e "\tПроизошла ошибка при выполнении скрипта ${0} (строка ${no}, функция '$fn'), 
выполняющего удаление старых WAL с сервера архивов.
\tВывод сбойной команды:\n\n'$(cat ${LOGERR:-/dev/null}|awk '$1=$1' ORS=' ')'" | mailx -s "$MAIL_SUBJ" $MAILXTO
    fi

    if [[ -t 1 ]]; then
        echo "* ${MSG} error occured in function '$fn' on line ${no}. Output: '$(cat ${LOGERR:-/dev/null}|awk '$1=$1' ORS=' ')'" 1>&2
    fi

    logger -p user.err -t "$bn" "* ${MSG} error occured in function '$fn' on line ${no}. Output: '$(cat ${LOGERR:-/dev/null}|awk '$1=$1' ORS=' ')'"

    if (( ! warn )); then
        exit $ret
    fi
}

myexit() {
    local ret=$?

    [[ -f $LOGERR ]] && rm "$LOGERR"
    exit $ret
}

main

## EOF ##
