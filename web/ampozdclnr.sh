#!/bin/bash
#
# Disk space cleaner
# for accounts on orenweb.biz
# version 0.1.0
#

set -o nounset
set -E

# Threshold for used disk space, kB
typeset -i USED_MAX=400000

readonly PATH=$PATH:/bin:/sbin:/usr/bin:/usr/sbin
readonly NOC="#NOC_MAIL#"

readonly bn=$(basename $0)
readonly hn=$(hostname -f)

# Misc variables
MSG=""
typeset -i LOCK=1 USED=1000000

main() {

    trap 'except HUP'   SIGHUP
    trap 'except INT'   SIGINT
    trap 'except QUIT'  SIGQUIT
    trap 'except ILL'   SIGILL
    trap 'except ABRT'  SIGABRT
    trap 'except KILL'  SIGKILL
    trap 'except SEGV'  SIGSEGV
    trap 'except TERM'  SIGTERM
    trap 'except ERR'   ERR
    trap myexit EXIT

    readonly LOCKFILE=${HOME}/tmp/${bn%\.*}.lock
    readonly LOGFILE=${HOME}/tmp/${bn%\.*}-$(date +'%FT%H%M').log
    readonly OUTFILE=$(mktemp -t ${bn%\.*}.out.XXXX)

    if [[ -f "$LOCKFILE" ]]; then
        local lock_time=$(stat --format="%Y" $LOCKFILE)
        local curr_time=$(date '+%s')

        if (( ((curr_time - lock_time)) < 1280 )); then
            MSG="Lock file found"
            writeLg
            exit 0
        fi
    else
        touch $LOCKFILE >$OUTFILE 2>&1
        LOCK=0
    fi

    # Flush error_log(s)
    find $HOME -type f -name error_log -exec sh -c 'cat /dev/null > {}' \;
    # Remove old cache files
    find $HOME/public_html -type f -path "*/cache/*" -mtime +2 ! -name 6666cd76f96956469e7be39d750cc7d9 -delete
    # Remove old e-mails
    find $HOME/mail -type f -path "*/new/*" -mtime +40 -delete
    # Used space
    USED=$(du -s $HOME|awk '{print $1}')
    if (( USED > USED_MAX )); then
        MSG="WARNING: ${USED}kB disk space used"
        writeLg
    fi

    exit 0
}

except() {
    local -i RET=$?
    local SIG=${1:-(U)}

    MSG="Error occured, exit code ${RET}, signal ${SIG}. Last command output: \"$(cat ${OUTFILE:-NOFILE})\", message: \"${MSG}\""
    writeLg

    exit $RET
}

myexit() {
    local -i RET=$?

    [[ -f "$OUTFILE" ]] && rm "$OUTFILE"

    if (( LOCK == 0 )); then
        [[ -f "$LOCKFILE" ]] && rm "$LOCKFILE"
    fi
    # MSG="Normal exit"; writeLg
    exit $RET
}

writeLg() {
    echo "$MSG" | mail -s "*** ${USER^^}@${hn} ***" -S "from=${USER} User <DoNotReply>" $NOC
}

main

