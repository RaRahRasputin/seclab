#!/usr/bin/env bash
# Runs in the background on edge and core. Every 10 seconds it turns two
# security data sources into Prometheus metrics by writing a text file that
# node_exporter's "textfile collector" publishes on port 9100:
#
#   seclab_nft_counter_packets{name="fwd_drop"}      from: nft -j list counters
#   seclab_suricata_alerts_total{signature="..."}    from: /var/log/suricata/eve.json
#
# This is how a firewall drop or an IDS alert becomes a line on a Grafana graph.
OUT=/var/lib/node_exporter/textfile
RULES=/lab/common/suricata/local.rules
EVE=/var/log/suricata/eve.json
mkdir -p "$OUT"

while true; do
  {
    echo '# HELP seclab_nft_counter_packets Packets matched by a named nftables counter.'
    echo '# TYPE seclab_nft_counter_packets counter'
    nft -j list counters 2>/dev/null \
      | jq -r '.nftables[] | select(.counter) | .counter
               | "seclab_nft_counter_packets{name=\"\(.name)\"} \(.packets)"'

    echo '# HELP seclab_suricata_alerts_total Suricata alerts seen so far, per rule.'
    echo '# TYPE seclab_suricata_alerts_total counter'
    # Start every known rule at 0 so its graph exists before the first alert,
    # then overwrite with the real counts from the event log.
    # (jq -R ... fromjson? reads line by line and skips a half-written last line.)
    {
      grep -o 'msg:"[^"]*"' "$RULES" | sed 's/^msg:"//; s/"$//' | sed 's/^/0\t/'
      [ -s "$EVE" ] && jq -rR 'fromjson? | select(.event_type=="alert") | .alert.signature' "$EVE" \
        | sort | uniq -c | sed 's/^ *\([0-9]*\) /\1\t/'
    } | awk -F'\t' '{ n[$2] = $1 }
          END { for (s in n)
                  printf "seclab_suricata_alerts_total{signature=\"%s\"} %s\n", s, n[s] }' \
      | sort
  } > "$OUT/seclab.prom.tmp" && mv "$OUT/seclab.prom.tmp" "$OUT/seclab.prom"
  sleep 10
done
