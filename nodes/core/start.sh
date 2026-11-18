#!/usr/bin/env bash
# core - internal Layer-3 switch: inter-VLAN routing plus the segmentation firewall.
#   start.sh                      run once by containerlab after the links exist
#   start.sh profile <name>       switch between "hardened" and "baseline"
source /lab/common/lib.sh

setup() {
  disable_ipv6
  for i in eth1 eth2; do wait_if "$i"; done

  # ---- addressing -------------------------------------------------------
  ip addr add 10.255.0.2/32 dev lo        # router-id loopback
  ip addr add 10.10.0.2/30  dev eth1      # transit to edge
  ip link set eth1 up
  ip link set eth2 up                     # the trunk itself carries no IP address

  # "Router on a stick": one physical trunk, one 802.1Q sub-interface per VLAN.
  # Each sub-interface is the default gateway of its VLAN.
  # (Cisco equivalent: interface g0/1.10 / encapsulation dot1Q 10 / ip address ...)
  for vid in 10 20 99; do
    ip link add link eth2 name "eth2.$vid" type vlan id "$vid"
    ip addr add "10.10.$vid.1/24" dev "eth2.$vid"
    ip link set "eth2.$vid" up
  done

  # ---- behave as a router ----------------------------------------------
  sysctl -qw net.ipv4.ip_forward=1
  sysctl -qw net.ipv4.conf.all.rp_filter=1
  sysctl -qw net.ipv4.conf.all.accept_redirects=0
  sysctl -qw net.ipv4.conf.all.send_redirects=0
  set_hosts

  # ---- OSPF (FRRouting) -------------------------------------------------
  cp /lab/common/frr-daemons /etc/frr/daemons
  cp /lab/node/frr.conf      /etc/frr/frr.conf
  chown frr:frr /etc/frr/daemons /etc/frr/frr.conf
  chmod 640 /etc/frr/frr.conf
  /usr/lib/frr/frrinit.sh start

  # ---- management services ---------------------------------------------
  start_sshd /lab/common/sshd_config
  start_node_exporter

  # ---- intrusion detection: watch the least-trusted internal zone ----
  bash /lab/common/ids.sh start eth2.10
  nohup bash /lab/common/router-metrics.sh >/var/log/router-metrics.log 2>&1 &
}

apply_profile() {
  load_nft "/lab/node/nft-$1.nft"
  conntrack -F >/dev/null 2>&1 || true
}

case "${1:-setup}" in
  setup)   setup; apply_profile "$(current_profile)" ;;
  profile) apply_profile "$2" ;;
  *) echo "usage: start.sh [setup | profile hardened|baseline]"; exit 1 ;;
esac
log "ready (profile: ${2:-$(current_profile)})"
