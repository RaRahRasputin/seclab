#!/bin/bash
set -e

ip link set eth1 up
ip addr add 203.0.113.1/24 dev eth1

ip link set eth2 up
ip addr add 203.0.113.2/24 dev eth2

ip link set eth3 up
ip addr add 203.0.113.3/24 dev eth3

ip route
