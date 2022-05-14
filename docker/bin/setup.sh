# Setup
sudo apt-get -y update
sudo apt-get install -y git curl
sudo apt-get install postgresql postgresql-contrib

# Install hasura-cli
curl -L https://github.com/hasura/graphql-engine/raw/stable/cli/get.sh | bash

# Install pgloader
apt-get install sbcl unzip libsqlite3-dev make curl gawk freetds-dev libzip-dev
wget https://github.com/dimitri/pgloader/archive/refs/tags/v3.6.3.zip -O pgloader.zip
unzip pgloader.zip
cd pgloader-3.6.3
make pgloader

# TODO: Install psql cli