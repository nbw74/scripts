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
readonly BIN_REQUIRED=""
# CONSTANTS END

main() {
    local fn=$FUNCNAME

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

    exit 0
}

except() {
    local ret=$?
    local no=${1:-no_line}

    if [[ -t 1 ]]; then
        echo "* FATAL: error occured in function '$fn' on line ${no}. Output: '$(cat ${LOGERR}|awk '$1=$1' ORS=' ')'" 1>&2
    fi

    logger -p user.err -t "$bn" "* FATAL: error occured in function '$fn' on line ${no}. Output: '$(cat ${LOGERR}|awk '$1=$1' ORS=' ')'"
    exit $ret
}

_exit() {
    local ret=$?

    [[ -f $LOGERR ]] && rm "$LOGERR"
    exit $ret
}

usage() {
    echo -e "\tUsage: $bn [OPTIONS] <parameter>\n
    Options:

    -h      print help
"
}

while getopts "h" OPTION; do
    case $OPTION in
        h) usage; exit 0
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
