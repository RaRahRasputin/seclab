#!/usr/bin/env bash
# Start or stop the Suricata IDS sensor on a router.
#   ids.sh start <interface>      e.g. ids.sh start eth1
#   ids.sh stop
#   ids.sh status
#
# Flags used:
#   -c  configuration file (our own minimal one, see suricata/suricata.yaml)
#   -S  load ONLY this rules file (our own eight rules, nothing else)
#   --af-packet=<if>  capture live traffic from this interface
#   -k none  do not discard packets with "bad" checksums. Virtual ethernet
#            links leave checksums for hardware that does not exist to fill
#            in, so without this Suricata would ignore most of the traffic.
#   -D  run in the background as a daemon
#
# The running sensor is tracked through its PID file. (Do not look for it with
# "pgrep -x suricata": the process renames itself to "Suricata-Main".)
PIDFILE=/var/run/suricata.pid
running() { [ -f "$PIDFILE" ] && kill -0 "$(cat "$PIDFILE")" 2>/dev/null; }

case "${1:-}" in
  start)
    [ -n "${2:-}" ] || { echo "usage: ids.sh start <interface>"; exit 1; }
    running && { echo "suricata already running (pid $(cat $PIDFILE))"; exit 0; }
    rm -f "$PIDFILE"
    mkdir -p /var/log/suricata
    suricata -c /lab/common/suricata/suricata.yaml \
             -S /lab/common/suricata/local.rules \
             --af-packet="$2" -k none -D \
             >/var/log/suricata/startup.log 2>&1
    echo "$2" > /var/run/suricata.iface
    for _ in $(seq 1 50); do running && break; sleep 0.2; done
    if running; then
      echo "suricata started on $2 (pid $(cat $PIDFILE))"
    else
      echo "suricata FAILED to start:"; cat /var/log/suricata/startup.log; exit 1
    fi
    ;;
  stop)
    if running; then
      kill "$(cat "$PIDFILE")"
      for _ in $(seq 1 50); do running || break; sleep 0.2; done
    fi
    rm -f "$PIDFILE"
    echo "suricata stopped"
    ;;
  status)
    if running; then
      echo "running (pid $(cat $PIDFILE)) on $(cat /var/run/suricata.iface 2>/dev/null)"
    else
      echo "stopped"; exit 3
    fi
    ;;
  *) echo "usage: ids.sh start <interface> | stop | status"; exit 1 ;;
esac
