#!/bin/bash
#
# Backup /etc/, /var/www/ and postgresql database
# fixed depth=1
# (tar-over-ssh)
# © 2017 nbw (initially designed for ec2.skyeng)
#
# ########## CONFIGURATION FILE EXAMPLE ##########
#
# HOST_WITH_BACKUPS=example.com
# USERNAME=backup
# DB_LIST="database1:database2:database3"
# DB_SKIP=""
# PGSQL_HOST=pgsql.example.com
# PGSQL_USER=postgres
# MAIL_FROM=checkable@domain.com
# BASE_MAIL=admin@example.com
# COPY_MAIL[0]=user1@example.com
# COPY_MAIL[1]=user2@example.com
#

set -o nounset
set -o errtrace

readonly PATH=/bin:/sbin:/usr/bin:/usr/sbin

readonly bn=$(basename $0)
readonly hn=$(hostname -f)

readonly CONFIG_FILE=/usr/local/etc/${bn%\.*}.conf
readonly LOCKFILE=/var/run/${bn%\.*}.lock
readonly ERRFILE=$(mktemp -t ${bn%\.*}.XXXX)
readonly TMPFILE=$(mktemp -t ${bn%\.*}.XXXX)
readonly COMPRESSOR=lbzip2

typeset -i e=0 KEEPLOCK=0
typeset -a COPY_MAIL=( "" )

LANG=C
LC_ALL=C
LC_MESSAGES=C

main() {

    trap except ERR
    trap myexit EXIT

    local FN=$FUNCNAME

    if [[ -f "$LOCKFILE" ]]; then
        local lock_time=$(stat --format="%Y" $LOCKFILE)
        local curr_time=$(date '+%s')

        if (( ((curr_time - lock_time)) < 72000 )); then
            writeLog "FATAL: Lock file found"
            KEEPLOCK=1
            exit
        fi
    else
        touch $LOCKFILE >$ERRFILE 2>&1

        if [[ -f "$CONFIG_FILE" ]]; then
            source $CONFIG_FILE
        else
            writeLog "FATAL: configuration file not found"
            false
        fi

        makeFileBackup
        makeDbBackup
        echo ":: All objects successfully sent to ${HOST_WITH_BACKUPS}:/var/preserve/remote"
    fi
}

makeFileBackup() {
    local FN=$FUNCNAME

    echo ":: Running tar for /etc/ and /var/www "
    tar --exclude-backups --one-file-system --rsh-command="/usr/bin/ssh" --totals \
        -cjf ${USERNAME}@${HOST_WITH_BACKUPS}:${hn}-files.tar.bz2 /etc /var/www 2>&1 | tee $ERRFILE

}

makeDbBackup() {
    local FN=$FUNCNAME

#     pg_dumpall -h $PGSQL_HOST -U $PGSQL_USER -g \
#         | ssh ${USERNAME}@${HOST_WITH_BACKUPS} \
#         "cat > ${PGSQL_HOST}-globalobjects.sql" 2>$ERRFILE
# Не судьба, внезапно

    for dbname in $(_db_list); do
        _pg_dump S                      # dump schema
        _pg_dump D                      # dump data
    done
}

_pg_dump(){
    local FN=$FUNCNAME

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

    echo ":: Running pg_dump on database \"$dbname\" (${suffix}) "
    writeLog "INFO: [${object}] \"$dbname\""
    pg_dump -h $PGSQL_HOST -U $PGSQL_USER --format=c --compress=0 $pg_parm $dbname 2>$ERRFILE \
        | dd 2>$TMPFILE | ssh ${USERNAME}@${HOST_WITH_BACKUPS} \
        "cat | $COMPRESSOR - > ${PGSQL_HOST}-${dbname}-${suffix}.sqlc.bz2" 2>>$ERRFILE

    pipeExitCheck
    # Show pipe statistics in stdout
    fgrep cop $TMPFILE
}

_db_list() {
    local FN=$FUNCNAME

    local -a DBlist=("")

    if [[ -n "$DB_LIST" ]]
    then
        DBlist=( $(echo "${DB_LIST}"|awk '$1=$1' FS=":" OFS=" ") )
    else
        DBlist=( $(echo "SELECT datname FROM pg_database WHERE NOT datname IN (${DB_SKIP}'template0') ORDER BY datname;" \
            | psql -h $PGSQL_HOST -U $PGSQL_USER -d template1 -q -t 2>$ERRFILE) )
        pipeExitCheck
    fi

    printf "%s " "${DBlist[@]}"
}

except() {
    local -i RET=$?
    local MESSAGE=""

    if (( e > 2 )); then
        exit
    fi

    MESSAGE="Error in function ${fn:-UNKNOWN}, exit code $RET. Program output: \"$(cat ${ERRFILE:-/dev/null})\""

    echo "$MESSAGE" 1>&2
    writeLog "$MESSAGE"
    sendMail "$MESSAGE"

    e=$((e+1))

    exit
}

pipeExitCheck() {

    local errvol="$(cat $ERRFILE)"

    if (( ${#errvol} )); then
        false
    fi

}

myexit() {

    if (( ! KEEPLOCK )); then
        [[ -f "$LOCKFILE" ]] && rm "$LOCKFILE"
        [[ -f "$ERRFILE" ]] && rm "$ERRFILE"
        [[ -f "$TMPFILE" ]] && rm "$TMPFILE"
    fi

    exit
}


usage() {
    echo "See code please"
}

writeLog() {
    local FN=$FUNCNAME

    logger -t "$bn" "$*"
}

sendMail() {
    local FN=$FUNCNAME

    local copies=""

    for (( i=0; i<${#COPY_MAIL[@]}; i++ )); do
        copies="$copies -c ${COPY_MAIL[$i]}"
    done

    echo "$MESSAGE" | mailx -r $MAIL_FROM -s "*** BACKUP FAILED on ${hn} ***" $copies $BASE_MAIL

}

while getopts "h" OPTION; do
    case $OPTION in
        h) usage; exit 0
            ;;
        *) usage; exit 1
    esac
done

main

### EOF ###
