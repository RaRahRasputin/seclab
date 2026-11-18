#!/usr/bin/env bash
# Publishes fail2ban's ban counts for the sshd jail as Prometheus metrics
# (via node_exporter's textfile collector), refreshed every 10 seconds.
OUT=/var/lib/node_exporter/textfile
mkdir -p "$OUT"
while true; do
  status="$(fail2ban-client status sshd 2>/dev/null)"
  current="$(echo "$status" | awk -F'\t' '/Currently banned/ {print $2}')"
  total="$(echo "$status"   | awk -F'\t' '/Total banned/     {print $2}')"
  failed="$(echo "$status"  | awk -F'\t' '/Total failed/     {print $2}')"
  {
    echo '# HELP seclab_fail2ban_banned_current Addresses currently banned by the sshd jail.'
    echo '# TYPE seclab_fail2ban_banned_current gauge'
    echo "seclab_fail2ban_banned_current ${current:-0}"
    echo '# HELP seclab_fail2ban_banned_total Bans issued by the sshd jail since it started.'
    echo '# TYPE seclab_fail2ban_banned_total counter'
    echo "seclab_fail2ban_banned_total ${total:-0}"
    echo '# HELP seclab_fail2ban_failed_total Failed logins counted by the sshd jail since start.'
    echo '# TYPE seclab_fail2ban_failed_total counter'
    echo "seclab_fail2ban_failed_total ${failed:-0}"
  } > "$OUT/fail2ban.prom.tmp" && mv "$OUT/fail2ban.prom.tmp" "$OUT/fail2ban.prom"
  sleep 10
done
