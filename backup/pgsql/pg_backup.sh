#!/bin/bash
#
# Скрипт для резервного копирования баз PostgreSQL
# на SMB-, NFS-шару или файловую систему
# Version 0.3.0
# 

set -o nounset

readonly PATH=/bin:/usr/bin
readonly bn=$(basename $0)

readonly LOCKFILE=/tmp/${bn%%\.*}.lock
readonly OUTFILE=/tmp/${bn%%\.*}.out
readonly PG_LOG=/var/log/${bn%%\.*}.pg_dump.log

typeset Sudo="sudo -i -u postgres"

typeset DB_SKIP="" NOC_MAIL="" METHOD="" CIFS_SERVER="" CIFS_EXPORT=""
typeset DB_LIST="" COMPRESSOR="" BLOCK_DEVICE="" LABEL=""
typeset fs_opts=""

typeset MOUNTROOT="/mnt"
typeset CONFIG="/usr/local/etc/pg_backup.conf"

typeset -i FIRST_RUN=0 DRY_RUN=0 USE_BZIP2=0
typeset -i MOUNT_ONLY=0 UMOUNT_ONLY=0 NO_UMOUNT=0
typeset -i last_backup_multiplier=8
typeset -i leave_backups_count=4
# Default values
typeset MOUNT_USER="anonymous" MOUNT_PASSWORD="@"
# Last component of path for backup catalog (MGIMO finished)
typeset BACKUPROOT="/AUTOMATIC"

##############################################################################
# CONFIGURATION FILE:
# DB_SKIP variable format: DB_SKIP="'abandon_db',"
[[ -r $CONFIG ]] && source $CONFIG
##############################################################################

main() {
    FN=$FUNCNAME

    if [[ -f "$LOCKFILE" ]]; then
        local lock_time=$(stat --format="%Y" $LOCKFILE)
        local curr_time=$(date '+%s')

        if (( ((curr_time - lock_time)) < 172800 )); then
            writeLog "ERROR: lock file found, exiting..."
            exit 1
        fi
    else
        touch $LOCKFILE >$OUTFILE 2>&1
        except
    fi

    if (( USE_BZIP2 == 1 )); then
        compressor_select
    fi

    echo "-- $(date)" >> $PG_LOG

    if [[ $METHOD == "cifs" ]]; then
        method_cifs
    elif [[ $METHOD == "filesystem" ]]; then
        method_fs
    else
        writeLog "ERROR: unknown method"
        false || except
    fi

    myexit 0
}

method_cifs() {
    FN=$FUNCNAME

    if [[ ${CIFS_SERVER:-NOP} == "NOP" || ${CIFS_EXPORT:-NOP} == "NOP" ]]; then
        writeLog "ERROR: required parameter is missing"
        false || except
    fi

    local MOUNTROOT=${MOUNTROOT}/${CIFS_SERVER}
    local cifs_opts="user=${MOUNT_USER},password=${MOUNT_PASSWORD},uid=postgres,forceuid,rw,file_mode=0644,dir_mode=0755"

    _method_run;

}

