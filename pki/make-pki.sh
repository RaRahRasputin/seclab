#!/usr/bin/env bash
# Generates every secret the lab needs. Run it from the repository root with:
#   docker run --rm -v "$PWD/pki:/pki" seclab/router:1 bash /pki/make-pki.sh
# (It runs inside the seclab/router image, so the lab host itself needs
#  neither openssl nor the WireGuard tools installed.)
#
# Output layout - one folder per node, mounted read-only at /lab/pki in that
# node, so each node receives ONLY the secrets it needs:
#
#   pki/ca/        root CA private key + certificate   (stays on the lab host: the "offline CA")
#   pki/out/web/   web.crt web.key web-client.crt web-client.key root.crt admin_ed25519.pub
#   pki/out/app/   app.crt app.key root.crt db_password admin_ed25519.pub
#   pki/out/db/    db.crt db.key root.crt db_password admin_ed25519.pub
#   pki/out/edge/  wg0.conf root.crt admin_ed25519.pub
#   pki/out/remote/ wg0.conf root.crt admin_ed25519 (the administrator's PRIVATE key)
#   ...
set -euo pipefail
cd "$(dirname "$0")"

if [ -f ca/root.key ] && [ "${1:-}" != "--force" ]; then
  echo "PKI already exists (pki/ca/root.key). Re-run with --force to regenerate everything."
  exit 0
fi
rm -rf ca out
mkdir -p ca out
NODES="edge core web app db bastion mon ws remote attacker rogue"
for n in $NODES; do mkdir -p "out/$n"; done

# ----------------------------------------------------------------- root CA --
# EC P-256 key, self-signed, valid 5 years. basicConstraints CA:TRUE with
# pathlen:0 means: this certificate may sign end-entity certificates, but
# nothing it signs may itself act as a CA.
openssl ecparam -name prime256v1 -genkey -noout -out ca/root.key
openssl req -x509 -new -key ca/root.key -sha256 -days 1825 \
  -subj "/O=SecLab/CN=SecLab Root CA" \
  -addext "basicConstraints=critical,CA:TRUE,pathlen:0" \
  -addext "keyUsage=critical,keyCertSign,cRLSign" \
  -out ca/root.crt
chmod 600 ca/root.key

# issue <name> <CN> <serverAuth|clientAuth> <subjectAltName>
# Creates a key and a CSR, then signs the CSR with the root CA (valid 90 days).
issue() {
  local name="$1" cn="$2" eku="$3" san="$4"
  openssl ecparam -name prime256v1 -genkey -noout -out "ca/$name.key"
  openssl req -new -key "ca/$name.key" -subj "/O=SecLab/CN=$cn" -out "ca/$name.csr"
  printf '%s\n' \
    "basicConstraints=critical,CA:FALSE" \
    "keyUsage=critical,digitalSignature" \
    "extendedKeyUsage=$eku" \
    "subjectAltName=$san" > "ca/$name.ext"
  openssl x509 -req -in "ca/$name.csr" -CA ca/root.crt -CAkey ca/root.key \
    -CAcreateserial -sha256 -days 90 -extfile "ca/$name.ext" -out "ca/$name.crt" 2>/dev/null
  rm -f "ca/$name.csr" "ca/$name.ext"
}

#     file        common name        purpose     names/addresses the certificate is valid for
issue web         portal.seclab.test serverAuth \
                  "DNS:portal.seclab.test,IP:203.0.113.1,IP:10.10.30.10"
issue web-client  web.seclab.test    clientAuth  "DNS:web.seclab.test"
issue app         app.seclab.test    serverAuth  "DNS:app.seclab.test,IP:10.10.20.10"
issue db          db.seclab.test     serverAuth  "DNS:db.seclab.test,IP:10.10.20.20"

cp ca/web.crt ca/web.key ca/web-client.crt ca/web-client.key out/web/
cp ca/app.crt ca/app.key out/app/
cp ca/db.crt  ca/db.key  out/db/
for n in $NODES; do cp ca/root.crt "out/$n/root.crt"; done      # the public root goes everywhere
rm -f out/attacker/root.crt out/rogue/root.crt                  # ...except to the attackers

# ------------------------------------------------------- database password --
openssl rand -hex 24 > ca/db_password
cp ca/db_password out/app/db_password
cp ca/db_password out/db/db_password

# ------------------------------------------------------ administrator SSH key --
ssh-keygen -q -t ed25519 -N '' -C 'labadmin@seclab' -f ca/admin_ed25519
cp ca/admin_ed25519 out/remote/admin_ed25519                    # private key: admin laptop only
for n in edge core web app db bastion mon; do
  cp ca/admin_ed25519.pub "out/$n/admin_ed25519.pub"
done

# ------------------------------------------------------------- WireGuard keys --
umask 077
EDGE_PRIV=$(wg genkey);   EDGE_PUB=$(echo "$EDGE_PRIV"   | wg pubkey)
REMOTE_PRIV=$(wg genkey); REMOTE_PUB=$(echo "$REMOTE_PRIV" | wg pubkey)
PSK=$(wg genpsk)

cat > out/edge/wg0.conf <<EOF
# edge - WireGuard server side. Installed as /etc/wireguard/wg0.conf
[Interface]
Address    = 10.10.200.1/24
ListenPort = 51820
PrivateKey = $EDGE_PRIV

# Peer 1: the administrator's laptop ("remote")
[Peer]
PublicKey    = $REMOTE_PUB
PresharedKey = $PSK
AllowedIPs   = 10.10.200.2/32
EOF

cat > out/remote/wg0.conf <<EOF
# remote - WireGuard client side. Installed as /etc/wireguard/wg0.conf
[Interface]
Address    = 10.10.200.2/24
PrivateKey = $REMOTE_PRIV

[Peer]
PublicKey    = $EDGE_PUB
PresharedKey = $PSK
Endpoint     = 203.0.113.1:51820
# Split tunnel: only the management VLAN (and the tunnel network itself) is
# routed into the VPN. Everything else stays outside it.
AllowedIPs   = 10.10.99.0/24, 10.10.200.0/24
PersistentKeepalive = 25
EOF
umask 022

# Bind-mounted files keep their host ownership, so make public material
# world-readable and leave private material readable by root only.
chmod 644 out/*/*.crt out/*/*.pub
chmod 600 out/*/*.key out/*/wg0.conf out/*/db_password out/remote/admin_ed25519
echo "PKI generated:"
find out -type f | sort | sed 's/^/  /'
