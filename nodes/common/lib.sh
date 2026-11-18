#!/usr/bin/env bash
# Shared helper functions, sourced by every node's start.sh.
# Mounted read-only into every container at /lab/common/lib.sh

log() { echo "[$(hostname)] $*"; }

# Current security profile ("hardened" or "baseline"), read from state/profile
# on the lab host (mounted at /lab/state). You write that file before deploying.
current_profile() { cat /lab/state/profile 2>/dev/null || echo hardened; }

# Wait until containerlab has attached a data-plane interface.
wait_if() {
  local i
  for i in $(seq 1 50); do
    ip link show "$1" >/dev/null 2>&1 && return 0
    sleep 0.2
  done
  log "ERROR: interface $1 never appeared"; return 1
}

# The lab is IPv4-only. An unused protocol is unmanaged attack surface, so
# switch IPv6 off. (The sysctl is absent on IPv6-less kernels, hence || true.)
disable_ipv6() {
  sysctl -qw net.ipv6.conf.all.disable_ipv6=1 2>/dev/null || true
  sysctl -qw net.ipv6.conf.default.disable_ipv6=1 2>/dev/null || true
}

# Static name resolution. The lab has no DNS server, so every node gets the
# same hosts file. The marker makes the function safe to run twice.
set_hosts() {
  grep -q 'SECLAB-HOSTS' /etc/hosts 2>/dev/null && return 0
  { echo '# SECLAB-HOSTS'; cat /lab/common/hosts; } >> /etc/hosts
}

# Trust the lab's private root CA system-wide.
trust_root_ca() {
  [ -f /lab/pki/root.crt ] || return 0
  cp /lab/pki/root.crt /usr/local/share/ca-certificates/seclab-root.crt
  update-ca-certificates >/dev/null 2>&1 || true
}

# Prometheus node_exporter: host metrics on TCP 9100, plus any *.prom files
# that our own scripts drop into the textfile directory.
start_node_exporter() {
  pgrep -f prometheus-node-exporter >/dev/null && return 0
  mkdir -p /var/lib/node_exporter/textfile
  nohup prometheus-node-exporter \
      --web.listen-address=:9100 \
      --collector.textfile.directory=/var/lib/node_exporter/textfile \
      >/var/log/node_exporter.log 2>&1 &
}

# Containers have no systemd, so the syslog daemon is started by hand. It gives
# each node an ordinary /var/log/auth.log, which is what sshd writes to and
# what fail2ban reads.
start_syslog() {
  pgrep -x rsyslogd >/dev/null && return 0
  rm -f /run/rsyslogd.pid
  rsyslogd
}

# Install the administrator's public key and (re)start sshd with the given config.
start_sshd() {
  local cfg="$1"
  start_syslog
  install -d -m 700 -o labadmin -g labadmin /home/labadmin/.ssh
  install -m 600 -o labadmin -g labadmin \
          /lab/pki/admin_ed25519.pub /home/labadmin/.ssh/authorized_keys
  [ -f /etc/ssh/ssh_host_ed25519_key ] || ssh-keygen -A >/dev/null
  mkdir -p /run/sshd
  pkill -x sshd 2>/dev/null; sleep 0.3
  /usr/sbin/sshd -f "$cfg"
}

# Load a complete nftables ruleset from a file, replacing whatever is loaded.
# The file is syntax-checked first (nft -c). If it contains an error, the rules
# that are currently loaded stay in force and the error is printed - a typo
# must never leave a firewall wide open.
load_nft() {
  if ! nft -c -f "$1"; then
    log "ERROR: $1 has errors - keeping the rules that are already loaded"
    return 1
  fi
  nft flush ruleset
  nft -f "$1" && log "firewall loaded: $1"
}
