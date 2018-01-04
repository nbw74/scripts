#!/bin/bash
#
# Рекурсивно переименовывает файлы, удаляя пробелы, расположенные
# в начале и конце имени
#

bn=$(basename $0)
target="${1:-.}"
readonly pwd=$PWD

Main() {

    local prefix=""
    local file=""
    readonly dirlist=$(mktemp /tmp/${bn%%\.*}.XXXXXXXX)
    readonly filelist=$(mktemp /tmp/${bn%%\.*}.XXXXXXXX)

    find "$target" -type d -print > $dirlist

    bIFS="$IFS"
    IFS=''

    while read dir; do
        cd "$dir"

        find -maxdepth 1 -type f | sed -r 's|^\./||' > $filelist

        while read file; do
            newname="$(echo "$file"|sed -r -e 's/^[[:space:]]*//' -e 's/[[:space:]]*(\.[a-zA-Z]*)/\1/')"
            
            if [[ "$file" == "$newname" ]]; then
                continue
            elif [[ -f "$newname" ]]; then
                echo "FILENAME CONFLICT DETECTED! ADDING PREFIX..."
                prefix=UNSPACED_
            fi
            mv -iv "$file" "${prefix}$newname"
            except mv
            prefix=""
        done < $filelist

        file=""
        cd $pwd
    done < $dirlist

    IFS="$bIFS"

    rm $dirlist $filelist
}

except() {
    local RET=$?

    if (( RET == 0 )); then
        return
    else
        echo "ERROR CODE $RET; $1"
        cd "$pwd"
        exit $RET
    fi
}

Main
