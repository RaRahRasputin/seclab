#!/bin/bash
set -e

ip link set eth1 up
ip addr add 203.0.113.50/24 dev eth1
ip route replace default via 203.0.113.1

ip -br addr
ip route
