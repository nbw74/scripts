#!/bin/bash
#
# Shell script template
#

set -E
set -o nounset

# DEFAULTS BEGIN
typeset URI=""
typeset PASSWORD=""
# DEFAULTS END

# CONSTANTS BEGIN
readonly PATH=/bin:/usr/bin:/sbin:/usr/sbin
readonly bn="$(basename "$0")"
readonly LOGERR=$(mktemp --tmpdir "${bn%\.*}.XXXX")
readonly SESSDIR=$(mktemp --directory --tmpdir "${bn%\.*}.XXXX")
readonly BIN_REQUIRED=""
# CONSTANTS END

main() {
    local fn=${FUNCNAME[0]}
    local filename=${URI##*\/}
    local cn=${filename%-*}

    trap 'except $LINENO' ERR
    trap _exit EXIT

    install

    echo_info "Downloading archive"
    cd "$SESSDIR" || false
    wget -q "$URI" >/dev/null 2>"$LOGERR"

    echo_info "Unpacking archive"
    7za x -p$PASSWORD "${filename}" >/dev/null 2>"$LOGERR"

    echo_info "Copying configs"
    cd "${filename%.*}" || false
    cp --preserve=mode,timestamps ca.crt "${cn}.crt" "${cn}.key" "${cn}.conf" /etc/openvpn/ 2>"$LOGERR"
    cd /tmp || false

    service

    echo_ok
    exit 0
}

service() {
    local fn=${FUNCNAME[0]}

    echo_info "Starting service (systemctl)"
    systemctl enable --now "openvpn@${cn}" >/dev/null 2>"$LOGERR"
}

install() {
    local fn=${FUNCNAME[0]}

    echo_info "Installing packages (yum)"
    yum -y -q install wget p7zip openvpn >/dev/null 2>"$LOGERR"
}

checks() {
    local fn=${FUNCNAME[0]}

    if (( EUID != 0 )); then
        echo "Please run this script with superuser rights" >"$LOGERR"
        false
    fi
    # Required binaries check
    for i in $BIN_REQUIRED; do
        if ! hash "$i" 2>/dev/null
        then
            echo "Required binary '$i' is not installed" >"$LOGERR"
            false
        fi
    done
}

except() {
    local ret=$?
    local no=${1:-no_line}

    if [[ -t 1 ]]; then
        echo_fatal "* FATAL: error occured in function '$fn' on line ${no}. Output: '$(awk '$1=$1' ORS=' ' "${LOGERR}")'" 1>&2
    fi

    logger -p user.crit -t "$bn" "* FATAL: error occured in function '$fn' on line ${no}. Output: '$(awk '$1=$1' ORS=' ' "${LOGERR}")'"
    exit $ret
}

_exit() {
    local ret=$?

    [[ -f $LOGERR ]] && rm "$LOGERR"
    [[ -d $SESSDIR ]] && rm -rf "$SESSDIR"
    exit $ret
}

readonly C_RST="tput sgr0"
readonly C_RED="tput setaf 1"
readonly C_GREEN="tput setaf 2"

echo_fatal() { $C_RED; echo "* FATAL: $*" 1>&2; $C_RST; }
echo_info() { $C_RST; echo "* INFO: $*" 1>&2; $C_RST; }
echo_ok() { $C_GREEN; echo "* OK" 1>&2; $C_RST; }

main

## EOF ##
