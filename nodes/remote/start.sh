#!/usr/bin/env bash
# remote - a legitimate machine on the internet. It plays three parts:
#   1. a customer using the public portal        (curl https://portal.seclab.test)
#   2. the administrator working from home        (WireGuard VPN, then SSH via the bastion)
#   3. "some website on the internet" on port 80  (used to prove NAT from inside)
source /lab/common/lib.sh
[ "$1" = "profile" ] && exit 0

disable_ipv6
wait_if eth1
ip addr add 203.0.113.50/24 dev eth1
ip link set eth1 up
echo '203.0.113.1  portal.seclab.test' >> /etc/hosts
echo '10.10.99.10  bastion'            >> /etc/hosts
trust_root_ca

# --- the administrator's SSH identity (private key never leaves this machine) ---
install -d -m 700 /root/.ssh
install -m 600 /lab/pki/admin_ed25519 /root/.ssh/id_ed25519
install -m 644 /lab/node/ssh_config   /root/.ssh/config

# --- the administrator's VPN profile (brought up on demand: wg-quick up wg0) ---
install -d -m 700 /etc/wireguard
install -m 600 /lab/pki/wg0.conf /etc/wireguard/wg0.conf

# --- a stand-in public website; its access log shows which address clients come from ---
mkdir -p /srv/www && echo 'hello from the internet' > /srv/www/index.html
cd /srv/www && nohup python3 -m http.server 80 >/var/log/www.log 2>&1 &
log "ready: $(ip -4 -br addr show eth1)"
