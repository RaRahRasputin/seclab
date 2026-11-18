#!/usr/bin/env bash
# Pre-flight check: finds typing / pasting mistakes BEFORE you deploy.
# Run on the lab host, from the repository root:   bash tests/preflight.sh
#
# Every check uses the real program that will later read the file (bash, nft,
# sshd, nginx, promtool, suricata, fail2ban, python), run inside your own images,
# with the files mounted read-only. Nothing is deployed and nothing is changed.
# Needs: the five images (P3) and the PKI (P5.2).
set -u
cd "$(dirname "$0")/.."
OK=0; BAD=0
pass() { echo "  ok    $1"; OK=$((OK+1)); }
fail() { echo "  FAIL  $1"; BAD=$((BAD+1)); }
check() {   # check <label> <command...>: run the command, report ok / FAIL with its output
  local label="$1"; shift
  local out
  if out="$("$@" 2>&1)"; then
    pass "$label"
  else
    fail "$label"; echo "$out" | sed 's/^/        /' | tail -5
  fi
}
run() {     # run <image> <shell command>: execute inside a throw-away container
  docker run --rm --cap-add NET_ADMIN -v "$PWD:/repo:ro" "$1" bash -c "$2"
}

echo "1. required files"
REQUIRED="seclab.clab.yaml images/Dockerfile pki/make-pki.sh
 nodes/common/lib.sh nodes/common/hosts nodes/common/sshd_config nodes/common/frr-daemons
 nodes/common/ids.sh nodes/common/router-metrics.sh
 nodes/common/suricata/suricata.yaml nodes/common/suricata/local.rules
 nodes/isp/start.sh nodes/attacker/start.sh nodes/rogue/start.sh nodes/ws/start.sh
 nodes/remote/start.sh nodes/remote/ssh_config nodes/sw1/start.sh
 nodes/edge/start.sh nodes/edge/frr.conf nodes/edge/nft-hardened.nft nodes/edge/nft-baseline.nft
 nodes/core/start.sh nodes/core/frr.conf nodes/core/nft-hardened.nft nodes/core/nft-baseline.nft
 nodes/web/start.sh nodes/web/index.html nodes/web/host-fw.nft
 nodes/web/nginx-hardened.conf nodes/web/nginx-baseline.conf
 nodes/app/start.sh nodes/app/app.py nodes/app/host-fw.nft
 nodes/app/nginx-hardened.conf nodes/app/nginx-baseline.conf
 nodes/db/start.sh nodes/db/init.sql nodes/db/host-fw.nft nodes/db/backup.sh
 nodes/bastion/start.sh nodes/bastion/host-fw.nft nodes/bastion/jail.local
 nodes/bastion/sshd_config-hardened nodes/bastion/sshd_config-baseline nodes/bastion/f2b-metrics.sh
 nodes/mon/start.sh nodes/mon/prometheus.yml nodes/mon/alert.rules.yml nodes/mon/blackbox.yml
 nodes/mon/host-fw.nft nodes/mon/grafana/make-dashboard.py
 nodes/mon/grafana/provisioning/datasources/prometheus.yml
 nodes/mon/grafana/provisioning/dashboards/seclab.yml
 nodes/mon/grafana/dashboards/seclab-overview.json
 tests/run-tests.sh tests/collect.sh tests/wordlists/users.txt tests/wordlists/passwords.txt
 pki/out/edge/wg0.conf pki/out/remote/wg0.conf pki/out/web/web.crt"
missing=0
for f in $REQUIRED; do [ -f "$f" ] || { fail "missing: $f"; missing=1; }; done
[ "$missing" = 0 ] && pass "all $(echo $REQUIRED | wc -w) required files exist"

echo "2. shell scripts (bash -n = parse without running)"
for f in $(find nodes tests pki -name '*.sh' | sort); do check "$f" bash -n "$f"; done

