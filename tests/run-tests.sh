#!/usr/bin/env bash
# SecLab test suite (Blueprint Part F.2). Run on the lab host, from the repository root:
#     bash tests/run-tests.sh
#
# Three kinds of test:
#   func    something that must WORK in every profile        -> OK / BROKEN
#   attack  something an attacker tries; the command exits 0
#           when the ATTACK SUCCEEDS                           -> EXPOSED / PROTECTED
#   ctrl    a security control that must be demonstrably
#           active (hardened profile only)                     -> OK / BROKEN
#
# Expected result:  hardened = every attack PROTECTED
#                   baseline = attacks EXPOSED (that is the point of the baseline)
# Every line prints PASS when the outcome matches the expectation for the
# active profile, FAIL otherwise. The script exits 0 only if nothing failed.
# Output: a table on screen plus evidence/tests-<profile>-<timestamp>.csv
set -u
cd "$(dirname "$0")/.."

PROFILE="$(cat state/profile 2>/dev/null || echo hardened)"
STAMP="$(date +%Y%m%d-%H%M%S)"
GRAFANA_PASSWORD="${GRAFANA_PASSWORD:-ChangeMe-SecLab-1}"   # as set in seclab.clab.yaml
mkdir -p evidence
CSV="evidence/tests-$PROFILE-$STAMP.csv"
echo "id,type,description,outcome,expected,verdict" > "$CSV"

# X <node> <command>: run a command quietly inside a node, giving up after 200 s
X() { local node="$1"; shift; docker exec "$node" timeout 200 bash -c "$*" >/dev/null 2>&1; }
N_PASS=0; N_FAIL=0

record() {  # id type description outcome expected
  local verdict=PASS
  [ "$4" = "$5" ] || verdict=FAIL
  if [ "$verdict" = PASS ]; then N_PASS=$((N_PASS+1)); else N_FAIL=$((N_FAIL+1)); fi
  printf '%-4s %-6s %-62s %-10s %s\n' "$1" "$2" "$3" "$4" "$verdict"
  echo "$1,$2,\"$3\",$4,$5,$verdict" >> "$CSV"
}

func() {    # id description node command
  local out=BROKEN; X "$3" "$4" && out=OK
  record "$1" func "$2" "$out" OK
}
ctrl() {    # id description node command      (hardened profile only)
  [ "$PROFILE" = hardened ] || return 0
  local out=BROKEN; X "$3" "$4" && out=OK
  record "$1" ctrl "$2" "$out" OK
}
attack() {  # id description node command      (exit 0 = attack succeeded)
  local out=PROTECTED expected=PROTECTED
  X "$3" "$4" && out=EXPOSED
  [ "$PROFILE" = baseline ] && expected=EXPOSED
  record "$1" attack "$2" "$out" "$expected"
}
# nft_count <node> <counter>: current packet count of a named nftables counter
nft_count() {
  docker exec "$1" nft -j list counter inet filter "$2" \
    | jq '.nftables[] | select(.counter) | .counter.packets'
}
# alerts <node> <text>: how many Suricata alerts containing this text a sensor has logged
alerts() {
  docker exec "$1" bash -c "jq -rR 'fromjson? | select(.event_type==\"alert\")
      | .alert.signature' /var/log/suricata/eve.json 2>/dev/null | grep -c '$2'"
}

PORTAL=http://portal.seclab.test
[ "$PROFILE" = hardened ] && PORTAL=https://portal.seclab.test
echo "=== SecLab test suite - profile: $PROFILE - $(date) ==="
printf '%-4s %-6s %-62s %-10s %s\n' ID TYPE DESCRIPTION OUTCOME VERDICT

# ------------------------------------------------------------------ routing --
func F01 "OSPF adjacency edge<->core is Full" edge \
  "vtysh -c 'show ip ospf neighbor' | grep -q Full"
func F02 "core learned the default route through OSPF" core \
  "ip route show default | grep -q 'via 10.10.0.1.*proto ospf'"
func F03 "edge learned the three VLAN subnets through OSPF" edge \
  "[ \$(ip route show proto ospf | grep -c -E '10\.10\.(10|20|99)\.0/24') -eq 3 ]"
