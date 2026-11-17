#!/bin/bash
set -e

# Create a bridge for the simulated internet
ip link add br0 type bridge
ip link set br0 up

# Connect all three ISP-facing interfaces
for iface in eth1 eth2 eth3; do
    ip link set "$iface" up
    ip link set "$iface" master br0
done

# Assign the ISP gateway address to the bridge
ip addr add 203.0.113.1/24 dev br0

ip -br addr
bridge link
