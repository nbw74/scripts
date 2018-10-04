#!/bin/bash
#
# pg_basebackup wrapper for periodic backup jobs
# Southbridge LLC, 2017-2018 A.D.
#

set -E
set -o nounset

# CONSTANTS BEGIN
readonly PATH=/bin:/usr/bin:/sbin:/usr/sbin
readonly CONFIG_PATH=/usr/local/etc:/srv/southbridge/etc
readonly bn="$(basename "$0")"
readonly LOGERR="$(mktemp --tmpdir "${bn%\.*}.XXXX")"
readonly CONFIG="${bn%\.*}.conf"
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
typeset -i STRIP_LAST_DASH_IN_ADDRESS=0
# DEFAULTS END

typeset OPTTAIL="" PG_VERSION=DEFAULT
typeset -i BACKUP_DEPTH=0 NOMAIL=0 config_present=0 DEBUG=0 DRY_RUN=0
# Чтение конфигурационных файлов
for path in $(echo "$CONFIG_PATH"|tr ':' ' '); do
    if [[ -f "${path}/$CONFIG" ]]; then
	# shellcheck disable=SC1090
	source "${path}/$CONFIG"
	config_present=1
    fi
done

main() {
    local fn=${FUNCNAME[0]}
    local instance_address=$OPTTAIL
    local command=""

    trap 'except $LINENO' ERR
    trap _exit EXIT

    if (( ! DEBUG )); then
	exec 4>&2		# Link file descriptor #4 with stderr. Preserve stderr
	exec 2>>"$LOGERR"	# stderr replaced with file $LOGERR
    fi
    # Проверка наличия нужных бинарников
    for i in $BIN_REQUIRED; do
        if ! hash "$i" 2>/dev/null
        then
            echo "Required binary '$i' is not installed" >&2
            false
        fi
    done

    if (( STRIP_LAST_DASH_IN_ADDRESS )); then
        local instance_catalog=${OPTTAIL%-*}
    else
        local instance_catalog=${OPTTAIL}
    fi

    checks_main

    if [[ $PG_VERSION == "DEFAULT" ]]; then
        command=/usr/bin/pg_basebackup
    else
        command=/usr/pgsql-${PG_VERSION}/bin/pg_basebackup
    fi

    if [[ ! -d "${BASEDIR}/$instance_catalog" ]]; then
	if (( DEBUG )); then
	    echo "RUN: mkdir \"${BASEDIR}/$instance_catalog\"" >&2
	fi
	if (( ! DRY_RUN )); then
	    mkdir "${BASEDIR}/$instance_catalog"
	fi
    fi

    cd "${BASEDIR}/$instance_catalog" || exit 1
    # Удаление всех каталогов в текущем, оставляя только (( BACKUP_DEPTH - 1 ))
    if (( DEBUG )); then
	# shellcheck disable=SC2028
	echo "RUN: find . -maxdepth 1 -mindepth 1 -type d -printf '%P\n' | sort -r | tail -n +$BACKUP_DEPTH | xargs rm -rf --" >&2
    fi
    if (( ! DRY_RUN )); then
	find . -maxdepth 1 -mindepth 1 -type d -printf '%P\n' | sort -r | tail -n +$BACKUP_DEPTH | xargs rm -rf --
    fi

    if (( DEBUG )); then
	echo "RUN: $command --host=$instance_address --username=$BAKUSER --pgdata=$BAKDIR --no-password" >&2
    fi
    if (( ! DRY_RUN )); then
	$command --host=$instance_address --username=$BAKUSER --pgdata="$BAKDIR" --no-password
    fi

    exit 0
}

