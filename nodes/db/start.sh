#!/usr/bin/env bash
# db - PostgreSQL 16 database server.
#   start.sh                      run once by containerlab after the links exist
#   start.sh profile <name>       switch between "hardened" and "baseline"
source /lab/common/lib.sh

PGCONF=/etc/postgresql/16/main

setup() {
  disable_ipv6
  wait_if eth1
  ip addr add 10.10.20.20/24 dev eth1
  ip link set eth1 up
  ip route add default via 10.10.20.1
  set_hosts
  trust_root_ca

  # TLS material for PostgreSQL. The private key must belong to the postgres
  # user and be unreadable by anyone else, or the server refuses to start.
  install -d -m 700 -o postgres -g postgres /etc/postgresql/tls
  install -m 600 -o postgres -g postgres /lab/pki/db.key /etc/postgresql/tls/
  install -m 644 -o postgres -g postgres /lab/pki/db.crt /etc/postgresql/tls/

  start_sshd /lab/common/sshd_config
  start_node_exporter
}

apply_profile() {
  if [ "$1" = hardened ]; then
    # --- listen on one address, TLS required, strong password hashing ---
    cat > "$PGCONF/conf.d/seclab.conf" <<'EOF'
listen_addresses = '10.10.20.20'
ssl = on
ssl_cert_file = '/etc/postgresql/tls/db.crt'
ssl_key_file  = '/etc/postgresql/tls/db.key'
ssl_min_protocol_version = 'TLSv1.2'
password_encryption = scram-sha-256
log_connections = on
log_disconnections = on
EOF
    # pg_hba.conf = "host-based authentication": WHO may connect FROM WHERE and HOW.
    # hostssl  -> the rule only matches TLS connections (clear-text is refused)
    # /32      -> exactly one client address: the application server
    cat > "$PGCONF/pg_hba.conf" <<'EOF'
# TYPE    DATABASE  USER      ADDRESS          METHOD
local     all       postgres                   peer
hostssl   portal    portal    10.10.20.10/32   scram-sha-256
EOF
    PASSWORD="$(cat /lab/pki/db_password)"
  else
    # --- baseline: listen everywhere, no TLS, anyone may try, weak password ---
    cat > "$PGCONF/conf.d/seclab.conf" <<'EOF'
listen_addresses = '*'
ssl = off
password_encryption = scram-sha-256
log_connections = on
EOF
    cat > "$PGCONF/pg_hba.conf" <<'EOF'
# TYPE    DATABASE  USER      ADDRESS          METHOD
local     all       postgres                   peer
host      all       all       0.0.0.0/0        scram-sha-256
EOF
    PASSWORD="portal123"
  fi
  chown postgres:postgres "$PGCONF/conf.d/seclab.conf" "$PGCONF/pg_hba.conf"

  pg_ctlcluster 16 main restart 2>/dev/null || pg_ctlcluster 16 main start
  for _ in $(seq 1 30); do pg_isready -q -h /var/run/postgresql && break; sleep 0.5; done

  # First start only: create the role, database and sample data.
  EXISTS="SELECT 1 FROM pg_database WHERE datname='portal'"
  if ! su postgres -c "psql -tAc \"$EXISTS\"" | grep -q 1; then
    su postgres -c "psql -q -v ON_ERROR_STOP=1 -f /lab/node/init.sql" && log "database initialised"
  fi
  su postgres -c "psql -q -c \"ALTER ROLE portal PASSWORD '$PASSWORD'\""

  if [ "$1" = hardened ]; then load_nft /lab/node/host-fw.nft
  else nft flush ruleset; fi
}

case "${1:-setup}" in
  setup)   setup; apply_profile "$(current_profile)" ;;
  profile) apply_profile "$2" ;;
  *) echo "usage: start.sh [setup | profile hardened|baseline]"; exit 1 ;;
esac
log "ready (profile: ${2:-$(current_profile)})"
