@ECHO OFF

REM PostgreSQL restore

set PATH=C:\pgsql\9.0\bin;%PATH%
set DUMPDIR=C:\pgsql\9.0\dump

for %%B in (bp30 buh2014 buh2014ob buh2015 smallbiz smallbiz_2014 unf-2 unf-2015) DO (
    ECHO ^>^>^> RESTORING SCHEMA %%B
    pg_restore -Upostgres -C -d postgres %DUMPDIR%\%%B.schema.sqlc
    ECHO ^>^>^> RESTORING DATA %%B
    pg_restore -Upostgres -d %%B %DUMPDIR%\%%B.data.sqlc
)

