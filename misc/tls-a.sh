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
# CONSTANTS END

typeset OPTTAIL="" IPADDR=""

main() {
    local fn=$FUNCNAME

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

    aunpack $OPTARG
    cd ${OPTARG%\.*}

    local cert=$(ls -1 *.crt|head -1)
    local cert_final=${cert//_/.}
    local domain=${cert_final%\.*}

    cat $cert ${cert%\.*}.ca-bundle > $cert_final
    mv ../${OPTARG%\.*}.key ${domain}.key

    if [[ -n "$IPADDR" ]]; then
        scp $cert_final ${domain}.key ${IPADDR}:
    fi

    exit 0
}

except() {
    local ret=$?
    local no=${1:-no_line}

    if [[ -t 1 ]]; then
        echo "* FATAL: error occured in function '$fn' on line ${no}. Output: '$(cat ${LOGERR}|awk '$1=$1' ORS=' ')'" 1>&2
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
            IPADDR=$OPTARG
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

main

## EOF ##
