#!/bin/bash
#
# davfs2 mounter for using with Bacula
# Version 0.0.1
# 

set -o nounset

readonly PATH=/bin:/usr/bin:/sbin:/usr/sbin
readonly bn=$(basename $0)

readonly OUTFILE=$(mktemp -t incrsync.XXXX)
readonly LOCKFILE=/tmp/${bn%%\.*}.lock
readonly LOG=/var/log/${bn%%\.*}.log

readonly davfs_opts="-o ro"

typeset DAVFS_URI="" MOUNTROOT="/mnt"
typeset -i MOUNT=0
typeset -i UMOUNT=0

main() {
    FN=$FUNCNAME

    if [ -f $LOCKFILE ]; then
        writeLog "ERROR: lock file found, exiting..."
        exit 1
    else
        touch $LOCKFILE
        except

        MOUNTROOT="${MOUNTROOT}/$(echo $DAVFS_URI | awk '{ sub(/(http|https):\/\//, ""); sub(/\/.*/, ""); printf $0 }')"

        if (( MOUNT == 1 )); then

            if [[ -z $DAVFS_URI ]]; then
                writeLog "ERROR: required parameter is missing"
                false || except
            fi

            mkdir -p $MOUNTROOT
            except
            writeLog "INFO: ${MOUNTROOT} created."

            mount.davfs $davfs_opts "$DAVFS_URI" $MOUNTROOT > $OUTFILE 2>&1
            except
            writeLog "INFO: DAVFS URI ${DAVFS_URI} mounted in ${MOUNTROOT}."

        elif (( UMOUNT == 1 )); then

            if [[ -z $DAVFS_URI ]]; then
                writeLog "ERROR: required parameter is missing"
                false || except
            fi

            sleep 2
            umount $MOUNTROOT > $OUTFILE 2>&1
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
        writeLog "Error in function ${FN:-UNKNOWN}, exit code $RET. Last command output: \"$(cat $OUTFILE)\""
        myexit $RET
    fi
}

myexit() {
    local RET="$1"

    [[ -f $OUTFILE ]] && rm $OUTFILE
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
        -p <URI>    DavFS URI
        -m          mount DAV filesystem
        -u          unmount mounted DAV filesystem
        -h          print this help
        "
}

while getopts "p:muh" OPTION; do
    case $OPTION in
        p) DAVFS_URI=$OPTARG
                ;;
        m) MOUNT=1
                ;;
        u) UMOUNT=1
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
