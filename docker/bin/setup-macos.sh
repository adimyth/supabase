# Setup
brew install git curl wget
brew install postgresql

# Install hasura-cli
curl -L https://github.com/hasura/graphql-engine/raw/stable/cli/get.sh | bash

# Install pgloader
brew install sbcl sqlite make curl gawk freetds
wget https://github.com/dimitri/pgloader/archive/refs/tags/v3.6.3.zip -O pgloader.zip
unzip pgloader.zip
cd pgloader-3.6.3
make pgloader

# Install pgsql cli
brew install libpq
echo export PATH="/usr/local/opt/libpq/bin:$PATH" >> ~/.bashrc
