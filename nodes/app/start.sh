#!/usr/bin/env bash
# app - application server (Flask API behind an nginx TLS front door).
#   start.sh                      run once by containerlab after the links exist
#   start.sh profile <name>       switch between "hardened" and "baseline"
source /lab/common/lib.sh

setup() {
  disable_ipv6
  wait_if eth1
  ip addr add 10.10.20.10/24 dev eth1
  ip link set eth1 up
  ip route add default via 10.10.20.1        # core's VLAN 20 sub-interface
  set_hosts
  trust_root_ca

  install -d -m 700 /etc/nginx/tls
  install -m 600 /lab/pki/app.key /etc/nginx/tls/
  install -m 644 /lab/pki/app.crt /lab/pki/root.crt /etc/nginx/tls/
  install -d -m 755 /etc/seclab
  install -m 644 /lab/pki/root.crt /etc/seclab/root.crt   # used by the app to verify the database

  start_sshd /lab/common/sshd_config
  start_node_exporter
}

apply_profile() {
  # ---- Flask application under gunicorn, as the unprivileged www-data user ----
  if [ "$1" = hardened ]; then
    DB_PASSWORD="$(cat /lab/pki/db_password)"; DB_SSLMODE=verify-full
  else
    DB_PASSWORD="portal123";                   DB_SSLMODE=disable
  fi
  pkill -f gunicorn 2>/dev/null; sleep 0.5
  # HOME is set because the PostgreSQL client library looks for optional files
  # in $HOME/.postgresql and must not be pointed at root's home directory.
  HOME=/var/www DB_PASSWORD="$DB_PASSWORD" DB_SSLMODE="$DB_SSLMODE" DB_HOST=db.seclab.test \
    gunicorn --chdir /lab/node --bind 127.0.0.1:5000 --workers 2 \
             --user www-data --group www-data --daemon \
             --error-logfile /var/log/gunicorn.log app:app

  # ---- nginx front door ----
  cp "/lab/node/nginx-$1.conf" /etc/nginx/nginx.conf
  nginx -t 2>&1 | sed 's/^/[app] /'
  if pgrep -x nginx >/dev/null; then nginx -s reload; else nginx; fi

  if [ "$1" = hardened ]; then load_nft /lab/node/host-fw.nft
  else nft flush ruleset; fi
}

case "${1:-setup}" in
  setup)   setup; apply_profile "$(current_profile)" ;;
  profile) apply_profile "$2" ;;
  *) echo "usage: start.sh [setup | profile hardened|baseline]"; exit 1 ;;
esac
log "ready (profile: ${2:-$(current_profile)})"
