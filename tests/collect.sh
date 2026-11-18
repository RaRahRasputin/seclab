#!/usr/bin/env bash
# Saves the live state of every node (firewall rules, routes, OSPF, VLANs, ports,
# VPN, fail2ban, Prometheus targets) to evidence/state-<profile>-<timestamp>/
# for the report appendices. Run on the lab host from the repository root:
#     bash tests/collect.sh
# Private keys are never printed: "wg show" hides them, the OSPF key is masked,
# and no key file is read.
set -u
cd "$(dirname "$0")/.."
dir="evidence/state-$(cat state/profile)-$(date +%Y%m%d-%H%M%S)"
mkdir -p "$dir"

# grab <node> <command> <name>: run a command in a node, save output to <node>-<name>.txt
grab() { docker exec "$1" bash -c "$2" > "$dir/$1-$3.txt" 2>&1 || true; }

for n in edge core; do
  grab $n "nft list ruleset" nft-ruleset
  grab $n "vtysh -c 'show ip ospf neighbor' -c 'show ip ospf interface' \
             -c 'show ip route'" ospf-routes
  grab $n "vtysh -c 'show running-config' | sed 's/md5 .*/md5 <removed>/'" frr-running-config
  grab $n "bash /lab/common/ids.sh status; tail -n 20 /var/log/suricata/fast.log" ids
done
grab edge "wg show" wireguard
grab sw1  "bridge vlan show; bridge link show" vlans
for n in web app db bastion mon; do grab $n "nft list ruleset" nft-ruleset; done
grab bastion "fail2ban-client status sshd" fail2ban
grab mon "curl -s localhost:9090/api/v1/targets | jq -r '.data.activeTargets[]
          | [.labels.job, .labels.node // .labels.instance, .health] | @tsv'" prometheus-targets
for n in isp edge core sw1 web app db bastion mon ws1 ws2 remote attacker rogue; do
  grab $n "ip -br addr; echo; ip route; echo; ss -H -tulnp | awk '{print \$1, \$5, \$7}'" \
       interfaces-routes-ports
done
echo "state saved to $dir/  ($(ls "$dir" | wc -l) files)"
