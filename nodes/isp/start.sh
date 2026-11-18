#!/usr/bin/env bash
# isp: a plain Layer-2 switch standing in for "the internet".
# Everything plugged into it shares the 203.0.113.0/24 segment
# (TEST-NET-3, an address block reserved by RFC 5737 for documentation and
# testing, so it can never collide with a real network).
source /lab/common/lib.sh
disable_ipv6

ip link add br0 type bridge
ip link set br0 up
for port in eth1 eth2 eth3; do
  wait_if "$port"
  ip link set "$port" master br0
  ip link set "$port" up
done
log "isp switch up: $(ls /sys/class/net/br0/brif | tr '\n' ' ')"
