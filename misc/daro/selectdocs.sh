#!/bin/bash
#
# Собирает в одну папку doc'ы, соответствующие текстовикам
# в иерархии, оставшимся после fdupes'а
#

txtlist=$(mktemp txts.XXXXXXXX)
txts="$1"
docs="$2"

Main() {

    mkdir LOST0 LOST1 LOST2

    find "$txts" -type f -name '*.doc*' -print > $txtlist

    cat $txtlist | while read line; do
        d1="${line#*\/}"        # путь без первого элемента
        f1="${d1%\.*}"          # полное имя текстового файла без первого элемента и расширения
        f2="${f1##*\/}"         # имя текстового файла без расширения

        if [[ -f "LOST0/$f2" ]]; then
            if [[ -f "LOST1/$f2" ]]; then
                cp -ai "${docs}/$f1" LOST2/
            else
                cp -ai "${docs}/$f1" LOST1/
            fi
        else
            cp -ai "${docs}/$f1" LOST0/
        fi
    done
}

Main
