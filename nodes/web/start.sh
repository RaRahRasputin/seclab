#!/usr/bin/env bash
# web - public reverse proxy in the DMZ.
#   start.sh                      run once by containerlab after the links exist
#   start.sh profile <name>       switch between "hardened" and "baseline"
source /lab/common/lib.sh

setup() {
  disable_ipv6
  wait_if eth1
  ip addr add 10.10.30.10/24 dev eth1
  ip link set eth1 up
  ip route add default via 10.10.30.1        # edge's DMZ interface
  set_hosts
  trust_root_ca

  # ---- site content -----------------------------------------------------
  mkdir -p /srv/portal/files
  cp /lab/node/index.html /srv/portal/index.html
  # A 20 MB file of random bytes for the throughput benchmark...
  head -c 20M /dev/urandom > /srv/portal/files/testfile.bin
  # ...and a file somebody "left lying around", for the directory-listing test.
  printf 'name,email\nAlex Doe,alex.doe@example.test\n' > /srv/portal/files/staff-export-2025.csv
  chown -R www-data:www-data /srv/portal

  # ---- TLS material: readable by root only; nginx reads it before dropping privileges
  install -d -m 700 /etc/nginx/tls
  install -m 600 /lab/pki/web.key /lab/pki/web-client.key /etc/nginx/tls/
  install -m 644 /lab/pki/web.crt /lab/pki/web-client.crt /lab/pki/root.crt /etc/nginx/tls/

  start_sshd /lab/common/sshd_config
  start_node_exporter
}

apply_profile() {
  cp "/lab/node/nginx-$1.conf" /etc/nginx/nginx.conf
  nginx -t 2>&1 | sed 's/^/[web] /'
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
