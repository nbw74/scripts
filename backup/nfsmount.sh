#!/bin/bash
#
# NFS mounter for using with Bacula
# Version 0.0.2
# 

set -o nounset

readonly PATH=/bin:/usr/bin
readonly bn=$(basename $0)

## readonly OUTFILE=$(mktemp -t incrsync.XXXX)
readonly LOCKFILE=/tmp/${bn%%\.*}.lock
readonly LOG=/var/log/${bn%%\.*}.log

readonly nfs_opts="-o proto=tcp,port=2049,"

typeset NFS_SERVER="" NFS_EXPORT="" MOUNTROOT="/mnt"
typeset -i MOUNT=0 UMOUNT=0 NFS_V3=0 RW=0

main() {
    FN=$FUNCNAME
    # defaults
    local nfs="nfs4" mode="ro"

    if [ -f $LOCKFILE ]; then
        writeLog "ERROR: lock file found, exiting..."
        exit 1
    else
        touch $LOCKFILE
        except

        MOUNTROOT=${MOUNTROOT}/${NFS_SERVER%%\.*}

        if (( MOUNT )); then

            if [[ -z $NFS_SERVER || -z $NFS_EXPORT ]]; then
                writeLog "ERROR: required parameter is missing"
                false || except
            fi

            mkdir -p $MOUNTROOT
            except
            writeLog "INFO: ${MOUNTROOT} created."

            if (( NFS_V3 )); then
                nfs="nfs"
            fi
            if (( RW )); then
                mode="rw"
            fi
            mount -t $nfs ${nfs_opts}$mode ${NFS_SERVER}:/${NFS_EXPORT} $MOUNTROOT
            except
            writeLog "INFO: filesystem ${NFS_EXPORT} mounted in ${MOUNTROOT}."

        elif (( UMOUNT )); then

            if [[ -z $NFS_SERVER ]]; then
                writeLog "ERROR: required parameter is missing"
                false || except
            fi

            sleep 2
            umount $MOUNTROOT
            except
            writeLog "INFO: ${MOUNTROOT} unmounted."
            sleep 1
            rmdir $MOUNTROOT
            except
            writeLog "INFO: ${MOUNTROOT} removed."
        else
            writeLog "ERROR: Unknown action"
            false || except
        fi

    fi

    myexit 0
}

except() {
    local RET=$?
    # local opt1=${1:-NOOP}

    if (( $RET != 0 )); then
        writeLog "Error in function ${FN:-UNKNOWN}, exit code $RET."
        myexit $RET
    fi
}

myexit() {
    local RET="$1"

    [[ -f $LOCKFILE ]] && rm $LOCKFILE
    exit $RET
}

writeLog() {
    echo "$*" | tee -a $LOG
    logger -t "$bn" "$*"
}

usage() {
    echo -e "Usage: $(basename $0) option (REQUIRED)
        Options:
        -3          use NFS v.3 (default use version 4)
        -n <addr>   NFS server address
        -e <path>   exported filesystem (e.q. \`volume1')
        -m          mount NFS filesystem
        -u          unmount mounted NFS filesystem
        -w          enable rw mode (default: ro)
        -h          print this help
        "
}

while getopts "3n:e:muwh" OPTION; do
    case $OPTION in
        3) NFS_V3=1
            ;;
        n) NFS_SERVER=$OPTARG
            ;;
        e) NFS_EXPORT=$OPTARG
            ;;
        m) MOUNT=1
            ;;
        u) UMOUNT=1
            ;;
        w) RW=1
            ;;
        h) usage
            exit 0
                ;;
        *) usage
            exit 1
    esac
done

if [[ "${1:-NOOP}" == "NOOP" ]]; then
    usage
    exit 1
fi

main