echo "3. nftables rulesets (nft -c = check only, nothing is loaded)"
for f in nodes/*/*.nft; do check "$f" run seclab/router:1 "nft -c -f /repo/$f"; done

# A rule split over two lines must end the first line with "\". If the "\" is lost,
# BOTH halves are still valid rules, and the second half ("counter ... accept")
# would accept everything - so nft -c cannot catch it. This check can: after
# joining continued lines, every rule must end with a verdict.
for f in nodes/*/*.nft; do
  bad="$(sed -e ':a' -e '/\\$/N; s/\\\n//; ta' "$f" \
         | grep -E '^\s*(iifname|oifname|ip |tcp |udp |icmp |ct |meta |counter name)' \
         | grep -vE '(accept|drop|masquerade|dnat to [^#]*)\s*(#.*)?$')"
  if [ -n "$bad" ]; then fail "$f: rule without a verdict (lost \\ ?)"; echo "        $bad"
  else pass "$f: every rule ends with a verdict"; fi
done

echo "4. sshd configurations"
for f in nodes/common/sshd_config nodes/bastion/sshd_config-hardened \
         nodes/bastion/sshd_config-baseline; do
  check "$f" run seclab/server:1 "ssh-keygen -A >/dev/null; mkdir -p /run/sshd; sshd -t -f /repo/$f"
done

echo "5. nginx configurations (with the real certificates)"
for n in web app; do
  for p in hardened baseline; do
    check "nodes/$n/nginx-$p.conf" run seclab/server:1 "install -d /etc/nginx/tls &&
      cp /repo/pki/out/$n/*.crt /repo/pki/out/$n/*.key /etc/nginx/tls/ &&
      cp /repo/nodes/$n/nginx-$p.conf /etc/nginx/nginx.conf && nginx -t"
  done
done

echo "6. monitoring configurations"
check "nodes/mon/prometheus.yml" run seclab/server:1 \
  "cd /repo/nodes/mon && sed 's#/lab/node/#/repo/nodes/mon/#' prometheus.yml > /tmp/p.yml &&
   promtool check config /tmp/p.yml"
check "nodes/mon/alert.rules.yml" run seclab/server:1 \
  "promtool check rules /repo/nodes/mon/alert.rules.yml"
check "nodes/mon/blackbox.yml" run seclab/server:1 \
  "prometheus-blackbox-exporter --config.file=/repo/nodes/mon/blackbox.yml --config.check"
check "dashboard JSON parses" python3 -m json.tool nodes/mon/grafana/dashboards/seclab-overview.json

echo "7. IDS rules and configuration (suricata -T = test mode)"
check "nodes/common/suricata/*" run seclab/router:1 "mkdir -p /var/log/suricata &&
  suricata -T -c /repo/nodes/common/suricata/suricata.yaml \
              -S /repo/nodes/common/suricata/local.rules"

echo "8. fail2ban"
check "nodes/bastion/jail.local" run seclab/server:1 \
  "cp /repo/nodes/bastion/jail.local /etc/fail2ban/ && rm -f /etc/fail2ban/jail.d/defaults-debian.conf &&
   touch /var/log/auth.log && fail2ban-client -t"

echo "9. Python files"
for f in nodes/app/app.py nodes/mon/grafana/make-dashboard.py analysis/analyse.py; do
  [ -f "$f" ] || continue
  check "$f" run seclab/server:1 \
    "python3 -c 'import ast, sys; ast.parse(open(sys.argv[1]).read())' /repo/$f"
done

echo "10. YAML files (needs python3-yaml on the lab host: sudo apt install -y python3-yaml)"
for f in seclab.clab.yaml nodes/mon/grafana/provisioning/datasources/prometheus.yml \
         nodes/mon/grafana/provisioning/dashboards/seclab.yml; do
  check "$f" python3 -c 'import sys, yaml; yaml.safe_load(open(sys.argv[1]))' "$f"
done

echo
echo "pre-flight: $OK ok, $BAD failed"
[ "$BAD" -eq 0 ]
