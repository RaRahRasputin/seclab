#!/usr/bin/env bash
# attacker - the EXTERNAL attacker, somewhere on the (simulated) internet.
source /lab/common/lib.sh
[ "$1" = "profile" ] && exit 0

disable_ipv6
wait_if eth1
ip addr add 203.0.113.66/24 dev eth1
ip link set eth1 up
# No default route: the only network that exists for this host is the simulated
# internet segment, and the only target on it is the edge router's public address.
echo '203.0.113.1  portal.seclab.test' >> /etc/hosts
log "ready: $(ip -4 -br addr show eth1)"
