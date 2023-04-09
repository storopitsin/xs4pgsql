@echo off
setlocal

set default_user=postgres
set default_password=postgres
set default_host=localhost
set default_dbname=xs_datamart_sampledb

echo Enter PostgreSQL user (default: %default_user%):
set /p user=
if "%user%"=="" set "user=%default_user%"

echo Enter PostgreSQL password (default: %default_password%):
set /p password=
if "%password%"=="" set "password=%default_password%"

echo Enter PostgreSQL host (default: %default_host%):
set /p host=
if "%host%"=="" set "host=%default_host%"

echo Enter database name (default: %default_dbname%):
set /p dbname=
if "%dbname%"=="" set "dbname=%default_dbname%"

set logfile=create_database.log

echo Creating database %dbname%...
psql -U %user% -h %host% -c "CREATE DATABASE %dbname%;" > %logfile% 2>&1

echo Running xs.sql script...
psql -U %user% -h %host% -d %dbname% -f xs.sql >> %logfile% 2>&1

echo Running datamart-sample.sql script...
psql -U %user% -h %host% -d %dbname% -f datamart-sample.sql >> %logfile% 2>&1

echo Test calculation xs...
psql -U %user% -h %host% -d %dbname% -c "select * from datamart.sp_rep_1_sample_data('2023-03-22')"

echo Done. See %logfile% for details.