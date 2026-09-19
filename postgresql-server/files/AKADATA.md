# PostgreSQL on Akadata

No database cluster is created while the APK is built or installed. As root,
initialize the default cluster explicitly with:

    postgresql-initdb

The helper creates `/var/lib/postgresql/data` for the `postgres` account, uses
peer authentication for local Unix-socket connections, uses SCRAM-SHA-256 for
host connections, and binds PostgreSQL to localhost. Set `PGDATA` when a
different data directory is required.

The OpenRC service is not added to a runlevel by the package. After reviewing
the generated configuration, enable it explicitly with:

    rc-update add postgresql default
    rc-service postgresql start

Remote access remains disabled unless an administrator changes both the listen
address and `pg_hba.conf`. The initialization helper never creates a password.
