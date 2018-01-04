#!/bin/bash
#
# Скрипт для создания репозитория Git
# (с git WM)
#

set -o nounset
set -o errtrace

readonly GITHOME=/var/lib/git
readonly GITGROUP=developers
readonly GITNAME=${1:-NONE}

Main() {
    FN=$FUNCNAME
    trap except ERR

    if [[ $GITNAME == "NONE" ]]; then
        echo "Required parameter missing"
        false || except
    fi

    cd $GITHOME
    sg $GITGROUP -c "git init --bare --shared ${GITNAME}"
    cd ${GITNAME}/hooks
    ln -sv post-update.sample post-update
    git update-server-info
    cd ../..
    ls -d ${GITNAME}

}

except() {
    echo "Error in function $FN"
    exit $?
}

Main