func F04 "workstation reaches its default gateway" ws1 \
  "ping -c1 -W2 10.10.10.1"
func F05 "workstation reaches a site on the internet" ws1 \
  "curl -s -m5 http://203.0.113.50/ | grep -q hello"
func F06 "NAT: internet site sees the edge's public address" remote \
  "tail -3 /var/log/www.log | grep -q '^203.0.113.1 '"

# Addition in the continuation guide (not in the blueprint's 48): Layer-2 isolation.
# rogue (VLAN 10) gives itself an address in the servers subnet and tries to reach
# db directly. With working VLANs its ARP request never reaches VLAN 20, so this
# fails - and "fails" is what the test requires (note the "!").
func V01 "VLAN isolation: rogue cannot reach VLAN 20 at Layer 2" rogue \
  "ip addr add 10.10.20.66/24 dev eth1; ! ping -c2 -W1 10.10.20.20; rc=\$?; \
   ip addr del 10.10.20.66/24 dev eth1; exit \$rc"

# ------------------------------------------------------------- the service --
func F07 "customer on the internet gets the portal page" remote \
  "curl -s -m8 $PORTAL/ | grep -q 'SecLab Client Portal'"
func F08 "portal -> API -> database chain returns data" remote \
  "curl -s -m8 $PORTAL/api/summary | grep -q APAC"
func F09 "staff workstation reaches the portal" ws1 \
  "curl -s -m8 $PORTAL/api/health | grep -q ok"

# ------------------------------------------------------- administration ----
X remote "wg show wg0 >/dev/null 2>&1 || wg-quick up wg0"; sleep 2
func F10 "VPN tunnel has completed a handshake" remote \
  "wg show wg0 latest-handshakes | awk '{exit !(\$2>0)}'"
func F11 "admin reaches the bastion through the VPN (key)" remote \
  "ssh -o ConnectTimeout=6 bastion true"
func F12 "admin reaches the database host via ProxyJump" remote \
  "ssh -o ConnectTimeout=8 db true"
func F13 "all 7 Prometheus scrape targets are up" mon \
  "[ \$(curl -sG localhost:9090/api/v1/query \
        --data-urlencode 'query=count(up{job=\"node\"}==1)' \
        | jq -r '.data.result[0].value[1]') = 7 ]"

# Addition in the continuation guide: Grafana is provisioned (data source + dashboard).
func G01 "Grafana has the Prometheus source and the dashboard" mon \
  "curl -s -m5 -u admin:$GRAFANA_PASSWORD localhost:3000/api/datasources/uid/prometheus \
     | grep -q '\"uid\":\"prometheus\"' && \
   curl -s -m5 -u admin:$GRAFANA_PASSWORD 'localhost:3000/api/search?query=SecLab' \
     | grep -q seclab-overview"

R6_BEFORE=$(alerts core 'R6 Users-zone')   # taken now, before the rogue device acts

# ------------------------------------------------- attacks from the internet --
attack A01 "internet: SSH service reachable (203.0.113.1:2222)" attacker \
  "nc -z -w2 203.0.113.1 2222"
attack A02 "internet: database port reachable (203.0.113.1:5432)" attacker \
  "nc -z -w2 203.0.113.1 5432"
attack A03 "internet: routed straight to internal DB via edge" attacker \
  "ip route replace 10.10.0.0/16 via 203.0.113.1; nc -z -w2 10.10.20.20 5432; rc=\$?; \
   ip route del 10.10.0.0/16; exit \$rc"
attack A04 "internet: hydra guesses an SSH password" attacker \
  "rm -f /tmp/hydra.out; timeout 150 hydra -L /lab/wordlists/users.txt \
     -P /lab/wordlists/passwords.txt -s 2222 -t 4 -f -o /tmp/hydra.out ssh://203.0.113.1; \
   grep -q 'password:' /tmp/hydra.out"
attack A05 "internet: portal answers over clear-text HTTP" attacker \
  "curl -s -m5 http://203.0.113.1/api/health | grep -q ok"
attack A06 "internet: directory listing reveals files" attacker \
  "curl -sk -L -m5 http://203.0.113.1/files/ | grep -q staff-export"
attack A07 "internet: web server discloses its version" attacker \
  "curl -skI -L -m5 http://203.0.113.1/ | grep -qi '^server: nginx/'"

