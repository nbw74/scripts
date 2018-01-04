#!/bin/bash
#
# Враппер для конверсии wav в ogg
# (для использования на IP-PBX)
#

readonly PATH=/bin:/usr/bin

set -o nounset
set -E

typeset QUIET="" WAVDIR=""
typeset -i FULL=0 NO_RM=0
export QUALITY=3

main() {

    trap 'except INT'   SIGINT
    trap 'except TERM'  SIGTERM
    trap 'except ERR'   ERR

    if [[ -z $WAVDIR ]]; then
        usage
        exit 1
    fi

    if (( FULL == 0 )); then
        WAVDIR="${WAVDIR}/$(date +%Y/%m/%d)"
    fi

    find $WAVDIR -type f -name '*.wav' -exec bash -c 'convert "$0"' '{}' \;
}

convert() {
    local -i oggsize=0
    local wavfile="$(basename $1)"
    local oggfile="$(basename $1 .wav).ogg"

    cd $(dirname $1)
    if [[ ! -f "$oggfile" ]]; then
        oggenc $QUIET -q$QUALITY -o "$oggfile" "$wavfile"
    fi

    oggsize=$(stat --format='%s' "${oggfile}")
    if (( oggsize > 0 )); then
        if (( NO_RM == 0 )); then
            rm "$wavfile"
        fi
    else
        echo "WARNING! Zero-sized OGG file detected." 1>&2
    fi
}

export -f convert

except() {
    RET=$?

    echo "ERROR: signal ${1:-(U)} received." 1>&2
    exit $RET
}

usage() {
    echo -e "Usage: $(basename $0) <option(s)>
        Options:
        -d <>       directory contains .wav files (with full path) (REQUIRED)
        -q N        quality (1-10)
        -Q          quiet mode
        -f          full subdirectories scan (instead of '+%Y/%m/%d')
        -R          do not remove .wav files after conversion
        -h          print help
        "
}

while getopts "d:fQq:Rh" OPTION; do
    case $OPTION in
        d) WAVDIR=$OPTARG
            ;;
        q) QUALITY=$OPTARG; export QUALITY
            ;;
        Q) QUIET="-Q"; export QUIET
            ;;
        f) FULL=1
            ;;
        R) NO_RM=1; export NO_RM
            ;;
        h) usage
            exit 0
            ;;
        *) usage
            exit 1
    esac
done

if [[ ${1:-NOP} == "NOP" ]]; then
    usage
    exit 1
fi

main
