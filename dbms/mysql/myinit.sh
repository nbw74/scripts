#!/bin/bash
#
# Скрипт для инициализации пользователя
# БД MySQL на выделенном сервере
# v. 0.1.3
# 

. /etc/rc.d/init.d/functions

typeset -i dbNameMaxLength=14

bn=$(basename $0)
host=$(hostname -f)

set -o nounset

typeset -i REMOVE=0 CREATE_RO=0 NOUSER=0

typeset DBCREDS="" DBCREDS_RO=""
typeset authParams=""
typeset DBUSER="" PASSWD=""

Main() {
    FN=$FUNCNAME

#     if grep -i centos /etc/issue >/dev/null; then
#         authParams=""
#     else
#         echo "Current system is not a CentOS, exiting"
#         false || except
#     fi

    if (( REMOVE == 0 )); then
        CreateDB
        Echo
    else
        RemoveDB
    fi

}

mdpass() { dd if=/dev/urandom bs=512 count=1 2>/dev/null | md5sum | awk '{print $1}'; }

CreateDB() {
    FN=$FUNCNAME
    typeset -i len=0

    echo -n "Creating MySQL database"

    local db="${S_DBNAME:-NOP}"

    if [[ $db == "NOP" ]]; then
        echo "Required partameter missing"
        false || except
    fi

    len=$(echo -n "$db"|wc -c)
    if (( len > dbNameMaxLength )); then
        writeLog "ERROR: database name length ($len) exceeds maximum ($dbNameMaxLength)."
	false || except
    fi

    if [[ ${DBUSER:-NOP} == "NOP" ]]; then
        DBUSER=$db
    fi

    if [[ ${PASSWD:-NOP} == "NOP" ]]; then
        mypass=$(mdpass)
        except quiet
        mypass_ro=$(mdpass)
        except quiet
    else
        mypass="$PASSWD"
        CREATE_RO=0
    fi
    
    mysql $authParams -e "CREATE DATABASE ${db} CHARACTER SET utf8 COLLATE utf8_general_ci;"
    except quiet

    if (( NOUSER == 0 )); then
        mysql $authParams ${db} -e "CREATE USER '${DBUSER}'@'%' IDENTIFIED BY '${mypass}';"
        except quiet
    fi

    mysql $authParams ${db} -e "GRANT ALL ON ${db}.* TO '${DBUSER}'@'%'; FLUSH PRIVILEGES;"
    except quiet

    if (( CREATE_RO == 1 )); then
        mysql $authParams ${db} -e "CREATE USER '${DBUSER}_ro'@'%' IDENTIFIED BY '${mypass_ro}'; GRANT SELECT ON ${db}.* TO '${DBUSER}_ro'@'%'; FLUSH PRIVILEGES;"
        except
    else
        echo_success
        echo
    fi


    DBCREDS="
*DBMS:* @MySQL@
*DB host:* @${host}@
*DB name:* @${db}@
*DB user:* @${DBUSER}:${mypass}@"

    if (( CREATE_RO == 1 )); then
        DBCREDS_RO="
*DB r/o user:* @${DBUSER}_ro:${mypass_ro}@"
    fi
}

Echo() {
    FN=$FUNCNAME

    # Wiki page generation

    echo "
#
# Wiki page:
#
===============================================================================

h3. Database
${DBCREDS}${DBCREDS_RO}

===============================================================================
#"

}

RemoveDB() {
    FN=$FUNCNAME

    local db=$S_DBNAME

    if [[ ${DBUSER:-NOP} == "NOP" ]]; then
        DBUSER=$db
    fi

    # Removing database
    if (( NOUSER == 0 )); then
        echo -n "Removing database user" "$DBUSER"
        mysql $authParams ${db} -e "DROP USER '${DBUSER}'@'%'"
        except
        echo -n "Removing database user" "${DBUSER}_ro"
        mysql $authParams ${db} -e "DROP USER '${DBUSER}_ro'@'%'"
        except warn
    fi
    echo -n "Removing database" "$db"
    mysql $authParams ${db} -e "DROP DATABASE ${db}"
    except
}

except() {
    RET=$?
    opt1=${1:-NOP}
    opt2=${2:-NOP}

    if (( RET == 0 )); then
        if [[ $opt1 == "quiet" || $opt2 == "quiet" ]]; then
            return
	elif [[ $opt1 = "pass" ]]; then
	    echo_passed
	    echo
        else
            echo_success
	    echo
        fi
    else
        if [[ $opt1 == "warn" ]]; then
            echo_warning
            echo
        else
            echo -n "Runtime error in function $FN"
            echo_failure
            echo
            exit $RET
        fi
    fi
}

writeLog() {
    echo -e "$*" 1>&2
    logger -t "$bn" "$*"
}

usage() {
    echo -e "Usage: $bn <option(s)>
        Options:
        -d <>       database name (up to 12 chars) [REQUIRED]
        -u          database user (default = database name)
        -p          password for db user. If defined, _ro user will not be created.
        -x          remove database and keys instead creation
        -U          do not create user (if user already exist)
        "
}

while getopts "d:u:p:rxUh" OPTION; do
    case $OPTION in
        d) S_DBNAME=$OPTARG
            ;;
        u) DBUSER=$OPTARG
            ;;
        p) PASSWD=$OPTARG
            ;;
        r) CREATE_RO=1
            ;;
        x) REMOVE=1
            ;;
        U) NOUSER=1
            ;;
        h) usage
            exit 0
            ;;
        *) usage
            exit 1
    esac
done

# if [[ -z "${1:-NOP}" ]]; then
#     usage
#     exit 1
# fi

Main
