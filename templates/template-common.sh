#!/bin/bash
#
# Shell script template
#

set -o nounset
set -o errtrace
set -o pipefail

# DEFAULTS BEGIN
typeset -i DEBUG=0
# DEFAULTS END

# CONSTANTS BEGIN
readonly PATH=/bin:/usr/bin:/sbin:/usr/sbin
readonly bn="$(basename "$0")"
readonly LOGERR=$(mktemp --tmpdir "${bn%\.*}.XXXX")
readonly BIN_REQUIRED=""
# CONSTANTS END

main() {
    local fn=${FUNCNAME[0]}

    trap 'except $LINENO' ERR
    trap _exit EXIT

    if (( ! DEBUG )); then
	exec 4>&2		# Link file descriptor #4 with stderr. Preserve stderr
	exec 2>>"$LOGERR"	# stderr replaced with file $LOGERR
    fi

    checks

    exit 0
}

checks() {
    local fn=${FUNCNAME[0]}
    # Required binaries check
    for i in $BIN_REQUIRED; do
        if ! command -v "$i" >/dev/null
        then
            echo "Required binary '$i' is not installed" >&2
            false
        fi
    done
}

except() {
    local ret=$?
    local no=${1:-no_line}

    if [[ -t 1 ]]; then
        echo_fatal "error occured in function '$fn' near line ${no}. Stderr: '$(awk '$1=$1' ORS=' ' "${LOGERR}")'"
    fi

    logger -p user.err -t "$bn" "* FATAL: error occured in function '$fn' near line ${no}. Stderr: '$(awk '$1=$1' ORS=' ' "${LOGERR}")'"
    exit $ret
}

_exit() {
    local ret=$?

    if (( ! DEBUG )); then
	exec 2>&4 4>&-	# Restore stderr and close file descriptor #4
    fi

    [[ -f $LOGERR ]] && rm "$LOGERR"
    exit $ret
}

usage() {
    echo -e "\\n    Usage: $bn [OPTIONS] <parameter>\\n
    Options:

    -a, --arg1 <value>		example argument
    -d, --debug			debug mode
    -h, --help			print help
"
}
# Getopts
getopt -T; (( $? == 4 )) || { echo "incompatible getopt version" >&2; exit 4; }

if ! TEMP=$(getopt -o a:h --longoptions arg1:,help -n "$bn" -- "$@")
then
    echo "Terminating..." >&2
    exit 1
fi

eval set -- "$TEMP"
unset TEMP

while true; do
    case $1 in
	-a|--arg1)		FLAG=$2 ;	shift 2	;;
	-d|--debug)		DEBUG=1 ;	shift	;;
	-h|--help)		usage ;		exit 0	;;
	--)			shift ;		break	;;
	*)			usage ;		exit 1
    esac
done

echo_err()      { tput setaf 7; echo "* ERROR: $*" ;   tput sgr0;   }
echo_fatal()    { tput setaf 1; echo "* FATAL: $*" ;   tput sgr0;   }
echo_warn()     { tput setaf 3; echo "* WARNING: $*" ; tput sgr0;   }
echo_info()     { tput setaf 6; echo "* INFO: $*" ;    tput sgr0;   }
echo_ok()       { tput setaf 2; echo "* OK" ;          tput sgr0;   }

if [[ "${1:-NOP}" == "NOP" ]]; then
    usage
    exit 1
fi

main

## EOF ##
