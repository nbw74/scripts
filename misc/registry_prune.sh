#!/bin/bash
#
# Remove old images from docker registry
# by nbw 2018 A.D.
#
set -o nounset
set -o errtrace
set -o pipefail

# CONSTANTS BEGIN
readonly PATH=/bin:/usr/bin:/sbin:/usr/sbin
readonly bn="$(basename "$0")"
readonly LOGERR=$(mktemp --tmpdir "${bn%\.*}.XXXX")
readonly BIN_REQUIRED=""
readonly -a curl_opts=( --connect-timeout 4 --max-time 20 -sS )
readonly -a curl_opts1=( -H "Accept: application/vnd.docker.distribution.manifest.v2+json" )
# CONSTANTS END

# DEFAULTS BEGIN
typeset URL="" REPOS=""
typeset -i COUNT=0 DAYS=0 VERBOSE=0 DRY_RUN=0
# DEFAULTS END

main() {
    local fn=${FUNCNAME[0]}

    trap 'except $LINENO' ERR
    trap _exit EXIT

    touch "$LOGERR"
    exec 4>&2		# Link file descriptor #4 with stderr. Preserve stderr
    exec 2>>"$LOGERR"	# stderr replaced with file $LOGERR

    checks

    local -i deadline=0		# если тэг старше этой epoch, то он удаляется
    deadline=$(date --date="$DAYS days ago" +"%s")
    _ifzero "$deadline"

    local -a Repos=()		# Массив для хранения имен репозиториев

    if [[ "${REPOS:-NOP}" == "NOP" ]]; then
	mapfile -t Repos < <( curl "${curl_opts[@]}" -X GET "${URL}/v2/_catalog" | jq -r '.repositories | .[]' )
    else
	read -r -a Repos < <( echo "$REPOS" | awk 'BEGIN { FS=","; OFS=" " } { $1=$1; print $0 }' )
    fi

    _ifnull Repos "${Repos[*]:-NOP}"
    _verbose "${#Repos[@]} repositories found."

    for (( r = 0; r < ${#Repos[@]}; r++ )); do
	_verbose "Current repository: '${Repos[r]}'"

	local -a Tags=()	# Тэги в данном репозитории
	local -a Candidates=()	# Кандидаты на удаление
	local -A Taglist=()	# Хэш вида [tag]="tag_time_epoch"
	local -a TaglistTail=()	# Последние COUNT ключей хэша Taglist

	mapfile -t Tags < <( curl "${curl_opts[@]}" -X GET "${URL}/v2/${Repos[r]}/tags/list" | jq -r '.tags | .[]' )

	if [[ "${Tags[*]:-NOP}" == "NOP" ]]; then
	    _verbose "0 tags found, skip pruning"
	    continue
	else
	    _verbose "${#Tags[@]} tags found."
	fi

	for (( t = 0; t < ${#Tags[@]}; t++ )); do
	    local tag_time_raw=""
	    local -i tag_time_epoch=0

	    tag_time_raw="$(curl "${curl_opts[@]}" -X GET "${URL}/v2/${Repos[r]}/manifests/${Tags[t]}" | \
		jq -r '.history[].v1Compatibility' | \
		jq -r '.created' | \
		sort | \
		tail -n1 )"
	    _ifnull tag_time_raw "${tag_time_raw:-NOP}"

	    tag_time_epoch=$(date --date="$tag_time_raw" +"%s")
	    _ifzero "$tag_time_epoch"

	    Taglist[${Tags[t]}]="$tag_time_epoch"

	    if (( tag_time_epoch < deadline )); then
		Candidates+=( "${Tags[t]}" )
	    fi

	    unset tag_time_raw tag_time_epoch
	done

	_ifnull Taglist "${Taglist[*]:-NOP}"

	mapfile -t TaglistTail < <(
	for k in "${!Taglist[@]}"; do
	    echo "$k" "${Taglist[$k]}"
	done | sort -k2,2n | tail -n$COUNT | awk '{ print $1 }'
	)

	_ifnull TaglistTail "${TaglistTail[*]:-NOP}"
	_verbose "${#TaglistTail[@]} newest tags found."

	if (( ${#TaglistTail[@]} < COUNT )); then
	    _verbose "Newest tags count < keep-count option value ($COUNT), skip pruning"
	    continue
	fi

	for (( c = 0; c < ${#Candidates[@]}; c++ )); do
	    local digest=""

	    if ! inArray TaglistTail "${Candidates[c]}"; then
		_verbose "Removing tag '${Candidates[c]}' ($((($(date +"%s")-$(date +"%s" --date "@${Taglist[${Candidates[c]}]}"))/(3600*24))) days old)"

		if (( ! DRY_RUN )); then
		    # Get tag digest
		    digest=$(curl "${curl_opts[@]}" "${curl_opts1[@]}" -IX GET "${URL}/v2/${Repos[r]}/manifests/${Candidates[c]}" | awk '/Docker-Content-Digest:/ { gsub(/\r/,""); print $2 }' )
		    # Delete manifest
		    curl "${curl_opts[@]}" "${curl_opts1[@]}" -X DELETE "${URL}/v2/${Repos[r]}/manifests/$digest"
		fi
	    fi

	    unset digest
	done

	unset Tags
	unset Candidates

    done

    exit 0
}

inArray() {
    local array="$1[@]"
    local seeking="$2"
    local -i in=1

    for e in ${!array}; do
        if [[ $e == "$seeking" ]]; then
            in=0
            break
        fi
    done

    return $in
}

_verbose() {
    local arg1="$1"

    if (( VERBOSE )); then
	echo "* INFO: $arg1"
    fi
}

_ifnull() {
    local fn=${FUNCNAME[0]}

    if [[ "$2" == "NOP" ]]; then
	echo "Variable or array '$1' is empty" >&2
	false
    fi
}

_ifzero() {
    local fn=${FUNCNAME[0]}
    local -i arg1=$1

    if (( ! arg1 )); then
	echo "Variable '$arg1' has zero value" >&2
	false
    fi
}

checks() {
    local fn=${FUNCNAME[0]}

    # Required binaries check
    for i in $BIN_REQUIRED; do
        if ! hash "$i" 2>/dev/null
        then
            echo "Required binary '$i' is not installed"
            false
        fi
    done

    if [[ -z "${URL}" || $COUNT == 0 || $DAYS == 0 ]]; then
	echo "Required parameter missing, see '-h'" >&2
	false
    fi

}

except() {
    local ret=$?
    local no=${1:-no_line}

    if [[ -t 1 ]]; then
	# shellcheck disable=SC1003
        echo "* FATAL: error occured in function '$fn' on line ${no}. Output: '$(awk '$1=$1' ORS='\\\\' "${LOGERR}")'"
    fi
    # shellcheck disable=SC1003
    logger -p user.err -t "$bn" "* FATAL: error occured in function '$fn' on line ${no}. Output: '$(awk '$1=$1' ORS='\\\\' "${LOGERR}")'"
    exit $ret
}

_exit() {
    local ret=$?

    exec 2>&4 4>&-	# Restore stderr and close file descriptor #4

    [[ -f $LOGERR ]] && rm "$LOGERR"
    exit $ret
}

usage() {
    echo -e "\\tUsage: $bn [OPTIONS] <parameter>\\n
    Options:

    -c, --keep-count n				keep at least n images
    -d, --keep-days n				keep images younger than n days
    -n, --dry-run				don't make any changes
    -r, --repos <name1[,name2,...]>		specify repo list manually
    -U, --registry <[schema]address:port>	docker registry URL
    -h, --help					print help
"
}
# Getopts
getopt -T; (( $? == 4 )) || { echo "incompatible getopt version" >&2; exit 4; }

if ! TEMP=$(getopt -o c:d:nr:U:vh --longoptions keep-count:,keep-days:,dry-run,repos:,registry:,verbose,help -n "$bn" -- "$@")
then
    echo "Terminating..." >&2
    exit 1
fi

eval set -- "$TEMP"
unset TEMP

while true; do
    case $1 in
	-c|--keep-count)	COUNT=$2 ;	shift 2	;;
	-d|--keep-days)		DAYS=$2 ;	shift 2	;;
	-n|--dry-run)		DRY_RUN=1 ;	shift	;;
	-r|--repos)		REPOS=$2 ;	shift 2	;;
	-U|--registry)		URL=$2 ;	shift 2	;;
	-v|--verbose)		VERBOSE=1 ;	shift	;;
	-h|--help)		usage ;		exit 0	;;
	--)			shift ;		break	;;
	*)			usage ;		exit 1
    esac
done

main

## EOF ##
