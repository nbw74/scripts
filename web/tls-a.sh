#!/bin/bash
#
# Shell script template
#

set -E
set -o nounset

# DEFAULTS BEGIN
# DEFAULTS END

# CONSTANTS BEGIN
readonly PATH=/bin:/usr/bin:/sbin:/usr/sbin
readonly bn="$(basename $0)"
readonly LOGERR=$(mktemp --tmpdir ${bn%\.*}.XXXX)
readonly BIN_REQUIRED="aunpack"
readonly ping_opts="-i0.2 -W1 -c5 -q"
# CONSTANTS END

typeset OPTTAIL="" ADDRESS=""

main() {
    local fn=${FUNCNAME[0]}
    local cert=""

    trap 'except $LINENO' ERR
    trap _exit EXIT
# Required binaries check
    for i in $BIN_REQUIRED; do
        if ! hash $i 2>/dev/null
        then
            echo "Required binary '$i' is not installed"
            false
        fi
    done

    aunpack $OPTTAIL
    mv ${OPTTAIL%\.*}.key ${OPTTAIL%\.*}/
    cd ${OPTTAIL%\.*} || false

    cert=$(find . -maxdepth 1 -type f -name '*.crt' -printf '%P\n' -quit)
    local cert_final=${cert//_/.}
    local domain=${cert_final%\.*}

    cat $cert ${cert%\.*}.ca-bundle > $cert_final
    mv ${OPTTAIL%\.*}.key ${domain}.key

    if [[ -z "$ADDRESS" ]]; then
        echo_info "remote server isn't specified, using '$domain'"

        ADDRESS=$(dig +short $domain|head -1)

        if [[ -z "$ADDRESS" ]]; then
            echo_err "cannot resolve '$domain'"
            false
        fi
    fi

    if ! ping $ping_opts $ADDRESS >/dev/null
    then
        echo_err "'$ADDRESS' is unreachable"
        false
    fi

    echo_info "try scp files to '$ADDRESS'..."
    scp $cert_final ${domain}.key ${ADDRESS}:

    echo_ok
    exit 0
}

except() {
    local ret=$?
    local no=${1:-no_line}

    if [[ -t 1 ]]; then
        echo_info "rollback." 1>&2
    fi

    if [[ -f ${domain}.key ]]; then
        mv ${domain}.key ../${OPTTAIL%\.*}.key || :
    fi

    cd .. || :

    if [[ -d ${OPTTAIL%\.*} ]]; then
        rm -r ${OPTTAIL%\.*} || :
    fi

    if [[ -t 1 ]]; then
        echo_fatal "error occured in function '$fn' on line ${no}." 1>&2
    fi

    logger -p user.err -t "$bn" "* FATAL: error occured in function '$fn' on line ${no}."
    exit $ret
}

_exit() {
    local ret=$?

    [[ -f $LOGERR ]] && rm "$LOGERR"
    exit $ret
}

usage() {
    echo -e "\tUsage: $bn [OPTIONS] <(zip-)archive with certificates>\n
    Options:

    -a <ipaddr> IP address for scp
    -h          print help
"
}

while getopts "a:h" OPTION; do
    case $OPTION in
        a)
            ADDRESS=$OPTARG
            ;;
        h)
            usage; exit 0
    esac
done

shift "$((OPTIND - 1))"

OPTTAIL="$*"

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
echo_info() { $C_BLUE; echo "* INFO: $*" 1>&2; $C_RST; }
echo_ok() { $C_GREEN; echo "* OK" 1>&2; $C_RST; }

main

## EOF ##
