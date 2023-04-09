#!/bin/bash

default_user="postgres"
default_password="postgres"
default_host="localhost"
default_dbname="xs_datamart_sampledb"

read -p "Enter PostgreSQL user (default: $default_user): " user
user=${user:-$default_user}

read -p "Enter PostgreSQL password (default: $default_password): " password
password=${password:-$default_password}

read -p "Enter PostgreSQL host (default: $default_host): " host
host=${host:-$default_host}

read -p "Enter database name (default: $default_dbname): " dbname
dbname=${dbname:-$default_dbname}

logfile="create_database.log"

echo "Creating database $dbname..."
psql -U $user -h $host -c "CREATE DATABASE $dbname;" > $logfile 2>&1

echo "Running xs.sql script..."
psql -U $user -h $host -d $dbname -f xs.sql >> $logfile 2>&1

echo "Running datamart-sample.sql script..."
psql -U $user -h $host -d $dbname -f datamart-sample.sql >> $logfile 2>&1

echo "Test calculation xs..."
psql -U $user -h $host -d $dbname -c "select * from datamart.sp_rep_1_sample_data('2023-03-22')"

echo "Done. See $logfile for details."