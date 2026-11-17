#!/bin/bash
set -e

# Create VLAN-aware bridge
ip link add br0 type bridge vlan_filtering 1
ip link set br0 up

# Add physical interfaces to bridge
for iface in eth1 eth2 eth3 eth4 eth5 eth6 eth7 eth8; do
    ip link set "$iface" up
    ip link set "$iface" master br0
done

# Configure trunk: tagged VLANs 10, 20, 99
bridge vlan del dev eth1 vid 1 2>/dev/null || true

for vlan in 10 20 99; do
    bridge vlan add dev eth1 vid "$vlan"
done

# Configure access ports
for iface in eth2 eth3 eth4; do
    bridge vlan del dev "$iface" vid 1 2>/dev/null || true
    bridge vlan add dev "$iface" vid 10 pvid untagged
done

for iface in eth5 eth6; do
    bridge vlan del dev "$iface" vid 1 2>/dev/null || true
    bridge vlan add dev "$iface" vid 20 pvid untagged
done

for iface in eth7 eth8; do
    bridge vlan del dev "$iface" vid 1 2>/dev/null || true
    bridge vlan add dev "$iface" vid 99 pvid untagged
done

# Disable VLAN 1 on the bridge itself
bridge vlan del dev br0 vid 1 2>/dev/null || true

# Show VLAN configuration
bridge vlan show