checks_main() {
    local fn=${FUNCNAME[0]}

    if [[ $(whoami) != "$RUNUSER" ]]; then
        echo "This script must be run as '$RUNUSER' user" >&2
        false
    fi

    if (( ! BACKUP_DEPTH )); then
        echo "Required variable 'BACKUP_DEPTH' (int) missing in configuration file '$CONFIG'" >&2
        false
    fi

    if [[ -z $instance_address ]]; then
        echo "Required parameter (instance address) is missing" >&2
        false
    fi

    if [[ ! -d "${BASEDIR}/$instance_catalog" ]]; then
        mkdir "${BASEDIR}/$instance_catalog"
    fi

    if [[ ! -r "$pgpass" ]]; then
        echo "PostgreSQL authorization file ($pgpass) is missing or unreadable" >&2
        false
    fi

    if ! grep -Fq $instance_catalog "$pgpass"
    then
        echo "PostgreSQL authorization file ($pgpass) is not contains authentication data for '$instance_address' address." >&2
        false
    fi

    if (( ! config_present )); then
        echo "Configuration file '$CONFIG' not found in '$CONFIG_PATH'" >&2
        false
    fi
}

except() {
    local ret=$?
    local no=${1:-no_line}

    if (( ! NOMAIL )); then
        echo -e "\tПроизошла ошибка при выполнении скрипта ${0} (строка ${no}, функция '$fn'), 
выполняющего полное копирование СУБД PostgreSQL посредством команды pg_basebackup с хоста *${instance_address}*.
\tВывод сбойной команды:\n\n  $(awk '$1=$1' ORS=' ' "${LOGERR}")" | mailx -s "$MAIL_SUBJ" $MAILXTO
    fi

    if [[ -t 1 ]]; then
        echo "* FATAL: error occured in function '$fn' on line ${no}. Output: '$(awk '$1=$1' ORS=' ' "${LOGERR}")'" 1>&2
    fi

    logger -p user.err -t "$bn" "* FATAL: error occured in function '$fn' on line ${no}. Output: '$(awk '$1=$1' ORS=' ' "${LOGERR}")'"
    exit $ret
}

_exit() {
    local ret=$?
    local -i bakdir_size=0

    if (( ! DEBUG )); then
	exec 2>&4 4>&-	# Restore stderr and close file descriptor #4
    fi

    if [[ -d "${BASEDIR}/${instance_catalog}/$BAKDIR" ]]; then
        bakdir_size=$(du -sb "${BASEDIR}/${instance_catalog}/$BAKDIR"|awk '{ print $1 }')
        # Если размер полученного каталога с бэкапом составляет менее 2M, то бэкап признаётся неудавшимся и каталог удаляется
        if (( bakdir_size < 2000000 )); then
            rm -rf "${BASEDIR:?}/${instance_catalog}/$BAKDIR"
        fi
    fi

    [[ -f $LOGERR ]] && rm "$LOGERR"
    exit $ret
}

usage() {
    echo -e "\tUsage: $bn [OPTIONS] <postgresql_instance_address>\n
    Options:

    --basedir, -b <path>	BASEDIR (default: '$BASEDIR')
    --depth, -D <n>		number of stored backups
    --strip-last-dash, -s	strip last dash-separated part of instance address
    --pg-version, -V		PostgreSQL version in format N.N
    --debug, -d			print some additional info
    --dry-run, -n		do not make action, print info only (with -d)
    --help, -h			print this text
"
}
# Getopts
getopt -T; (( $? == 4 )) || { echo "incompatible getopt version" >&2; exit 4; }

if ! TEMP=$(getopt -o b:D:V:sdnh --longoptions basedir:,depth:,strip-last-dash,pg-version:,debug,dry-run,help -n "$bn" -- "$@")
then
    echo "Terminating..." >&2
    exit 1
fi

eval set -- "$TEMP"
unset TEMP

while true; do
    case $1 in
	-b|--basedir)		BASEDIR=$2 ;	shift 2	;;
	-D|--depth)		BACKUP_DEPTH=$2 ;		shift 2	;;
	-V|--pg-version)	PG_VERSION=$2 ;	shift 2	;;
	-s|--strip-last-dash)	STRIP_LAST_DASH_IN_ADDRESS=1 ;	shift	;;
	-d|--debug)		DEBUG=1 ;	shift	;;
	-n|--dry-run)		DRY_RUN=1 ;	shift	;;
	-h|--help)		usage ;		exit 0	;;
	--)			shift ;		break	;;
	*)			usage ;		exit 1
    esac
done

OPTTAIL="$*"

if [[ "${1:-NOP}" == "NOP" ]]; then
    usage
    exit 1
fi

main

## EOF ##
