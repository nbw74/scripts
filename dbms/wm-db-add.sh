#!/bin/bash
#
# Script fir adding required credentials in pg_hba.conf
# and pgbouncer configs
#

set -E
set -o nounset

# DEFAULTS BEGIN
typeset MARK="MARK ONE"
typeset pgbouncer_ini="/etc/pgbouncer/pgbouncer.ini"
typeset userlist="/etc/pgbouncer/userlist.txt"
# DEFAULTS END

# CONSTANTS BEGIN
readonly PATH=/bin:/usr/bin:/sbin:/usr/sbin
readonly bn="$(basename $0)"
readonly LOGERR=$(mktemp --tmpdir ${bn%\.*}.XXXX)
readonly BIN_REQUIRED="pgrep diff colordiff"
# CONSTANTS END

main() {
    local fn=${FUNCNAME[0]}
    local bak=""

    trap 'except $LINENO' ERR
    trap _exit EXIT
# Required binaries check
    for i in $BIN_REQUIRED; do
        if ! hash $i 2>/dev/null
        then
            echo "Required binary '$i' is not installed" >$LOGERR
            false
        fi
    done

    checks

    bak="$(date '+%FT%H%M%S').bak"
    pgHBA
    pgbouncerIni
    pgbouncerUserlist

    exit 0
}

pgHBA() {
    local fn=${FUNCNAME[0]}
    local data=""
    local pg_hba="pg_hba.conf"
    local mark="## $MARK ##"

    echo_info "Finding PostgreSQL data directory from process commandline..."

    data=$(pgrep -af '.*(postgres|postmaster)\s+-D\s+.*'|awk '{ match($0, /-D[[:space:]]+[/.a-z0-9]+/); dir=substr($0, RSTART, RLENGTH); sub(/-D[[:space:]]+/, "", dir); print dir }')

    if [[ -z "$data" ]]; then
        echo_err "No PostgreSQL data directory found. Database process is not running?"
        false
    fi

    if grep -Pq "\s+$USERNAME\s+" ${data}/$pg_hba
    then
        echo_err "User already exist in the ${data}/$pg_hba"
        false
    fi

    cp -a ${data}/$pg_hba /root/${pg_hba}-$bak
    echo_info "Modifying ${data}/$pg_hba"
    sed -i "/${mark}/i \
host\t${USERNAME}\t${USERNAME}\t127.0.0.1/32\t\tmd5" "${data}/$pg_hba"
    diff -u "/root/${pg_hba}-$bak" "${data}/$pg_hba" | colordiff
}

pgbouncerIni() {
    local fn=${FUNCNAME[0]}
    local mark=";; $MARK"

    if grep -Pq "=$USERNAME" ${pgbouncer_ini}
    then
        echo_err "User already exist in the ${pgbouncer_ini}"
        false
    fi

    cp -a ${pgbouncer_ini} /root/${pgbouncer_ini##*\/}-$bak
    echo_info "Modifying ${pgbouncer_ini}"
    sed -i "/${mark}/i \
${USERNAME} = host=127.0.0.1 dbname=${USERNAME} user=${USERNAME} pool_size=40" "$pgbouncer_ini"
    diff -u "/root/${pgbouncer_ini##*\/}-$bak" "$pgbouncer_ini" | colordiff
}

pgbouncerUserlist() {
    local fn=${FUNCNAME[0]}

    if grep -Pq "\"$USERNAME\"" ${userlist}
    then
        echo_err "User already exist in the ${userlist}"
        false
    fi

    cp -a ${userlist} /root/${userlist##*\/}-$bak
    echo_info "Modifying ${userlist}"
    echo -e "\"$USERNAME\"\t\"$PASSWORD\"" >> "$userlist"
    diff -u "/root/${userlist##*\/}-$bak" "$userlist" | colordiff
}

checks() {
    local fn=${FUNCNAME[0]}

    if [[ -z "$USERNAME" || -z "$PASSWORD" ]]; then
        echo_err "Required parameter missing (see -h)"
        false
    fi
}

except() {
    local ret=$?
    local no=${1:-no_line}

    if [[ -t 1 ]]; then
        echo_fatal "error occured in function '$fn' on line ${no}. Output: '$(awk '$1=$1' ORS=' ' ${LOGERR})'"
    fi

    logger -p user.err -t "$bn" "* FATAL: error occured in function '$fn' on line ${no}. Output: '$(awk '$1=$1' ORS=' ' ${LOGERR})'"
    exit $ret
}

_exit() {
    local ret=$?

    [[ -f $LOGERR ]] && rm "$LOGERR"
    exit $ret
}

usage() {
    echo -e "\n\tUsage: $bn [OPTIONS] <parameter>\n
    Options:

    -u <string>     database user (REQUIRED)
    -p <string>     password of this user (REQUIRED)
    -h              print help
"
}

while getopts "u:p:h" OPTION; do
    case $OPTION in
        u)
            USERNAME=$OPTARG
            ;;
        p)
            PASSWORD=$OPTARG
            ;;
        h)
            usage; exit 0
            ;;
        *) usage; exit 1
    esac
done

if [[ "${1:-NOP}" == "NOP" ]]; then
    usage
    exit 1
fi

readonly C_RST="tput sgr0"
readonly C_RED="tput setaf 1"
readonly C_GREEN="tput setaf 2"
readonly C_YELLOW="tput setaf 3"
readonly C_BLUE="tput setaf 4"
readonly C_CYAN="tput setaf 6"
readonly C_WHITE="tput setaf 7"

echo_err() { $C_WHITE; echo "* ERROR: $*" 1>&2; $C_RST; }
echo_fatal() { $C_RED; echo "* FATAL: $*" 1>&2; $C_RST; }
echo_warn() { $C_YELLOW; echo "* WARNING: $*" 1>&2; $C_RST; }
echo_info() { $C_RST; echo "* INFO: $*" 1>&2; $C_RST; }
echo_ok() { $C_GREEN; echo "* OK" 1>&2; $C_RST; }

main

## EOF ##
