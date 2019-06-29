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
readonly bn="$(basename "$0")"
readonly LOGERR=$(mktemp --tmpdir "${bn%\.*}.XXXX")
readonly BIN_REQUIRED="aunpack dos2unix"
typeset -a ping_opts=( '-i0.2' '-W1' '-c5' '-q' )
# CONSTANTS END

typeset OPTTAIL="" ADDRESS="" REALM=""

main() {
    local fn=${FUNCNAME[0]}
    local cert=""

    trap 'except $LINENO' ERR
    trap _exit EXIT

    _checks

    aunpack $OPTTAIL
    if [[ -f "${OPTTAIL%\.*}.key" ]]; then
	mv ${OPTTAIL%\.*}.key ${OPTTAIL%\.*}/
    fi
    cd ${OPTTAIL%\.*} || false

    cert=$(find . -maxdepth 1 -type f -regextype sed -regex '.*/[-_a-z0-9]\+_[a-z]\+\.crt'  -printf '%P\n' -quit)
    local cert_final=${cert//_/.}
    local domain=${cert_final%\.*}

    if [[ -f "${cert%\.*}.ca-bundle" ]]; then
        cat "$cert" "${cert%\.*}.ca-bundle" > "$cert_final"
    elif [[ -f COMODORSADomainValidationSecureServerCA.crt && -f COMODORSAAddTrustCA.crt && -f AddTrustExternalCARoot.crt ]]; then
        cat "$cert" COMODORSADomainValidationSecureServerCA.crt COMODORSAAddTrustCA.crt AddTrustExternalCARoot.crt > "$cert_final"
    elif [[ -f SectigoRSADomainValidationSecureServerCA.crt && -f USERTrustRSAAddTrustCA.crt && -f AddTrustExternalCARoot.crt ]]; then
        cat "$cert" SectigoRSADomainValidationSecureServerCA.crt USERTrustRSAAddTrustCA.crt AddTrustExternalCARoot.crt > "$cert_final"
    else
        echo_err "Unknown certificate layout"
	false
    fi

    dos2unix "$cert_final"

    if [[ -f "${OPTTAIL%\.*}.key" ]]; then
	mv ${OPTTAIL%\.*}.key "${domain}.key"
	dos2unix "${domain}.key"
    fi

    if [[ -z "$REALM" ]]; then

	if [[ -z "$ADDRESS" ]]; then
	    echo_info "remote server isn't specified, using '$domain'"

	    ADDRESS=$(dig +short "$domain"|head -1)

	    if [[ -z "$ADDRESS" ]]; then
		echo_err "cannot resolve '$domain'"
		false
	    fi
	fi

	if ! ping "${ping_opts[@]}" "$ADDRESS" >/dev/null
	then
	    echo_err "'$ADDRESS' is unreachable"
	    false
	fi

	echo_info "try scp files to '$ADDRESS'..."
	scp "$cert_final" "${domain}.key" "${ADDRESS}":

    else

	mkdir -p "${HOME}/ansible/${REALM}/files/crypto"

	if [[ -f "${domain}.key" ]]; then
	    cp -v "${domain}.key" "${HOME}/ansible/${REALM}/files/crypto"
	fi

	cp -v "$cert_final" "${HOME}/ansible/${REALM}/files/crypto"

    fi

    echo_ok
    exit 0
}

_checks() {
    local fn=${FUNCNAME[0]}

# Required binaries check
    for i in $BIN_REQUIRED; do
        if ! hash $i 2>/dev/null
        then
            echo "Required binary '$i' is not installed"
            false
        fi
    done
}

except() {
    local ret=$?
    local no=${1:-no_line}

    if [[ -t 1 ]]; then
        echo_info "rollback." 1>&2
    fi

    if [[ -f ${domain}.key ]]; then
        mv "${domain}.key" ../${OPTTAIL%\.*}.key || :
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
    echo -e "\\tUsage: $bn [OPTIONS] <(zip-)archive with certificates>\\n
    Options:

    -a, --address <ipaddr>	IP address for scp
    -l, --local <REALM>		copy cert in local catalog ~/ansible/REALM/files/crypto
    -h, --help			print help
"
}

# Getopts
getopt -T; (( $? == 4 )) || { echo "incompatible getopt version" >&2; exit 4; }

if ! TEMP=$(getopt -o a:l:h --longoptions address:,local:,help -n "$bn" -- "$@")
then
    echo "Terminating..." >&2
    exit 1
fi

eval set -- "$TEMP"
unset TEMP

while true; do
    case $1 in
        -a|--address)       ADDRESS=$2 ;    shift 2 ;;
	-l|--local)	    REALM=$2 ;	    shift 2 ;;
        -h|--help)          usage ;         exit 0  ;;
        --)                 shift ;         break   ;;
        *)                  usage ;         exit 1
    esac
done

OPTTAIL="$*"

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
