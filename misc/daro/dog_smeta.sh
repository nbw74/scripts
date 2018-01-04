#!/bin/bash
#
# "Мне нужна программа, которая будет выпонять следующее: обходить нерекурсивно
# файлы в текущем каталоге, для каждого создавать в текущей директории каталог
# с именем, эквивалентным имени файла (без расширения), затем создавать в нём
# вложенный подкаталог с именем, которое пользователь передаёт программе первым
# параметром, и перемещать исходный файл в данный подкаталог, с добавлением к
# имени файла префикса, который передаётся вторым параметром".
#

readonly inserted=$1
readonly prefix=$2

bn=$(basename $0)

Main() {

    if [[ -z $inserted || -z $prefix ]]; then
        echo "
        Данная программ принимает ровно два параметра.
        Пример запуска:
        
        $bn 1-дог догОС_
"
        exit 1
    fi

    readonly filelist=$(mktemp /tmp/${bn%%\.*}.XXXXXXXX)

    bIFS="$IFS"
    IFS=''

    find -maxdepth 1 -type f | sed -r 's|^\./||' > $filelist

    while read file; do
        # Strip extension
        d1="${file%%\.*}"
        # Create dirs
        mkdir -p "${d1}/$inserted"
        except mkdir
        # Move file
        mv -i "$file" "${d1}/$inserted/${prefix}$file"
        except mv

    done < $filelist

    IFS="$bIFS"
    rm $filelist

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
