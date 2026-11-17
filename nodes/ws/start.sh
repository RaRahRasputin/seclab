#!/bin/bash
set -e

HOST_ID="${1:?}"

case "$HOST_ID" in
    11) IP="10.10.10.11" ;;
    12) IP="10.10.10.12" ;;
    *) exit 1 ;;
esac

ip link set eth1 up
ip addr add "$IP/24" dev eth1
ip route replace default via 10.10.10.1
