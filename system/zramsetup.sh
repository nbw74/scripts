#!/bin/bash

### BEGIN INIT INFO
# Provides:          zram-setup
# Required-Start:    $local_fs
# Required-Stop:     $local_fs
# Default-Start:     2 3 4 5
# Default-Stop:      0 1 6
# Short-Description: setting up zram device
# Description:       Setting up ZRAM device for store Apache session files (v.1.3)
### END INIT INFO

set -o nounset

## HARDCODED! FIX THIS
readonly ZRAM_DEVICE=/dev/zram0
#
readonly ZRAM_MOUNTPOINT="/var/cache/httpd/zram"
readonly BASEDIR="/var/www"

readonly PATH=/usr/bin:/usr/sbin
readonly bn=$(basename $0)
readonly LOCKFILE=/run/${bn%%\.*}.lock
readonly OUTFILE=/tmp/${bn%%\.*}.out

typeset -a SiteUsers=("")

main() {
    FN=$FUNCNAME

    if [[ -f $LOCKFILE ]]; then
        local lock_time=$(stat --format="%Y" $LOCKFILE)
        local curr_time=$(date '+%s')

        if (( ((curr_time - lock_time)) < 280 )); then
            writeLog "[fail] ERROR: lock file found, exiting..."
            exit 1
        fi
    else
        touch $LOCKFILE >$OUTFILE 2>&1
        except touch
    fi

    mkfs.btrfs -L ZRAMCACHE $ZRAM_DEVICE >$OUTFILE 2>&1
    except create_filesystem

    mount -o discard $ZRAM_DEVICE $ZRAM_MOUNTPOINT >$OUTFILE 2>&1
    except mount_device
    
    if df | egrep -q "/dev/zram.*${ZRAM_MOUNTPOINT}"; then
        true
    else
        writeLog "ERROR: ZRAM device not mounted"
        false || except
    fi

    if (( ${#SiteUsers[@]} == 1 )); then
        SiteUsers=( $(find $BASEDIR -type d -maxdepth 1 -regextype posix-extended -regex '.*/[^.][^.][-_.a-zA-Z0-9]+' 2>/dev/null | fgrep --color=none '.' | sed "s|${BASEDIR}/||g") )
        except SiteUsers
    fi

    local u=""
    for u in ${SiteUsers[@]}; do
        mkdir ${ZRAM_MOUNTPOINT}/$u > $OUTFILE 2>&1
        except mkdir
        chown ${u}:${u} ${ZRAM_MOUNTPOINT}/$u
        except chown
        chmod 0770 ${ZRAM_MOUNTPOINT}/$u
        except chmod

        if [[ ! -d ${BASEDIR}/${u}/tmp ]]; then
            writeLog "WARNING: ${BASEDIR}/${u}/tmp not found, creating"
            mkdir ${BASEDIR}/${u}/tmp
            except mkdir_tmp
        fi
        mount -o bind ${ZRAM_MOUNTPOINT}/$u ${BASEDIR}/${u}/tmp
        except mount_bind
    done

    restorecon -R $ZRAM_MOUNTPOINT
    except restorecon

    writeLog "[ ok ] ZRAM cache mounted."
    myexit 0

}

except() {
    local RET=$?
    local opt1=${1:-NONE}
    local opt2=${2:-NONE}

    if (( $RET != 0 )); then
        writeLog "Error in function ${FN:-UNKNOWN}, exit code $RET (${opt1}: $(cat ${OUTFILE}))."
        myexit $RET
    fi
}

myexit() {
    local RET="$1"

    [[ -f $LOCKFILE ]] && rm $LOCKFILE
    [[ -f $OUTFILE ]] && rm $OUTFILE
    exit $RET
}

writeLog() {
    echo -e "$*"
    logger -t "$bn" "$*"
}

main

### EOF ###
