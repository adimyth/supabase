# Sharpsell backend v2
## Technology stack

- DB - PostgreSQL
- Programming language - Python
- Authentication - GoTrue
- API surface - GraphQL
- API gateway - Kong
- Infrastructure - AWS

---

## How it works

Supabase is a combination of open source tools. We’re building the features of Firebase using enterprise-grade, open source products. If the tools and communities exist, with an MIT, Apache 2, or equivalent open license, we will use and support that tool. If the tool doesn't exist, we build and open source it ourselves. Supabase is not a 1-to-1 mapping of Firebase. Our aim is to give developers a Firebase-like developer experience using open source tools.

### Architecture

![Arcitecture](https://imgur.com/hEBNBO0.png)

- [PostgreSQL](https://www.postgresql.org/) is an object-relational database system with over 30 years of active development that has earned it a strong reputation for reliability, feature robustness, and performance.
- [GoTrue](https://github.com/netlify/gotrue) is an SWT based API for managing users and issuing SWT tokens.
- [PostgREST](http://postgrest.org/) is a web server that turns your PostgreSQL database directly into a RESTful API
- [FastAPI](https://fastapi.tiangolo.com/) is a modern, fast (high-performance), web framework for building APIs with Python 3.6+ based on standard Python type hints.
- [Hasura GraphQL Engine](https://hasura.io/docs/latest/graphql/core/index/) makes your data instantly accessible over a real-time GraphQL API, so you can build and ship modern apps and APIs faster.
- [GraphQL to REST](https://hasura.io/docs/latest/graphql/core/api-reference/restified/) - The RESTified GraphQL API allows for the use of a REST interface to saved GraphQL queries and mutations. In our case, we implement some of the PHP apis to GraphQL & then expose them as REST APIs.
- [Kong](https://github.com/Kong/kong) is a cloud-native API gateway.

---

## Getting started
### Platform
The above stack has been tested on the following platforms:
* ✅ Ubuntu
* ✅ MacOS Intel Chip (BigSur)
* ❌ MacOS M1 Chip (BigSur)

| ***Note*** - We are facing some errors when installing & running `pgloader` on MacOS M1 Chip. Raise a PR if you have any solution


### Pre Requisites
1. **Docker**
2. **MySQL DB**
   
   Assuming that you have the smartsell & launchhpad db's available on your local machine. Connect with Sasank or Vicky to get the app running locally.
3. **Install pgloader**
   
    *Ubuntu*
    ```bash
    apt-get install sbcl unzip libsqlite3-dev make curl gawk freetds-dev libzip-dev
    wget https://github.com/dimitri/pgloader/archive/refs/tags/v3.6.3.zip -O pgloader.zip
    unzip pgloader.zip
    cd pgloader-3.6.3
    make pgloader

    ./build/bin/pgloader --version
    ```
    *MacOS (Intel)*
    ```bash
    brew install sbcl sqlite make curl gawk freetds
    wget https://github.com/dimitri/pgloader/archive/refs/tags/v3.6.3.zip -O pgloader.zip
    unzip pgloader.zip
    cd pgloader-3.6.3
    make pgloader

    ./build/bin/pgloader --version
    ```

   *Macos (M1)*
   1. Enable Rosetta for Terminal on M1 Mac
      ```bash
      /usr/sbin/softwareupdate --install-rosetta --agree-to-license
      ```
      * Select the app(Terminal) in the Finder.
      * Right click on the app(Terminal) and select Get Info.
      * In `General`, check the `Open using Rosetta` check-box.
      * Restart the terminal.
      * Running `arch` should give `i386`
   2. Install `xcode`
      ```bash
      xcode-select --install
      ```
   3. Uninstall `arm64` brew
      ```bash
      which brew # /opt/homebrew

      /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/master/uninstall.sh)"
      ```
   4. Install `intel` brew
      ```bash
      /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"

      git -C $(brew --repository homebrew/core) checkout master

      which brew # /usr/local/bin/brew
      ```
   5. Install & symlink `openssl`
      ```bash
      brew install openssl

      sudo ln -s /usr/local/opt/openssl@3/lib/libcrypto.dylib /usr/local/lib/libcrypto.dylib

      sudo ln -s /usr/local/opt/openssl@3/lib/libssl.dylib /usr/local/lib/libssl.dylib
      ```
   6. Install pgloader
      ```bash
      brew install sbcl sqlite make curl gawk freetds
      wget https://github.com/dimitri/pgloader/archive/refs/tags/v3.6.3.zip -O pgloader.zip
      unzip pgloader.zip
      cd pgloader-3.6.3
      make pgloader

      ./build/bin/pgloader --version
      ```
4. **Install Hasura CLI**
    ```bash
    curl -L https://github.com/hasura/graphql-engine/raw/stable/cli/get.sh | bash

    hasura version
    ```

### Run the setup
1. Clone the repo
   ```bash
   gh repo clone adimyth/supabase
   ```
2. Setting up environment variables
   
   Inside `docker` directory, copy the contents of the `.env.example` file to `.env` file and update the values accordingly.
   ```bash
   cd docker
   cp .env.example .env
   ```
3. Running all the docker services
    ```bash
    docker-compose up -d
    ```
    Run the following command to check the status of the services
    ```bash
    docker-compose ps
    ```
4. Migrating from MySQL to Postgres
   
   `pgLoader` is an open-source database migration tool that aims to simplify the process of migrating to PostgreSQL.

   Here, we will migrate the smartsell & launchpad databases to postgres's default database(`postgres`).

   Navigate to the *"pgloader-3.6.3"* directory from the [previous section]()
   ```bash
   # Migrating smartsell from MySQL to Postgres
   ./build/bin/pgloader mysql://{MYSQL_USERNAME}:{MYSQL_PASSWORD}@localhost/smartsell postgresql://postgres:{POSTGRES_PASSWORD}@localhost/postgres

   # Migrating launchpad from MySQL to Postgres
   ./build/bin/pgloader mysql://{MYSQL_USERNAME}:{MYSQL_PASSWORD}@localhost/launchpad postgresql://postgres:{POSTGRES_PASSWORD}@localhost/postgres
   ```
   Refer `.env` file for `{POSTGRES_PASSWORD}`

   | ***Note***: You might face some errors when migrating using pgloader. 
   1. In case of `PGLOADER.CONNECTION:DB-CONNECTION-ERROR`, restart the mysql service.
   2. For other errors, repeat the above command until successful.
 
5. Apply existing migrations
    ```bash
    cd ../sharpsell-project/migrations
    hasura migrate apply --all-databases --endpoint http://localhost:8081
    hasura metadata apply --endpoint http://localhost:8081
    ```
6. Run Hasura console
    ```bash
    hasura console --endpoint http://localhost:8081
    ```
7. Verifying all services are running -
   1. Supabase dashboard - http://localhost:3000
   2. Postgres database - http://localhost:5432
   3. Hasura console - http://localhost:9695/console
   4. REST APIs - http://localhost:9695/console/api/rest/list - You should be able to see a list of REST APIs 

| 👉 *PS - Automation scripts are in progress.*

8. Verifying apis -
   We have ported some of the smartsell & launchpad APIs, we can use them to test the functionality of the app.
   1. Import the provided collection inside `sharpsell.postman_collection.json` inside postman
   2. Test out the APIs

---

## Resources
* [SmartSell APIs Migration (Notion)](https://www.notion.so/fppl/SmartSell-APIs-Migration-96c9984583ca411e9ee98f7cd7fd4616)
* [Launchpad APIs Migration (Notion)](https://www.notion.so/fppl/Launchpad-APIs-Migration-68b4b36455cd4e8fa5c047a012668fc2)