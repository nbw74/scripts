#!/bin/bash
# shellcheck disable=SC2317
#
# Use whisper.cpp by simple way
#

set -o nounset
set -o errtrace
set -o pipefail

# DEFAULTS BEGIN
typeset -i DEBUG=0 FORCE_REWRITE=0
typeset MEDIA_FILE="" OUTPUT_FILE="" GGML_MODEL="large-v3-turbo"
# DEFAULTS END

# CONSTANTS BEGIN
PATH=/bin:/usr/bin:/sbin:/usr/sbin
readonly WHISPER_PATH="${HOME}/projects/github/ggml-org/whisper.cpp"

typeset bn=""
bn="$(basename "$0")"
readonly bn

readonly BIN_REQUIRED="gawk ffmpeg file realpath"
# CONSTANTS END

main() {
    local fn=${FUNCNAME[0]}

    trap 'except $LINENO' ERR
    trap _exit EXIT

    checks

    (( DEBUG )) && set -xv

    MEDIA_FILE="$(realpath "$MEDIA_FILE")"
    local media_file_no_ext="${MEDIA_FILE%.*}"

    local filetype=""

    filetype=$(file -b --mime-type "$MEDIA_FILE" | awk -F '/' '{ print $1 }')

    if [[ $filetype == "video" ]]
    then
	echo_info "File has video mime-type, try to convert..."

	if [[ -e "${media_file_no_ext}.ogg" && $FORCE_REWRITE == 0 ]]
	then
	    echo_err "Output audio file '${media_file_no_ext}.ogg' already exists and --force not given, cannot continue"
	    false
	else
	    ffmpeg -y -i "$MEDIA_FILE" -vn -c:a libvorbis -q:a 5 "${media_file_no_ext}.ogg"
	    MEDIA_FILE="${media_file_no_ext}.ogg"
	fi
    elif [[ $filetype == "audio" ]]
    then
	echo_info "File has audio mime-type, processing..."
    else
	echo_err "File has unsupported mime-type, panic"
	false
    fi

    if [[ "${OUTPUT_FILE:-nul}" == "nul" ]]
    then
	OUTPUT_FILE="${media_file_no_ext}"
    fi

    if [[ -e "${OUTPUT_FILE}.txt" && $FORCE_REWRITE == 0 ]]
    then
	echo_err "Output file '${OUTPUT_FILE}.txt' already exists and --force not given, cannot continue"
	false
    fi

    set +o nounset
    source /opt/intel/oneapi/setvars.sh
    set -o nounset

    cd "$WHISPER_PATH" || false

    build/bin/whisper-cli --print-colors --print-progress --language ru --model "models/ggml-${GGML_MODEL}.bin" --file "$MEDIA_FILE" --output-txt --output-file "${OUTPUT_FILE}"

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

    echo_fatal "error occured in function '$fn' near line ${no}."
    exit $ret
}

_exit() {
    local ret=$?
    exit $ret
}

usage() {
    echo -e "\\n    Usage: $bn [OPTIONS] <input audio or video file>\\n
    Options:

    -m, --model <name>		GGML model name; default: large-v3-turbo
    -o, --output <path>		output text file name (without extension); default is same as input file path
    -f, --force			force overwrite existing output file(s)
    -d, --debug			debug mode
    -h, --help			print help

	Available models:
"

    cd "${WHISPER_PATH}/models" || false
    # shellcheck disable=SC2012
    ls -lh ggml-*.bin | awk '{ name=$9; sub(/^ggml-/, "", name); sub(/\.bin$/, "", name); print $5 "\t" name }' | sort -h | column -t -N SIZE,NAME | awk '{ print "\t" $0 }'

    echo
}
# Getopts
getopt -T; (( $? == 4 )) || { echo "incompatible getopt version" >&2; exit 4; }

if ! TEMP=$(getopt -o m:fdh --longoptions model:,force,debug,help -n "$bn" -- "$@")
then
    echo "Terminating..." >&2
    exit 1
fi

eval set -- "$TEMP"
unset TEMP

while true; do
    case $1 in
	-m|--model)		GGML_MODEL=$2 ;		shift 2	;;
	-o|--output)		OUTPUT_FILE=$2 ;	shift 2	;;
	-f|--force)		FORCE_REWRITE=1 ;	shift	;;
	-d|--debug)		DEBUG=1 ;		shift	;;
	-h|--help)		usage ;			exit 0	;;
	--)			shift ;			break	;;
	*)			usage ;			exit 1
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
else
    MEDIA_FILE="$1"
fi

main

## EOF ##
