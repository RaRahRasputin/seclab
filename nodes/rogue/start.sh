#!/usr/bin/env bash
# rogue - the INTERNAL attacker: an unauthorised device plugged into a spare
# office wall port (VLAN 10), or equally a staff PC that has been compromised.
# It gets no hosts file and no CA certificate: it knows nothing it has not found out.
source /lab/common/lib.sh
[ "$1" = "profile" ] && exit 0

disable_ipv6
wait_if eth1
ip addr add 10.10.10.66/24 dev eth1
ip link set eth1 up
ip route add default via 10.10.10.1
log "ready: $(ip -4 -br addr show eth1)"
