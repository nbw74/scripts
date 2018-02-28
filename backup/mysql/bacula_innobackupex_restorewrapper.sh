#!/bin/bash
#
# Restore commands wrapper for dbms/bacula_innobackupex.sh and bacula
#

set -o nounset
set -o errtrace

typeset MARIADB_VERSION=""
typeset DB_NAME=""
typeset -i NODUMP=0

readonly bn=$(basename "$0")

main() {
    trap except ERR

    local FN=${FUNCNAME[0]}

    if [[ "${MARIADB_VERSION:-UNSET}" == "UNSET" || ! ${MARIADB_VERSION} =~ 100|101 ]]; then
        echo "${bn}: '-m' option required. See '-h' for details"
        false
    fi

    if [[ $NODUMP == 0 && ${DB_NAME:-UNSET} == "UNSET" ]]; then
        echo "${bn}: '-d' option required. See '-h' for details"
        false
    fi

    SCL_DATADIR="/var/opt/rh/rh-mariadb${MARIADB_VERSION}/lib/mysql"
    SCL_DEFFILE="/etc/opt/rh/rh-mariadb${MARIADB_VERSION}/my.cnf.d/mariadb-server.cnf"
    SCL_SERVICE="rh-mariadb${MARIADB_VERSION}-mariadb.service"
    XTRABAK_DIR="/var/preserve/xtrabackup"

    echo ".. Stop SCL MariaDB service "
    systemctl stop $SCL_SERVICE
    echo ".. Remove SCL lib/mysql directory "
    rm -r "$SCL_DATADIR"
    echo ".. Create SCL lib/mysql directory "
    mkdir "$SCL_DATADIR"
    echo ".. Change owner of SCL lib/mysql directory "
    chown mysql:mysql "$SCL_DATADIR"

    if [[ -e "$XTRABAK_DIR" ]]; then
        echo ".. Remove preserve/xtrabackup directory "
        rm -r "$XTRABAK_DIR"
    fi
    echo ".. Move restored xtrabackup in preserve directory "
    mv /var/preserve/bacula-restores$XTRABAK_DIR /var/preserve/

    echo ".. Execute prepare step "
    /usr/local/bin/bacula_innobackupex.sh -p -f "$SCL_DEFFILE"
    echo ".. Execute restore step "
    /usr/local/bin/bacula_innobackupex.sh -r -f "$SCL_DEFFILE"

    if (( ! NODUMP )); then
        echo ".. Start SCL MariaDB service "
        systemctl start $SCL_SERVICE
        echo ".. Execute mysqldump "
        /opt/rh/rh-mariadb${MARIADB_VERSION}/root/bin/mysqldump ${DB_NAME} | lbzip2 - > "${DB_NAME}-$(date '+%FT%H%M').sql.bz2"
        echo ".. Stop SCL MariaDB service "
        systemctl stop $SCL_SERVICE
        rm -r "$XTRABAK_DIR"
    else
        echo "Dump restored. Please run $SCL_SERVICE manually."
    fi
}

except() {
    local RET=$?

    echo "Error in function ${FN:-UNKNOWN}, exit code $RET" 1>&2
    exit $RET
}

usage() {
    echo -e "Usage: $bn <options>
        Options:
        -m <str>    MariaDB version (currently 100|101) - REQUIRED
        -b <str>    database name for extraction
        -N          do not execute mysqldump (e.g. if you want use pipe for data transfusion)
        -h          print this help
"
    exit 0
}
while getopts "m:d:Nh" OPTION; do
    case $OPTION in
        m) MARIADB_VERSION=$OPTARG
            ;;
        d) DB_NAME=$OPTARG
            ;;
        N) NODUMP=1
            ;;
        h) usage
            ;;
        *) usage
    esac
done

main
