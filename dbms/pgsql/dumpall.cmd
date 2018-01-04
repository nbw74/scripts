@ECHO OFF

REM PostgreSQL dump

set PATH=C:\pgsql\9.0\bin;%PATH%
set DUMPDIR=C:\pgsql\9.0\dump

ECHO ^>^>^> DUMP GLOBAL OBJECTS
pg_dumpall -Upostgres -g -f %DUMPDIR%\globals.sql

for %%B in (bp30 buh2014 buh2014ob buh2015 smallbiz smallbiz_2014 unf-2 unf-2015) DO (
    ECHO ^>^>^> DUMPING SCHEMA %%B
    pg_dump -s -Fc -Z9 -Upostgres -f %DUMPDIR%\%%B.schema.sqlc %%B
    ECHO ^>^>^> DUMPING DATA %%B
    pg_dump -a -Fc -Z9 -Upostgres -f %DUMPDIR%\%%B.data.sqlc %%B
)

