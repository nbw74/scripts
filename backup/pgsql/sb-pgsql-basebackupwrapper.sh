#!/bin/bash
#
# pg_basebackup wrapper for periodic backup jobs
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
readonly BIN_REQUIRED="pg_basebackup logger mailx"
readonly pgpass="${HOME}/.pgpass"
readonly BAKDIR="$(date '+%FT%H%M')"
# CONSTANTS END

# DEFAULTS BEGIN
typeset RUNUSER="basebackup"
typeset BAKUSER="replicator"
typeset BASEDIR="/srv/basebackup"
typeset MAILXTO="root"
typeset MAIL_SUBJ="ERRORS REPORTED: PostgreSQL Backup error Log"
# DEFAULTS END

typeset OPTTAIL=""
typeset -i BACKUP_DEPTH=0 NOMAIL=0 config_present=0

main() {
    local fn=$FUNCNAME
    local instance_address=$OPTTAIL
    local instance_catalog=${OPTTAIL%-*}

    trap 'except $LINENO' ERR
    trap myexit EXIT
    # Проверка наличия нужных бинарников
    for i in $BIN_REQUIRED; do
        if ! hash $i 2>/dev/null
        then
            echo "Required binary '$i' is not installed" >$LOGERR
            false
        fi
    done
    # Чтение конфигурационных файлов
    for path in $(echo "$CONFIG_PATH"|tr ':' ' '); do
        if [[ -f "${path}/$CONFIG" ]]; then
            source "${path}/$CONFIG"
            config_present=1
        fi
    done

    checks_main

    cd "${BASEDIR}/$instance_catalog" 2>$LOGERR
    # Удаление всех каталогов в текущем, оставляя только (( BACKUP_DEPTH - 1 ))
    ls -dt 20* 2>/dev/null | tail -n +$BACKUP_DEPTH | xargs rm -rf -- 2>$LOGERR
    pg_basebackup --host=$instance_address --username=$BAKUSER --pgdata=$BAKDIR --no-password 2>$LOGERR

    exit 0
}

checks_main() {
    local fn=$FUNCNAME

    if [[ $(whoami) != $RUNUSER ]]; then
        echo "This script must be run as '$RUNUSER' user" >$LOGERR
        false
    fi

    if (( ! BACKUP_DEPTH )); then
        echo "Required variable 'BACKUP_DEPTH' (int) missing in configuration file '$CONFIG'" >$LOGERR
        false
    fi

    if [[ -z $instance_address ]]; then
        echo "Required parameter (instance address) is missing" >$LOGERR
        false
    fi

    if [[ ! -d "${BASEDIR}/$instance_catalog" ]]; then
        mkdir "${BASEDIR}/$instance_catalog" 2>$LOGERR
    fi

    if [[ ! -r "$pgpass" ]]; then
        echo "PostgreSQL authorization file ($pgpass) is missing or unreadable" >$LOGERR
        false
    fi

    if ! fgrep -q $instance_catalog $pgpass
    then
        echo "PostgreSQL authorization file ($pgpass) is not contains authentication data for '$instance_address' address." >$LOGERR
        false
    fi

    if (( ! config_present )); then
        echo "Configuration file '$CONFIG' not found in '$CONFIG_PATH'" >$LOGERR
        false
    fi
}

except() {
    local ret=$?
    local no=${1:-no_line}

    if (( ! NOMAIL )); then
        echo -e "\tПроизошла ошибка при выполнении скрипта ${0} (строка ${no}, функция '$fn'), 
выполняющего полное копирование СУБД PostgreSQL посредством команды pg_basebackup с хоста *${instance_address}*.
\tВывод сбойной команды:\n\n  $(cat ${LOGERR}|awk '$1=$1' ORS=' ')" | mailx -s "$MAIL_SUBJ" $MAILXTO
    fi

    if [[ -t 1 ]]; then
        echo "* FATAL: error occured in function '$fn' on line ${no}. Output: '$(cat ${LOGERR}|awk '$1=$1' ORS=' ')'" 1>&2
    fi

    logger -p user.err -t "$bn" "* FATAL: error occured in function '$fn' on line ${no}. Output: '$(cat ${LOGERR}|awk '$1=$1' ORS=' ')'"
    exit $ret
}

myexit() {
    local ret=$?
    local -i bakdir_size=0

    if [[ -d "${BASEDIR}/${instance_catalog}/$BAKDIR" ]]; then
        bakdir_size=$(du -sb "${BASEDIR}/${instance_catalog}/$BAKDIR"|awk '{ print $1 }')
        # Если размер полученного каталога с бэкапом составляет менее 2M, то бэкап признаётся неудавшимся и каталог удаляется
        if (( bakdir_size < 2000000 )); then
            rm -rf "${BASEDIR}/${instance_catalog}/$BAKDIR"
        fi
    fi

    [[ -f $LOGERR ]] && rm "$LOGERR"
    exit $ret
}

usage() {
    echo -e "\tUsage: $bn [postgresql_instance_address]\n
"
}

while getopts "h" OPTION; do
    case $OPTION in
        h) usage; exit 0
    esac
done

shift "$((OPTIND - 1))"

OPTTAIL="$*"

if (( ! INIT )); then
    if [[ "${1:-NOP}" == "NOP" ]]; then
        usage
        exit 1
    fi
fi

main

## EOF ##
