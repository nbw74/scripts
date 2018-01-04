#!/bin/bash
#
# Скрипт для определения возраста SVN-репозиториев
# (дата последнего коммита)
#

SVN_ROOT=/var/local/svn
REPOLIST=/var/local/repolist_svn
OUTFILE=/var/local/svnlog
# параметр, задающий префикс репозиториев, например https://svn.example.com/svn/
SVNURI=$1

Main() {
    FN=$FUNCNAME
    set -o nounset
    trap except ERR

    # cat /dev/null > $OUTFILE

    mkdir -p $SVN_ROOT
    cd $SVN_ROOT

    while read repo; do
        echo "svn checkout $repo ..."
        svn -q checkout ${SVNURI}$repo $repo
        echo "done."
        cd $repo
        echo "${repo}: $(svn -q log -l 1 | grep -P '\d{4}-')" >> $OUTFILE
        cd ..
        rm -rf "$repo"
        echo "$repo removed"
        echo "\$PWD is $(pwd)"
        echo "--------------------------------------------------------------------"
    done < $REPOLIST
}

except() {
    echo "Error in function $FN"
    exit $?
}

Main
