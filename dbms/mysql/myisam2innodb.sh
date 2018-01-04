#!/bin/bash
#
# Script for MySQL database format conversion from 
# MyISAM to InnoDB (Debian version)
#


typeset dbName
typeset siteName
typeset -a DbList
typeset -i showDbList=0
typeset -i allDatabases=0

bn=$(basename $0)
sa=/tmp/${bn%\.*}.awk

Main() {

    FN=$FUNCNAME
    timestamp=$(date '+%FT%H%M%S')

# AWK subprogram
    echo '
BEGIN {}

! /ENGINE=MyISAM/ {
    print( $0 );
}

/ENGINE=MyISAM/ {
    if( ! match(E, /FULLTEXT/) ) {
	if( ! match($0, /mysql>/)  ) {
	    sub(/ENGINE=MyISAM/, "ENGINE=InnoDB" );
	}
    }
    print( $0 );
}

{
    E = $0;
}

END {}
' > $sa
    except

    if grep -i debian /etc/issue >/dev/null; then
	authParams="--defaults-file=/etc/mysql/debian.cnf"
    else
	echo "Current system is not a Debian, exiting"
	false|except
    fi

    if (( showDbList == 1 )); then
	dblist show
	except
	exit 0
    fi

    if [[ -n $siteName ]]; then
	echo -e "Running a2dissite for site ${siteName}..."
	a2dissite $siteName
	except
	service apache2 reload
	except
    fi

    if (( allDatabases != 0 )); then

	dblist

	local i

	for (( i=0; i<${#DbList[@]}; i++ )); do
	    dbconvert ${DbList[$i]}
	done

    else
	dbconvert $dbName
    fi

    if [[ -n $siteName ]]; then
	echo -e "Running a2ensite for site ${siteName}..."
	a2ensite $siteName
	except
	service apache2 reload
	except
    fi

}

dblist() {

    FN=$FUNCNAME

    DbList=( $(mysql $authParams --batch --skip-column-names -e "SHOW DATABASES"|egrep -v "information_schema|performance_schema|mysql|test") )
    except

    if [[ $1 == "show" ]]; then

	local i

	for (( i=0; i<${#DbList[@]}; i++ )); do
	    echo ${DbList[$i]}
	done
    fi

}

dbconvert() {

    dbName=$1
    FN=$FUNCNAME

    if [[ -z $dbName ]]; then
	echo "dbname not defined"
	false|except
    else
	dumpFile=${dbName}-${timestamp}.sql
	dumpFileAlt=${dbName}-${timestamp}-ALTERED.sql
    fi

    # Dump creation
    echo -en "\tmysqldump started..."
    mysqldump $authParams --add-drop-table $dbName > $dumpFile
    except
    echo "Database dump created as $dumpFile ($(ls -sh $dumpFile | awk '{print $1}'))"
    echo -en "\tAltering ENGINE records..."
    # sed -i -r 's/ENGINE=MyISAM/ENGINE=InnoDB/g' $dumpFile
    awk -f $sa $dumpFile > $dumpFileAlt
    except
    echo -en "\tDatabase loading..."
    mysql $authParams $dbName < $dumpFileAlt
    except


}

if [ -f /etc/init.d/functions ]; then
    . /etc/init.d/functions
    ECHO_SUCCESS=echo_success
    ECHO_FAILURE=echo_failure
    ECHO_WARNING=echo_warning
elif [ -f /lib/lsb/init-functions ]; then
    . /lib/lsb/init-functions
    ECHO_SUCCESS="log_end_msg 0"
    ECHO_FAILURE="log_end_msg 1"
    ECHO_WARNING="log_end_msg 255"
else
    echo "init-functions not found, exiting..."
    exit 18
fi

writeLog() {
    echo "$*" 1>&2
    logger -t "$bn" "$*"
}

except() {
    RET=$?
    if (( RET == 0 )); then
        $ECHO_SUCCESS
#	echo
    else
        echo "Runtime error in function $FN"
        $ECHO_FAILURE
        exit $RET
    fi
}

usage() {
    echo -e "Usage: $(basename $0) option
        Options:
	-a		Convert all databases
	-d <dbname>	MySQL database name
	-s <sitename>	Apache site configuration file name for disabling/enabling (optional)
	-l		List databases and exit
        "
}

while getopts "ad:s:lh" OPTION; do
    case $OPTION in
        a) allDatabases=1
                ;;
        d) dbName=$OPTARG
                ;;
        s) siteName=$OPTARG
                ;;
        l) showDbList=1
                ;;
        h) usage
            exit 0
                ;;
        *) usage
            exit 1
    esac
done

if [ -z "$1" ]; then
    usage
    exit 1
fi

Main

