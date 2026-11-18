#!/usr/bin/env bash
# mon - monitoring server: Prometheus + blackbox_exporter (Grafana joins this
# node's network namespace as a separate container, see the topology file).
source /lab/common/lib.sh
[ "$1" = "profile" ] && exit 0          # monitoring is identical in both profiles

disable_ipv6
wait_if eth1
ip addr add 10.10.99.20/24 dev eth1
ip link set eth1 up
# eth0 (the out-of-band console port) keeps Docker's default route. Everything
# inside the lab is reached through the management VLAN gateway instead:
ip route add 10.10.0.0/16 via 10.10.99.1
sysctl -qw net.ipv4.ip_forward=0
set_hosts
echo '10.10.30.10  portal.seclab.test' >> /etc/hosts
trust_root_ca

load_nft /lab/node/host-fw.nft
start_sshd /lab/common/sshd_config
start_node_exporter

nohup prometheus-blackbox-exporter \
      --config.file=/lab/node/blackbox.yml \
      --web.listen-address=127.0.0.1:9115 \
      >/var/log/blackbox.log 2>&1 &

mkdir -p /var/lib/prometheus/data
nohup prometheus \
      --config.file=/lab/node/prometheus.yml \
      --storage.tsdb.path=/var/lib/prometheus/data \
      --storage.tsdb.retention.time=7d \
      --web.listen-address=0.0.0.0:9090 \
      >/var/log/prometheus.log 2>&1 &
log "ready: $(ip -4 -br addr show eth1)"
