#!/bin/bash
#
# Originally copied and modified from
# https://github.com/docker-library/postgres/blob/ec5ce80ca914e02c2d5eb9fde424039d4cee032e/9.4/docker-entrypoint.sh
#
set -e

set_listen_addresses() {
	sedEscapedValue="$(echo "$1" | sed 's/[\/&]/\\&/g')"
	sed -ri "s/^#?(listen_addresses\s*=\s*)\S+/\1'$sedEscapedValue'/" "$PGDATA/postgresql.conf"
}

POSTGRES_USER="$(cat /var/run/secrets/drycc/database/creds/user)"
POSTGRES_PASSWORD="$(cat /var/run/secrets/drycc/database/creds/password)"
POSTGRES_CONTROLLER="$(cat /var/run/secrets/drycc/database/creds/controller_db_name)"
POSTGRES_MANAGER="$(cat /var/run/secrets/drycc/database/creds/manager_db_name)"
POSTGRES_PASSPORT="$(cat /var/run/secrets/drycc/database/creds/passport_db_name)"

if [ "$1" = 'postgres' ]; then
	mkdir -p "$PGDATA"
	chmod 700 "$PGDATA"
	chown -R postgres "$PGDATA"

	chmod g+s /run/postgresql
	chown -R postgres /run/postgresql

	# look specifically for PG_VERSION, as it is expected in the DB dir
	if [ ! -s "$PGDATA/PG_VERSION" ]; then
		gosu postgres initdb

		# check password first so we can output the warning before postgres
		# messes it up
		if [ "$POSTGRES_PASSWORD" ]; then
			pass="PASSWORD '$POSTGRES_PASSWORD'"
			authMethod=md5
		else
			# The - option suppresses leading tabs but *not* spaces. :)
			cat >&2 <<-'EOWARN'
				****************************************************
				WARNING: No password has been set for the database.
				         This will allow anyone with access to the
				         Postgres port to access your database. In
				         Docker's default configuration, this is
				         effectively any other container on the same
				         system.

				         Use "-e POSTGRES_PASSWORD=password" to set
				         it in "docker run".
				****************************************************
			EOWARN

			pass=
			authMethod=trust
		fi

		{ echo; echo "host all all 0.0.0.0/0 $authMethod"; } >> "$PGDATA/pg_hba.conf"

		# internal start of server in order to allow set-up using psql-client
		# does not listen on TCP/IP and waits until start finishes
		gosu postgres pg_ctl -D "$PGDATA" \
			-o "-c listen_addresses=''" \
			-w start

		: ${POSTGRES_USER:=postgres}
#		: ${POSTGRES_DB:=$POSTGRES_USER}
#		export POSTGRES_USER POSTGRES_DB

		if [ "$POSTGRES_CONTROLLER" != '' ]; then
			psql --username postgres <<-EOSQL
				CREATE DATABASE "$POSTGRES_CONTROLLER" ;
			EOSQL
			echo
		fi

		if [ "$POSTGRES_MANAGER" != '' ]; then
			psql --username postgres <<-EOSQL
				CREATE DATABASE "$POSTGRES_MANAGER" ;
			EOSQL
			echo
		fi

    if [ "$POSTGRES_PASSPORT" != '' ]; then
			psql --username postgres <<-EOSQL
				CREATE DATABASE "$POSTGRES_PASSPORT" ;
			EOSQL
			echo
		fi

		if [ "$POSTGRES_USER" = 'postgres' ]; then
			op='ALTER'
		else
			op='CREATE'
		fi

		psql --username postgres <<-EOSQL
			$op USER "$POSTGRES_USER" WITH SUPERUSER $pass ;
		EOSQL
		echo

		echo
		for f in /docker-entrypoint-initdb.d/*; do
			case "$f" in
				*.sh)  echo "$0: running $f"; . "$f" ;;
				*.sql)
					echo "$0: running $f";
					psql -v ON_ERROR_STOP=1 --username "$POSTGRES_USER" --dbname "$POSTGRES_DB" < "$f"
					echo
					;;
				*)     echo "$0: ignoring $f" ;;
			esac
			echo
		done

		gosu postgres pg_ctl -D "$PGDATA" -m fast -w stop
		set_listen_addresses '*'

		echo
		echo 'PostgreSQL init process complete; ready for start up.'
		echo
	fi

	exec gosu postgres "$@"
fi

exec "$@"
