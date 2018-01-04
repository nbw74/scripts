#!/bin/bash
#
# [23:09:50] <..> находим в папке(в плоском каталоге, без вложений)файлы, которых есть слово "монтаж" и помещаем в другую папку
# [23:10:27] <..> или второй вариант с сочетанием слов обслуживание и пожарной
#
# НЕРЕКУРСИВНЫЙ! Смотрит только там, где запустили. Параметров не требует.
#

Main() {
    mkdir монтаж
    except "Каталог \"монтаж\" уже существует"
    mkdir пожарн
    except "Каталог \"пожарн\" уже существует"

    for file in *.doc*; do
        tmp=$(mktemp /tmp/doc.XXXXXXXX)

        if file "$file" | fgrep -q 'Composite Document File'; then
            catdoc "$file" > $tmp
            except "Ошибка catdoc"
        elif file "$file" | fgrep -q 'Microsoft Word 2007'; then
            unzip -qc "$file" word/document.xml | sed 's#</w:p>#\n\n#g;s#<[^>]*>##g' > $tmp
            except "Ошибка catdocx"
        fi

        if fgrep -q монтаж $tmp
        then
            mv -iv "$file" монтаж/
        elif fgrep -q обслуживание $tmp
        then
            if fgrep -q пожарн $tmp
            then
                mv -iv "$file" пожарн/
            fi
        fi

        rm $tmp
    done
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