method_fs() {
    FN=$FUNCNAME

    if [[ -n "$LABEL" ]]
    then
        local MOUNTROOT=${MOUNTROOT}/${LABEL}
    elif [[ -n "$BLOCK_DEVICE" ]]
    then
        local MOUNTROOT=${MOUNTROOT}/${BLOCK_DEVICE##*\/}
    else
        writeLog "ERROR: required parameter is missing"
        false || except
    fi

    [[ -z $fs_opts ]] || fs_opts="-o $fs_opts"

    _method_run;
}

_method_run() {

    if (( MOUNT_ONLY == 1 )); then
        fs_mount
    elif (( UMOUNT_ONLY == 1 )); then
        fs_umount
    else
        fs_mount
        disk_space
        pg_backup_full
        if (( NO_UMOUNT == 0 )); then
            fs_umount
        fi
    fi
}

fs_mount() {
    FN=$FUNCNAME

    mkdir -p $MOUNTROOT >$OUTFILE 2>&1
    except

    if [[ $METHOD == "cifs" ]]
    then
        mount -t cifs -o $cifs_opts //${CIFS_SERVER}/${CIFS_EXPORT} $MOUNTROOT >$OUTFILE 2>&1
        except
        writeLog "INFO: filesystem ${CIFS_EXPORT} mounted in ${MOUNTROOT}."
    elif [[ $METHOD == "filesystem" ]]
    then
        if [[ -n "$LABEL" ]]
        then
            mount $fs_opts -L "$LABEL" $MOUNTROOT >$OUTFILE 2>&1
            except
            writeLog "INFO: filesystem $LABEL mounted in ${MOUNTROOT}."
        else
            mount $fs_opts $BLOCK_DEVICE $MOUNTROOT >$OUTFILE 2>&1
            except
            writeLog "INFO: filesystem $BLOCK_DEVICE mounted in ${MOUNTROOT}."
        fi
    fi
}

fs_umount() {
    FN=$FUNCNAME

    cd /root >$OUTFILE 2>&1
    except umount
    umount $MOUNTROOT >$OUTFILE 2>&1
    except
    writeLog "INFO: ${MOUNTROOT} unmounted."
    sleep 1
    rmdir $MOUNTROOT >$OUTFILE 2>&1
    except
}

disk_space() {
    FN=$FUNCNAME

    local DUMPDIR=${MOUNTROOT}${BACKUPROOT}
    local -i last_backup_size=0

    if (( FIRST_RUN == 1 )); then
        $Sudo mkdir -p $DUMPDIR >$OUTFILE 2>&1
        except umount
    fi

    cd $DUMPDIR >$OUTFILE 2>&1
    except umount

    if ls -1tr | tail -1 | grep -qP "\d{4}-\d{2}-\d{2}T\d{4}$"
    then
        last_backup_size=$(ls -1tr | tail -1 | xargs -d '\n' du -s | awk '{ print $1 }')
        # Умножаем на last_backup_multiplier - с запасом
        last_backup_size=$(( last_backup_size * last_backup_multiplier ))
    else
        if (( FIRST_RUN == 0 )); then
            writeLog "ERROR: cannot find old dump (wrong dir?)"
            false || except umount
        else
            return 0
        fi
    fi

    while (( $(_free_space) < last_backup_size )); do
        _remove_old
    done

}

_remove_old() {
    FN=$FUNCNAME

    local -i backups_count=0
    local oldest_backup=""

    backups_count=$(ls -1tr | grep -P "\d{4}-\d{2}-\d{2}T\d{4}$" | wc -l)

    if (( backups_count <= leave_backups_count )); then
        writeLog "ERROR: too few (${backups_count}) backups left on disk, I do not want remove oldest. NO FREE SPACE ON FILESYSTEM."
        false || except umount
    fi
    
    oldest_backup=$(ls -1tr | head -1)
    
    rm -r $oldest_backup
    except umount

    writeLog "INFO: old backup directory \"$oldest_backup\" removed"
}

_free_space() {
    FN=$FUNCNAME

    local -i free_space=0
    free_space=$(df -P | awk -v "fs=${MOUNTROOT}$" '$0 ~ fs {print $4}')
    printf "%i" $free_space
}

pg_backup_full() {
    FN=$FUNCNAME

    local DUMPDIR=${MOUNTROOT}${BACKUPROOT}/$(date '+%FT%H%M')

    if (( DRY_RUN == 0 )); then
        $Sudo mkdir $DUMPDIR >$OUTFILE 2>&1
        except umount
    fi

    if (( DRY_RUN == 0 )); then
        $Sudo pg_dumpall -g >${DUMPDIR}/globalobjects.sql 2>$OUTFILE
        except umount
    fi

    for dbname in $(_db_list); do
        _pg_dump S                      # dump schema
        _pg_dump D                      # dump data
    done
}

_pg_dump(){
    FN=$FUNCNAME

    local object=${1:-NOP}
    local pg_parm="" suffix=""

    case $object in
        S) pg_parm="-s";
            suffix="schema"
            ;;
        D) pg_parm="-a";
            suffix="data"
            ;;
        *) false || except umount
    esac

    writeLog "INFO: [${object}] \"$dbname\""
    if (( DRY_RUN == 0 )); then
        if (( USE_BZIP2 == 1 )); then
            $Sudo pg_dump --format=c --compress=0 $pg_parm $dbname 2>>$PG_LOG | $COMPRESSOR - > ${DUMPDIR}/${dbname}-${suffix}.sqlc.bz2 2>$OUTFILE
            except umount
        else
            $Sudo pg_dump --format=c --compress=9 $pg_parm $dbname --file=${DUMPDIR}/${dbname}-${suffix}.sqlc >$OUTFILE 2>&1
            except umount
        fi
    fi
}

