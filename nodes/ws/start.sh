#!/usr/bin/env bash
# ws1 / ws2 - staff workstations in the USERS VLAN.
# Usage (from the topology file):  start.sh <last-octet>     e.g. start.sh 11
source /lab/common/lib.sh
[ "$1" = "profile" ] && exit 0          # workstations are identical in both profiles

disable_ipv6
wait_if eth1
ip addr add "10.10.10.$1/24" dev eth1
ip link set eth1 up
ip route add default via 10.10.10.1     # core's VLAN 10 sub-interface

set_hosts
echo '10.10.30.10  portal.seclab.test' >> /etc/hosts   # staff reach the portal on its DMZ address
trust_root_ca
log "ready: $(ip -4 -br addr show eth1)"