# ------------------------------------------- attacks from inside (VLAN 10) --
attack A08 "rogue device: database port reachable" rogue \
  "nc -z -w2 10.10.20.20 5432"
attack A09 "rogue device: reads customer table (weak password)" rogue \
  "PGPASSWORD=portal123 PGCONNECT_TIMEOUT=3 psql -h 10.10.20.20 -U portal -d portal \
     -tAc 'select count(*) from customers' | grep -q 500"
attack A10 "rogue device: calls the application API directly" rogue \
  "curl -s -m3 http://10.10.20.10:8000/api/customers | grep -q email || \
   curl -sk -m3 https://10.10.20.10:8443/api/customers | grep -q email"
attack A11 "rogue device: bastion SSH port reachable" rogue \
  "nc -z -w2 10.10.99.10 22"
attack A12 "rogue device: router management (SSH) reachable" rogue \
  "nc -z -w2 10.10.10.1 22"

# ----------------------------- attacks assuming a server is already compromised --
attack A13 "compromised web server: outbound connection (C2 path)" web \
  "curl -s -m3 http://203.0.113.50/ | grep -q hello"
attack A14 "compromised web server: database port reachable" web \
  "nc -z -w2 10.10.20.20 5432"
attack A15 "compromised app server: reaches the internet" app \
  "curl -s -m3 http://203.0.113.50/ | grep -q hello"
attack A16 "API answers a caller with no client certificate" web \
  "curl -s -m3 http://10.10.20.10:8000/api/health | grep -q ok || \
   curl -s -m3 --cacert /lab/pki/root.crt https://app.seclab.test:8443/api/health \
     | grep -q ok"

# ------------------------------------------------ attacks on administration --
attack A17 "bastion accepts a password login" remote \
  "sshpass -p Summer2025 ssh -o ConnectTimeout=6 -o PubkeyAuthentication=no \
     -o PreferredAuthentications=password jsmith@10.10.99.10 true"
attack A18 "bastion relays to an arbitrary internal port" remote \
  "ssh -o ConnectTimeout=6 -W 10.10.20.20:5432 bastion </dev/null"

# ---------------------------------------------- on-path eavesdropping test --
# Capture the web->app traffic on the transit link while a customer fetches
# records, then look for readable e-mail addresses in the capture.
docker exec -d edge bash -c "timeout 6 tcpdump -i eth2 -A -s0 \
  'tcp port 8000 or tcp port 8443' > /tmp/sniff.txt 2>/dev/null"
sleep 1.5
X remote "curl -s -m5 '$PORTAL/api/customers?region=APAC'"
sleep 5.5
attack A19 "on-path capture shows customer data in clear text" edge \
  "grep -q 'example.test' /tmp/sniff.txt"

# --------------------------------------- controls (hardened profile only) ----
ctrl C01 "portal certificate chains to the lab root CA" remote \
  "echo | openssl s_client -connect portal.seclab.test:443 -servername portal.seclab.test \
     -CAfile /lab/pki/root.crt 2>/dev/null | grep -q 'Verify return code: 0'"
ctrl C02 "HTTP is redirected to HTTPS (301)" remote \
  "[ \$(curl -s -m5 -o /dev/null -w '%{http_code}' http://portal.seclab.test/) = 301 ]"
ctrl C03 "TLS 1.1 handshake is refused" remote \
  "! (echo | openssl s_client -connect portal.seclab.test:443 -tls1_1 \
       -cipher 'DEFAULT@SECLEVEL=0' 2>/dev/null | grep -q 'Cipher is [A-Z]')"
ctrl C04 "HSTS and anti-sniffing headers are sent" remote \
  "curl -sI -m5 https://portal.seclab.test/ | tr -d '\r' \
     | grep -ci -E '^(strict-transport-security|x-content-type-options|x-frame-options):' \
     | grep -q 3"
ctrl C05 "API request was authenticated with a client cert" app \
  "tail -5 /var/log/nginx/access.log | grep -q 'client_cert=SUCCESS cn=\"CN=web.seclab.test'"
ctrl C06 "database session is encrypted (TLS 1.3)" db \
  "tail -20 /var/log/postgresql/postgresql-16-main.log | grep -q 'SSL enabled (protocol=TLSv1.3'"
