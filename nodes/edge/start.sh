#!/usr/bin/env bash
# edge - perimeter router and firewall.
#   start.sh                      run once by containerlab after the links exist
#   start.sh profile <name>       switch between "hardened" and "baseline"
source /lab/common/lib.sh

setup() {
  disable_ipv6
  for i in eth1 eth2 eth3; do wait_if "$i"; done

  # ---- addressing -------------------------------------------------------
  ip addr add 10.255.0.1/32   dev lo      # router-id loopback
  ip addr add 203.0.113.1/24  dev eth1    # WAN  (simulated internet)
  ip addr add 10.10.0.1/30    dev eth2    # transit to core
  ip addr add 10.10.30.1/24   dev eth3    # DMZ gateway
  for i in eth1 eth2 eth3; do ip link set "$i" up; done

  # ---- behave as a router ----------------------------------------------
  sysctl -qw net.ipv4.ip_forward=1
  sysctl -qw net.ipv4.conf.all.rp_filter=1          # kernel reverse-path check
  sysctl -qw net.ipv4.conf.all.accept_redirects=0   # ignore ICMP redirects
  sysctl -qw net.ipv4.conf.all.send_redirects=0
  set_hosts

  # ---- WireGuard VPN endpoint (interface wg0, UDP 51820) ----------------
  install -d -m 700 /etc/wireguard
  install -m 600 /lab/pki/wg0.conf /etc/wireguard/wg0.conf
  wg-quick up wg0 2>&1 | sed 's/^/[edge] wg: /'

  # ---- OSPF (FRRouting) -------------------------------------------------
  cp /lab/common/frr-daemons /etc/frr/daemons
  cp /lab/node/frr.conf      /etc/frr/frr.conf
  chown frr:frr /etc/frr/daemons /etc/frr/frr.conf
  chmod 640 /etc/frr/frr.conf                        # it contains the OSPF key
  /usr/lib/frr/frrinit.sh start

  # ---- management services ---------------------------------------------
  start_sshd /lab/common/sshd_config
  start_node_exporter

  # ---- intrusion detection: watch the internet-facing interface ----
  bash /lab/common/ids.sh start eth1
  nohup bash /lab/common/router-metrics.sh >/var/log/router-metrics.log 2>&1 &
}

apply_profile() {
  load_nft "/lab/node/nft-$1.nft"
  conntrack -F >/dev/null 2>&1 || true   # forget connections allowed by the old rules
}

case "${1:-setup}" in
  setup)   setup; apply_profile "$(current_profile)" ;;
  profile) apply_profile "$2" ;;
  *) echo "usage: start.sh [setup | profile hardened|baseline]"; exit 1 ;;
esac
log "ready (profile: ${2:-$(current_profile)})"
