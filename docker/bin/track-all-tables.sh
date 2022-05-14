#!/bin/bash

export DB_HOST="localhost"
export DB_PORT=5432
export DB_USER="postgres"
export DB_PASSWORD="your-super-secret-and-long-postgres-password"

# Get all tables from the database
LAUNCHPAD_TABLES=$(psql postgresql://$DB_USER:$DB_PASSWORD@$DB_HOST:$DB_PORT/sharpsell -Atc "SELECT table_name FROM information_schema.tables WHERE table_schema = 'launchpad' ORDER BY 1")
echo "# LAUNCHPAD TABLES" >> tables.yaml
for table in $LAUNCHPAD_TABLES;
do
    echo "- table:" >> tables.yaml
    echo "  schema: launchpad" >> tables.yaml
    echo "  name: $table" >> tables.yaml
done

SMARTSELL_TABLES=$(psql postgresql://$DB_USER:$DB_PASSWORD@$DB_HOST:$DB_PORT/sharpsell -Atc "SELECT table_name FROM information_schema.tables WHERE table_schema = 'smartsell' ORDER BY 1")
echo "# SMARTSELL TABLES" >> tables.yaml
for table in $SMARTSELL_TABLES; do
    echo "- table:" >> tables.yaml
    echo "  schema: smartsell" >> tables.yaml
    echo "  name: $table" >> tables.yaml
    echo >> tables.yaml
done

# Track all tables and views present in the database
hasura metadata apply

# Track all the foreign-keys of all tables in the database
hasura metadata apply