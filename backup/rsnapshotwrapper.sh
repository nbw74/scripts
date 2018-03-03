#!/bin/bash
#
# Small rsnapshot wrapper for backup to NFS export
#

set -o nounset
set -o errtrace

readonly PATH=/bin:/usr/bin
readonly bn=$(basename "$0")

readonly OUTFILE=$(mktemp -t "${bn}.XXXX")
readonly LOCKFILE=/tmp/${bn%%\.*}.lock
readonly LOG=/var/log/${bn%%\.*}.log

readonly nfs_opts="-o proto=tcp,port=2049,rw"

typeset RSNAP_ARG="" NFS_SERVER="" NFS_EXPORT="" MOUNTROOT="/mnt"
typeset -i NFS_V3=0 KEEPLOCK=0 MOUNT_ONLY=0

main() {

    trap except ERR
    trap myexit EXIT

    FN=${FUNCNAME[0]}

    if [[ -f "$LOCKFILE" ]]; then
        writeLog "ERROR: lock file found, exiting..."
        KEEPLOCK=1
        exit 1
    else
        touch "$LOCKFILE"

        if [[ -z $NFS_SERVER || -z $NFS_EXPORT ]]; then
            writeLog "ERROR: required parameter is missing"
            exit 1
        fi

        Mount
        rsnapshot $RSNAP_ARG 2>"$OUTFILE"

    fi
}

Mount() {

    FN=${FUNCNAME[0]}
    # defaults
    local nfs="nfs4"

    MOUNTROOT=${MOUNTROOT}/${NFS_SERVER%%\.*}

    mkdir -p $MOUNTROOT >"$OUTFILE" 2>&1
    writeLog "INFO: ${MOUNTROOT} created."

    if (( NFS_V3 )); then
        nfs="nfs"
    fi
    # shellcheck disable=SC2086
    mount -t $nfs ${nfs_opts} ${NFS_SERVER}:/${NFS_EXPORT} $MOUNTROOT >"$OUTFILE" 2>&1

    writeLog "INFO: filesystem ${NFS_EXPORT} mounted in ${MOUNTROOT}."

    if (( MOUNT_ONLY )); then
        exit
    fi
}

Umount() {

    FN=${FUNCNAME[0]}

    umount "$MOUNTROOT" >"$OUTFILE" 2>&1
    writeLog "INFO: ${MOUNTROOT} unmounted."
    sleep 1
    rmdir "$MOUNTROOT" >"$OUTFILE" 2>&1
    writeLog "INFO: ${MOUNTROOT} removed."
}

writeLog() {
    logger -t "$bn" "$*"
}

myexit() {
    local -i RET=$?

    if (( ! KEEPLOCK )); then
        if (( ! MOUNT_ONLY )); then
            Umount
        fi
        [[ -f $LOCKFILE ]] && rm "$LOCKFILE"
        [[ -f "${OUTFILE:-NOFILE}" ]] && rm "$OUTFILE"
    fi
}

except() {
    local -i RET=$?

    MSG="Error in function ${FN:-UNKNOWN}, exit code $RET. Program output was: \"$(cat "${OUTFILE:-/dev/null}")\""
    writeLog "$MSG"

    exit $RET
}

usage() {
    echo -e "Usage: $bn option (REQUIRED)
        Options:
        -3          use NFS v.3 (default use version 4)
        -e <path>   exported filesystem (e.q. \`volume1')
        -m          mount NFS filesystem and exit
        -n <addr>   NFS server address
        -r <arg>    argument for rsnapshot
        -h          print this help
        "
}

while getopts "3e:mn:r:h" OPTION; do
    case $OPTION in
        3) NFS_V3=1
            ;;
        e) NFS_EXPORT=$OPTARG
            ;;
        m) MOUNT_ONLY=1
            ;;
        n) NFS_SERVER=$OPTARG
            ;;
        r) RSNAP_ARG=$OPTARG
            ;;
        *) usage
            exit 1
    esac
done

if [[ "${1:-NOOP}" == "NOOP" ]]; then
    usage
    KEEPLOCK=1
    exit 1
fi

main
