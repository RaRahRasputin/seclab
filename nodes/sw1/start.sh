#!/usr/bin/env bash
# sw1: VLAN-aware access switch (the office "distribution switch").
#
#   eth1          802.1Q trunk to core, carries VLANs 10, 20 and 99 tagged
#   eth2 eth3 eth4   access ports, VLAN 10  USERS    (ws1, ws2, rogue)
#   eth5 eth6        access ports, VLAN 20  SERVERS  (app, db)
#   eth7 eth8        access ports, VLAN 99  MGMT     (bastion, mon)
#
# This is the Linux equivalent of the Cisco commands
#   switchport mode trunk / switchport trunk allowed vlan 10,20,99
#   switchport mode access / switchport access vlan 10
source /lab/common/lib.sh
disable_ipv6

# vlan_filtering 1  -> the bridge enforces VLAN membership per port
# vlan_default_pvid 0 -> ports belong to NO VLAN until we say so (deny by default)
ip link add br0 type bridge vlan_filtering 1 vlan_default_pvid 0
ip link set br0 up

for port in eth1 eth2 eth3 eth4 eth5 eth6 eth7 eth8; do
  wait_if "$port"
  ip link set "$port" master br0
  ip link set "$port" up
done

# Trunk: frames for these VLANs leave eth1 with an 802.1Q tag.
for vid in 10 20 99; do
  bridge vlan add dev eth1 vid "$vid"
done

# Access ports: "pvid" tags frames arriving on the port with this VLAN,
# "untagged" strips the tag again when frames leave towards the host.
access() { bridge vlan add dev "$1" vid "$2" pvid untagged; }
access eth2 10; access eth3 10; access eth4 10
access eth5 20; access eth6 20
access eth7 99; access eth8 99

log "sw1 VLAN table:"
bridge vlan show
