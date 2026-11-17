#!/bin/bash
set -e

# External interface
ip link set eth1 up
ip addr add 203.0.113.10/24 dev eth1
ip route replace default via 203.0.113.1

# Transit interface to core
ip link set eth2 up
ip addr add 10.10.0.1/30 dev eth2

# DMZ interface
ip link set eth3 up
ip addr add 10.10.30.1/24 dev eth3

# Enable IPv4 forwarding
sysctl -w net.ipv4.ip_forward=1

# Start FRR
sed -i 's/^ospfd=no/ospfd=yes/' /etc/frr/daemons
/usr/lib/frr/frrinit.sh start
vtysh -b

ip -br addr
ip route
