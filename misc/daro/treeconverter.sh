#!/bin/bash
#
# Конвертирует дерево из doc и docx
# в plaintext'овое
#

bn=$(basename $0)
treelist=$(mktemp /tmp/${bn%%\.*}.XXXXXXXX)
target="$1"

Main() {

    find "$target" -type f -name '*.doc*' -print > $treelist

    cat $treelist | while read line; do
        b1="${line%%\/*}"     # первый элемент пути
        d1="${line#*\/}"      # путь без первого элемента

        if [[ $d1 =~ / ]]; then
            dx="${d1%\/*}"        # путь без первого элемента и имени файла
        else
            dx=""
        fi

        mkdir -p "${b1}_txt/${dx}"

        if file "$line" | fgrep -q 'Composite Document File'; then
            catdoc "$line" > "${b1}_txt/${d1}.txt"
        elif file "$line" | fgrep -q 'Microsoft Word 2007'; then
            unzip -qc "$line" word/document.xml | sed 's#</w:p>#\n\n#g;s#<[^>]*>##g' > "${b1}_txt/${d1}.txt"
        else
            echo -e "\e[0;33m${line}: \e[0;31mUnwanted document format\e[0m"
        fi
    done

    rm $treelist

}

except() {
    local RET=$?

    if (( RET == 0 )); then
        return
    else
        echo "$1"
        exit $RET
    fi
}

Main
