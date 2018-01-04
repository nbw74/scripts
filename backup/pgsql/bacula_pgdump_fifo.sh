#!/bin/bash
#
# PostgreSQL dump for Bacula
#
# "Backups should be run as the superuser.  Don't waste your time trying
# to kluge up something else."
# http://www.postgresql.org/message-id/2183.1034309819@sss.pgh.pa.us
#
# source: http://wiki.bacula.org/doku.php?id=application_specific_backups:postgresql
#
# Version 0.2.3
#

readonly CONFIG=/usr/local/etc/bacula_pgdump_fifo

bn=$(basename $0)

if [[ -r $CONFIG ]]; then
    . $CONFIG
else
    echo "Configuration file ($CONFIG) not readable"
    exit 136
fi

set -o nounset

readonly FIFODIR=${DUMPDIR}/fifo
readonly RFIFODIR=/tmp/bacula-restores/${DUMPDIR}/fifo
readonly PGUSER=postgres
export PGUSER
# export PGPASSWORD=	                           # only when pg_hba.conf requires it

declare INPUT_LIST=""

make_database_backup() {
    exec > /dev/null
    FN=$FUNCNAME

    mkdir -p $FIFODIR
    except
    # rm -f $FIFODIR/*.data.fifo
    # except

    pg_dumpall -U $PGUSER -g >${DUMPDIR}/globalobjects.sql   # hopefully never a big file, so no need for a fifo
    except

    for dbname in $(db_list); do
        _pg_dump schema
        _pg_dump data
    done
}

_pg_dump(){
    FN=$FUNCNAME

    local object=${1:-NOP}
    local pg_parm=""

    case $object in
        schema) pg_parm="-s" ;;
        data)   pg_parm="-a" ;;
        *) false || except "$object"
    esac

    mkfifo ${FIFODIR}/${dbname}.${object}.fifo
    except mkfifo
    pg_dump -U $PGUSER --format=c --compress=9 $pg_parm $dbname --file=${FIFODIR}/${dbname}.${object}.fifo 2>&1 < /dev/null &
    except pg_dump
}


delete_database_backup() {
    FN=$FUNCNAME
    sleep 10

    for dbname in $(db_list); do
        _rm_dump schema
        _rm_dump data
    done

    rm ${DUMPDIR}/globalobjects.sql
    except
}

_rm_dump() {
    FN=$FUNCNAME

    local object=${1:-NOP}
    local -i PGDSPID=0

    PGDSPID=$(ps aux | fgrep "pg_dump" | fgrep " --file=${FIFODIR}/${dbname}.${object}.fifo" | awk '{print $2}')
    if (( $PGDSPID != 0 )); then
        echo "ALERT: alive pg_dump PID: $PGDSPID"
        kill $PGDSPID
        except
    fi

    rm ${FIFODIR}/${dbname}.${object}.fifo
    except
}

restore() {
    exec > /dev/null
    FN=$FUNCNAME

    mkdir -p $RFIFODIR
    rm ${RFIFODIR}/*.fifo

    for dbname in $(db_list); do
	_db_restore schema
	_db_restore data
    done
}

_db_restore() {
    FN=$FUNCNAME

    local object=${1:-NOP}

    mkfifo ${RFIFODIR}/${dbname}.${object}.fifo
    except
    dd if="${RFIFODIR}/${dbname}.${object}.fifo" of="${RFIFODIR}/${dbname}.${object}.sqlc" 2>&1 < /dev/null &
    except
}

listdbdump() {
    FN=$FUNCNAME

    for dbname in $(db_list); do
	echo "${FIFODIR}/${dbname}.schema.fifo"
	echo "${FIFODIR}/${dbname}.data.fifo"
    done
}

db_list() {
    FN=$FUNCNAME

    local -a DBlist=("")

    if [[ -z $INPUT_LIST ]]; then
        DBlist=( $(echo "SELECT datname FROM pg_database WHERE NOT datname IN ('bacula','template0') ORDER BY datname;" | psql -U $PGUSER -d template1 -q -t) )
        except
    else
        DBlist=( $(echo "${INPUT_LIST}"|awk '$1=$1' FS=":" OFS=" ") )
    fi

    printf "%s " "${DBlist[@]}"
}

noP() {
    echo "Type \"$bn -h\" for usage guide"
    exit 1
}

writeLog() {
    echo "${bn}: $*" >2 1>&2
    logger -t "$bn" "$*"
}

except() {
    local RET=$?
    local opt1=${1:-UNDEF}

    if (( RET != 0 )); then
	writeLog "Fatal error: non-zero exit code in function \"${FN}\", exiting (${RET}; ${opt1})"
        exit $RET
    fi
}

[[ "${1:-NOP}" == "NOP" ]] && noP

while getopts "d:lmrxh" OPTION
do
    case $OPTION in
        d) INPUT_LIST=$OPTARG
            ;;
	l) listdbdump
	    ;;
	m) make_database_backup
	    ;;
	r) restore
	    ;;
	x) delete_database_backup
	    ;;
	h) echo "Usage: `basename $0` -m|-d|-l"
	    ;;
	*) noP
    esac
done

exit 0

# Changelog:

# 0.1.1 - 2014-01-20
#   - добавлена функция debug;
#   - добавлено ``su - postgres -c'' в /etc/bacula.d/leader.conf on bacula-dir
#       (File = "\\|su - postgres -c \"/usr/local/bin/bacula_pgdump_fifo.sh -l\"")
#
# 0.2.0 - 2014-01-20
#   - добавлена функция restore (http://www.linux.org.ru/forum/admin/8526054 -> 
#       http://www.backupcentral.com/phpBB2/two-way-mirrors-of-external-mailing-lists-3/bacula-25/wiki-postgres-example-revisited-95147/);
#   - хост-специфичные настройки вынесены в конфигурационный файл;
#
# 0.2.1 - 2015-07-08
#   - маленький рефакторинг
#
# 0.2.2 - 2015-10-28
#   - закомментировано удаление *.data.dump в начале выполнения. Нафих?
#   - убраны --force из вызовов rm
#   - добавлен sleep в delete_database_backup

# 0.2.3 - 2016-03-24
#   - добавлен ключ для бэкапа отдельной базы
#   - FIFOs *.dump renamed to *.fifo
#   - опция 'd' переименована в 'x'
