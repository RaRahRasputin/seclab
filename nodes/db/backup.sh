#!/usr/bin/env bash
# db - database backup and restore test.
#   backup.sh backup          dump the portal database, compress it, record a checksum,
#                             keep the newest 7 dumps
#   backup.sh restore-test    restore the newest dump into a scratch database and
#                             compare row counts with the live database
# Run from the lab host:  docker exec db bash /lab/node/backup.sh backup
#                        docker exec db bash /lab/node/backup.sh restore-test
#
# A backup that has never been restored is only a hope. The restore test is the
# evidence that the Recovery Point (the dump) can actually become a database again.
set -euo pipefail
DIR=/var/backups/portal
KEEP=7
install -d -m 700 -o postgres -g postgres "$DIR"

case "${1:-}" in
  backup)
    f="$DIR/portal-$(date +%Y%m%d-%H%M%S).sql.gz"
    start=$(date +%s%N)
    # pg_dump writes a consistent snapshot even while the application is reading.
    su postgres -c "pg_dump --no-owner portal" | gzip > "$f"
    chown postgres:postgres "$f"; chmod 600 "$f"
    ( cd "$DIR" && sha256sum "$(basename "$f")" > "$(basename "$f").sha256" )
    # retention: delete everything except the newest $KEEP dumps (and their checksums)
    ls -1t "$DIR"/portal-*.sql.gz | tail -n +$((KEEP + 1)) | while read -r old; do
      rm -f "$old" "$old.sha256"
    done
    ms=$(( ($(date +%s%N) - start) / 1000000 ))
    echo "backup written: $f  ($(stat -c %s "$f") bytes, $ms ms)"
    ;;
  restore-test)
    f="$(ls -1t "$DIR"/portal-*.sql.gz 2>/dev/null | head -1)"
    [ -n "$f" ] || { echo "no backup found - run: backup.sh backup"; exit 1; }
    ( cd "$DIR" && sha256sum -c "$(basename "$f").sha256" )            # 1. integrity
    start=$(date +%s%N)
    su postgres -c "dropdb --if-exists portal_restore_test"
    su postgres -c "createdb portal_restore_test"
    # 2. restore
    gunzip -c "$f" | su postgres -c "psql -q -v ON_ERROR_STOP=1 portal_restore_test" >/dev/null
    # 3. compare row counts, printed as customers/orders (chr(47) is "/")
    Q="select (select count(*) from customers) || chr(47) || (select count(*) from orders)"
    count() { su postgres -c "psql -tA -d $1 -c '$Q'"; }
    live="$(count portal)"; restored="$(count portal_restore_test)"
    su postgres -c "dropdb portal_restore_test"
    echo "restore time: $(( ($(date +%s%N) - start) / 1000000 )) ms"
    echo "rows customers/orders  live: $live   restored: $restored"
    if [ "$live" = "$restored" ]; then echo "RESTORE TEST PASSED"
    else echo "RESTORE TEST FAILED"; exit 1; fi
    ;;
  *) echo "usage: backup.sh backup | restore-test"; exit 1 ;;
esac