_db_list() {
    FN=$FUNCNAME

    local -a DBlist=("")
    
    if [[ -n "$DB_LIST" ]]
    then
        DBlist=( $(echo "${DB_LIST}"|awk '$1=$1' FS=":" OFS=" ") )
    else
        DBlist=( $(echo "SELECT datname FROM pg_database WHERE NOT datname IN (${DB_SKIP}'template0') ORDER BY datname;" \
            | $Sudo psql -d template1 -q -t) )
        except
    fi

    printf "%s " "${DBlist[@]}"
}

compressor_select() {
    FN=$FUNCNAME

    local c=""

    for c in lbzip2 pbzip2 bzip2; do
        if which $c >/dev/null 2>&1
        then
            [[ $c == "bzip2" ]] && writeLog "WARNING: using obsolete single-threaded $c"
            COMPRESSOR=$c
            return
        fi
    done

    writeLog "ERROR: no suitable compressor found ([l|p]bzip2)"
    false || except

}

except() {
    local RET=$?
    local opt1=${1:-NOOP}

    if (( $RET != 0 )); then
        writeLog "FATAL: Error in function ${FN:-UNKNOWN}, exit code $RET. Last command output: \"$(cat $OUTFILE)\""

        if [[ $opt1 == "umount" ]]; then
            fs_umount
        fi

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
    logger -t "$bn" "$*"
    echo "$*" 1>&2
}

usage() {
    echo -e "Usage: $bn option (REQUIRED)
        Options:
        -C              backup method: CIFS mount
        -D <db:db:..>   list databases for dump
        -L <label>      use filesystem label for mounting
        -M              mount remote filesystem and exit
        -N              does not umount filesystem after backup
        -S              backup method: filesystem
        -U              umount filesystem and exit
        -b              use external compressor (bzip2)
        -d <device>     block device (for use with -S)
        -e <path>       exported filesystem (e.q. \`volume1') (for use with -C)
        -f              first run on filesystem (for single use only)
        -h              print this help
        -k              \"dry-run\"
        -n <addr>       CIFS server address
        -o <options>    filesystem mount options (e.q. discard,noatime)
        -p              CIFS password (default: @)
        -u              CIFS user (default: anonymous)

        Examples:
    
    $bn -C -n backup.inside.company.org -e Volume_1/pg_backup
    $bn -S -b -d /dev/vg00/lv00 -o discard
    $bn -S -N -L PGDUMP
        "
}

while getopts "CD:L:MNSUbd:e:fhkn:o:p:u:" OPTION; do
    case $OPTION in
        C) METHOD=cifs
            ;;
        D) DB_LIST=$OPTARG
            ;;
        L) LABEL=$OPTARG
            ;;
        M) MOUNT_ONLY=1
            ;;
        N) NO_UMOUNT=1
            ;;
        S) METHOD=filesystem
            ;;
        U) UMOUNT_ONLY=1
            ;;
        b) USE_BZIP2=1
            ;;
        d) BLOCK_DEVICE=$OPTARG
            ;;
        e) CIFS_EXPORT=$OPTARG
            ;;
        f) FIRST_RUN=1
            ;;
        k) DRY_RUN=1
            ;;
        n) CIFS_SERVER=$OPTARG
            ;;
        o) fs_opts=$OPTARG
            ;;
        p) MOUNT_PASSWORD=$OPTARG
            ;;
        u) MOUNT_USER=$OPTARG
            ;;
        h) usage
            exit 0
            ;;
        *) usage
            exit 1
    esac
done

if [[ "${1:-NOP}" == "NOP" ]]; then
    usage
    exit 1
fi

main
