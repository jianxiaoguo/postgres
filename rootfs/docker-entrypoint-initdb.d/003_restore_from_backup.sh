#!/usr/bin/env bash

cat << EOF >> "$PGDATA/postgresql.conf"
wal_level = archive
archive_mode = on
archive_command = 'envdir "${WALG_ENVDIR}" wal-g wal-push %p'
archive_timeout = 60
EOF

# ensure $PGDATA has the right permissions
chown -R postgres:postgres "$PGDATA"
chmod 0700 "$PGDATA"

# reboot the server for wal_level to be set before backing up
echo "Rebooting postgres to enable archive mode"
su-exec postgres pg_ctl -D "$PGDATA" -w restart

# check if there are any backups -- if so, let's restore
# we could probably do better than just testing number of lines -- one line is just a heading, meaning no backups

if [[ $(envdir "$WALG_ENVDIR" wal-g backup-list | wc -l) -gt "1" ]]; then
  echo "Found backups. Restoring from backup..."
  su-exec postgres pg_ctl -D "$PGDATA" -w stop
  rm -rf "$PGDATA"
  envdir "$WALG_ENVDIR" wal-g backup-fetch "$PGDATA" LATEST
  cat << EOF > "$PGDATA/postgresql.conf"
# These settings are initialized by initdb, but they can be changed.
log_timezone = 'UTC'
lc_messages = 'C'     # locale for system error message
lc_monetary = 'C'     # locale for monetary formatting
lc_numeric = 'C'      # locale for number formatting
lc_time = 'C'       # locale for time formatting
default_text_search_config = 'pg_catalog.english'
wal_level = archive
archive_mode = on
archive_command = 'envdir "${WALG_ENVDIR}" wal-g wal-push %p'
archive_timeout = 60
listen_addresses = '*'
EOF
  cat << EOF > "$PGDATA/pg_hba.conf"
# "local" is for Unix domain socket connections only
local   all             all                                     trust
# IPv4 local connections:
host    all             all             127.0.0.1/32            trust
# IPv6 local connections:
host    all             all             ::1/128                 trust
# IPv4 global connections
host    all             all             0.0.0.0/0               md5
EOF
  touch "$PGDATA/pg_ident.conf"
  echo "restore_command = 'envdir "${WALG_ENVDIR}" wal-g wal-fetch \"%f\" \"%p\"'" >> "$PGDATA/recovery.conf"
  chown -R postgres:postgres "$PGDATA"
  chmod 0700 "$PGDATA"
  su-exec postgres pg_ctl -D "$PGDATA" \
      -o "-c listen_addresses=''" \
      -w start
fi

# ensure $PGDATA has the right permissions
chown -R postgres:postgres "$PGDATA"
chmod 0700 "$PGDATA"