ctrl C07 "OSPF adjacency uses MD5 authentication" edge \
  "vtysh -c 'show ip ospf interface eth2' | grep -q 'Cryptographic authentication enabled'"

if [ "$PROFILE" = hardened ]; then
  # anti-spoofing: rogue borrows the application server's address and sends a SYN
  before=$(nft_count core spoof_drop)
  X rogue "ip addr add 10.10.20.10/32 dev lo; nc -z -w1 -s 10.10.20.10 10.10.30.10 80; \
           ip addr del 10.10.20.10/32 dev lo"
  after=$(nft_count core spoof_drop)
  out=BROKEN; [ "${after:-0}" -gt "${before:-0}" ] && out=OK
  record C08 ctrl "forged source address is dropped and counted (core)" "$out" OK
fi

# rate limiting: 800 API requests, 40 at a time, from one address
ctrl C09 "rate limit answers a request flood with 503" remote \
  "ab -q -n 800 -c 40 https://portal.seclab.test/api/health 2>/dev/null \
     | awk '/Non-2xx responses/ {n=\$3} END {exit !(n>0)}'"

if [ "$PROFILE" = hardened ]; then
  # fail2ban: four refused logins from the VPN address, then expect a ban.
  # (timeout 6: the ban can land in the middle of the fourth attempt and leave it hanging)
  for _ in 1 2 3 4; do
    X remote "timeout 6 ssh -o ConnectTimeout=4 -o PubkeyAuthentication=no \
      -o PreferredAuthentications=password -o BatchMode=yes nobody@10.10.99.10 true"
  done
  sleep 4
  ctrl C10 "fail2ban banned the address after repeated failures" bastion \
    "fail2ban-client status sshd | grep -q '10.10.200.2'"
  ctrl C11 "banned address can no longer open SSH" remote \
    "! nc -z -w2 10.10.99.10 22"
  docker exec bastion fail2ban-client set sshd unbanip 10.10.200.2 >/dev/null 2>&1
fi

# ------------------------------------------------------------- detection ----
b=$(alerts edge 'R1 TCP port scan')
X attacker "nmap -n -Pn -sS -T4 -p 1-1000 203.0.113.1"
sleep 3; a=$(alerts edge 'R1 TCP port scan')
out=BROKEN; [ "${a:-0}" -gt "${b:-0}" ] && out=OK
record D01 func "IDS (edge) alerts on an external port scan" "$out" OK

# (rule R6 alerts at most once per 30 s per source, so compare with the count
#  taken at the start of the run rather than a few seconds ago)
X rogue "nmap -n -Pn -sS -T4 -p 22,80,443,5432,8443 10.10.20.10 10.10.20.20 10.10.99.10"
sleep 3; a=$(alerts core 'R6 Users-zone')
out=BROKEN; [ "${a:-0}" -gt "${R6_BEFORE:-0}" ] && out=OK
record D02 func "IDS (core) alerts on lateral movement from VLAN 10" "$out" OK

b=$(alerts edge 'R3 Nikto')
X attacker "timeout 40 nikto -h http://203.0.113.1 -maxtime 20s -nointeractive"
sleep 3; a=$(alerts edge 'R3 Nikto')
out=BROKEN; [ "${a:-0}" -gt "${b:-0}" ] && out=OK
record D03 func "IDS (edge) recognises the Nikto web scanner" "$out" OK

if [ "$PROFILE" = hardened ]; then
  drops=$(nft_count edge in_drop)
  out=BROKEN; [ "${drops:-0}" -gt 100 ] && out=OK
  record D04 ctrl "edge firewall counted the scan as dropped packets" "$out" OK
fi

sleep 25   # give Prometheus two scrape cycles to pick up the new alert counts
func D05 "Prometheus alert IntrusionDetected is firing" mon \
  "curl -s localhost:9090/api/v1/alerts | jq -e '[.data.alerts[]
     | select(.labels.alertname==\"IntrusionDetected\" and .state==\"firing\")] | length>0'"

echo
echo "Profile $PROFILE: $N_PASS matched expectation, $N_FAIL did not.   Evidence: $CSV"
[ "$N_FAIL" -eq 0 ]
