#!/usr/bin/env bash
# bastion - the administrative jump host in the management VLAN.
#   start.sh                      run once by containerlab after the links exist
#   start.sh profile <name>       switch between "hardened" and "baseline"
source /lab/common/lib.sh

setup() {
  disable_ipv6
  wait_if eth1
  ip addr add 10.10.99.10/24 dev eth1
  ip link set eth1 up
  ip route add default via 10.10.99.1        # core's VLAN 99 sub-interface
  set_hosts
  start_syslog
  start_node_exporter
  nohup bash /lab/node/f2b-metrics.sh >/var/log/f2b-metrics.log 2>&1 &
}

apply_profile() {
  fail2ban-client stop >/dev/null 2>&1

  # Start every profile with a clean slate, so that failed logins recorded
  # under the previous profile cannot cause a ban under the new one:
  #   1. archive the authentication log and tell rsyslog to open a fresh one
  #   2. make fail2ban forget its saved bans (dbfile = None: keep them in memory only)
  if [ -s /var/log/auth.log ]; then
    mv /var/log/auth.log "/var/log/auth.log.$(date +%Y%m%d-%H%M%S)"
  fi
  install -m 640 -o syslog -g adm /dev/null /var/log/auth.log
  pkill -HUP -x rsyslogd 2>/dev/null
  rm -f /var/lib/fail2ban/fail2ban.sqlite3
  printf '[DEFAULT]\ndbfile = None\n' > /etc/fail2ban/fail2ban.local

  if [ "$1" = hardened ]; then
    passwd -l jsmith >/dev/null                       # lock the weak account
    load_nft /lab/node/host-fw.nft
    start_sshd /lab/node/sshd_config-hardened
    cp /lab/node/jail.local /etc/fail2ban/jail.local
    rm -f /etc/fail2ban/jail.d/defaults-debian.conf   # Ubuntu's default assumes systemd
    mkdir -p /run/fail2ban
    fail2ban-client start >/dev/null && log "fail2ban started"
  else
    echo 'jsmith:Summer2025' | chpasswd               # a guessable password
    nft flush ruleset
    start_sshd /lab/node/sshd_config-baseline
  fi
}

case "${1:-setup}" in
  setup)   setup; apply_profile "$(current_profile)" ;;
  profile) apply_profile "$2" ;;
  *) echo "usage: start.sh [setup | profile hardened|baseline]"; exit 1 ;;
esac
log "ready (profile: ${2:-$(current_profile)})"
