#!/usr/bin/env python3
"""Writes the Grafana dashboard file dashboards/seclab-overview.json.

Run it once, from the repository root, on the lab host:
    python3 nodes/mon/grafana/make-dashboard.py

Why a script instead of a hand-written JSON file: a Grafana dashboard is about
950 lines of JSON, almost all of it repeated settings. The part that matters is
the list of 14 panels below - one line of title, query and unit each.
Grafana reads the generated file at start-up (see provisioning/dashboards/seclab.yml).
"""
import json
from pathlib import Path

DS = {"type": "prometheus", "uid": "prometheus"}   # matches provisioning/datasources/


def stat(pid, x, title, expr, desc="", steps=(("green", None),), unit="none",
         decimals=None, mappings=None):
    """A single big number with a coloured background (top row of the dashboard)."""
    defaults = {
        "unit": unit,
        "color": {"mode": "thresholds"},
        "thresholds": {"mode": "absolute",
                       "steps": [{"color": c, "value": v} for c, v in steps]},
        "mappings": mappings or [],
    }
    if decimals is not None:
        defaults["decimals"] = decimals
    return {
        "id": pid, "type": "stat", "title": title, "description": desc,
        "datasource": DS, "gridPos": {"x": x, "y": 0, "w": 4, "h": 4},
        "targets": [{"datasource": DS, "expr": expr, "legendFormat": "__auto",
                     "refId": "A", "range": False, "instant": True}],
        "fieldConfig": {"defaults": defaults, "overrides": []},
        "options": {
            "reduceOptions": {"calcs": ["lastNotNull"], "fields": "", "values": False},
            "colorMode": "background", "graphMode": "none",
            "textMode": "auto", "justifyMode": "center",
        },
    }


def graph(pid, x, y, title, queries, unit, desc="", style="line"):
    """A graph. queries = list of (PromQL expression, legend text).
    style: "line", "stacked" (lines stacked on top of each other) or "bars" (stacked bars)."""
    custom = {"drawStyle": "bars" if style == "bars" else "line", "lineWidth": 2,
              "fillOpacity": 40 if style == "bars" else 10,
              "showPoints": "never", "spanNulls": True}
    if style != "line":
        custom["stacking"] = {"mode": "normal", "group": "A"}
    targets = [{"datasource": DS, "expr": e, "legendFormat": legend,
                "refId": chr(65 + i), "range": True, "instant": False}
               for i, (e, legend) in enumerate(queries)]
    return {
        "id": pid, "type": "timeseries", "title": title, "description": desc,
        "datasource": DS, "gridPos": {"x": x, "y": y, "w": 12, "h": 8},
        "targets": targets,
        "fieldConfig": {
            "defaults": {
                "unit": unit, "min": 0, "custom": custom,
                "color": {"mode": "palette-classic"},
            },
            "overrides": [],
        },
        "options": {
            "legend": {"displayMode": "table", "placement": "bottom",
                       "calcs": ["lastNotNull", "max"]},
            "tooltip": {"mode": "multi", "sort": "desc"},
        },
    }


DROPS = 'seclab_nft_counter_packets{name=~"fwd_drop|in_drop|spoof_drop"}'
ACCEPTS = 'seclab_nft_counter_packets{name=~"fwd_.*", name!="fwd_drop"}'
RX = 'node_network_receive_bytes_total{job="node", device=~"eth.*|wg0"}'
IDLE = 'node_cpu_seconds_total{node="mon", mode="idle"}'

panels = [
    # ---- top row: six numbers ---------------------------------------------
    stat(1, 0, "Nodes answering", 'count(up{job="node"} == 1)',
         "Scrape targets that are up. Expected: 7.",
         steps=(("red", None), ("orange", 5), ("green", 7))),
    stat(2, 4, "Public portal (HTTPS probe)", 'probe_success{job="portal_probe"}',
         "blackbox_exporter fetches https://portal.seclab.test/api/health"
         " through core and edge every 10 s.",
         steps=(("red", None), ("green", 1)),
         mappings=[{"type": "value",
                    "options": {"0": {"text": "DOWN"}, "1": {"text": "UP"}}}]),
    stat(3, 8, "Portal certificate: days left",
         '(probe_ssl_earliest_cert_expiry{job="portal_probe"} - time()) / 86400',
         steps=(("red", None), ("orange", 14), ("green", 30)), decimals=0),
    stat(4, 12, "Firewall drops per second", f"sum(rate({DROPS}[1m]))",
         "Packets refused by the edge and core firewalls"
         " (forward, input and anti-spoofing counters).",
         steps=(("green", None), ("orange", 5), ("red", 50)), unit="pps", decimals=1),
    stat(5, 16, "IDS alerts, last 5 min", "sum(increase(seclab_suricata_alerts_total[5m]))",
         "Suricata alerts from both sensors.",
         steps=(("green", None), ("orange", 1)), decimals=0),
    stat(6, 20, "Addresses banned by fail2ban", "seclab_fail2ban_banned_current",
         "Current bans in the bastion's sshd jail.",
         steps=(("green", None), ("red", 1)), decimals=0),

    # ---- graphs, two per row ------------------------------------------------
    graph(7, 0, 4, "Firewall: packets dropped per second",
          [('sum by (node, name) (rate(seclab_nft_counter_packets{name=~".*drop"}[30s]))',
            "{{node}} {{name}}")], "pps",
          "Named nftables counters, read every 10 s by router-metrics.sh."
          " A port scan shows up here as a spike in edge in_drop."),
    graph(8, 12, 4, "IDS: alerts per minute, by rule",
          [("sum by (node, signature) (increase(seclab_suricata_alerts_total[1m]))",
            "{{node}}: {{signature}}")], "short",
          "Suricata alerts per rule. R1 port scan, R2 SSH burst, R3 Nikto,"
          " R6 lateral movement...", style="bars"),
    graph(9, 0, 12, "Firewall: packets accepted per second, by rule",
          [(f"sum by (node, name) (rate({ACCEPTS}[30s]))", "{{node}} {{name}}")], "pps",
          "Counters attached to the allow rules: customers to the web server,"
          " web to the API, VPN to the bastion, management traffic."),
    graph(10, 12, 12, "Portal probe: time per phase",
          [('probe_http_duration_seconds{job="portal_probe"}', "{{phase}}")], "s",
          "Where the time of one HTTPS request goes: TCP connect, TLS handshake,"
          " server processing, transfer.", style="stacked"),
    graph(11, 0, 20, "Network traffic received per node",
          [(f"sum by (node) (rate({RX}[30s])) * 8", "{{node}}")], "bps",
          "Per-node figures are real: each container has its own network stack."),
    graph(12, 12, 20, "SSH on the bastion: failed logins and bans",
          [("increase(seclab_fail2ban_failed_total[1m])", "failed logins per minute"),
           ("seclab_fail2ban_banned_current", "addresses currently banned")], "short",
          "fail2ban's sshd jail."),
    graph(13, 0, 28, "Prometheus alerts firing",
          [('count by (alertname) (ALERTS{alertstate="firing"})', "{{alertname}}")], "short",
          "Alert rules from alert.rules.yml that are currently true.", style="bars"),
    graph(14, 12, 28, "Lab host CPU busy",
          [(f"100 * (1 - avg(rate({IDLE}[30s])))", "all cores, percent busy")], "percent",
          "CPU of the whole lab host. Containers share one kernel, so node_exporter"
          " reports the same CPU figures from every node; per-container CPU is"
          " measured with 'docker stats' in the benchmark instead."),
]

dashboard = {
    "uid": "seclab-overview",
    "title": "SecLab - security overview",
    "tags": ["seclab"],
    "timezone": "browser",
    "schemaVersion": 39,
    "version": 1,
    "editable": True,
    "refresh": "5s",
    "time": {"from": "now-15m", "to": "now"},
    "timepicker": {"refresh_intervals": ["5s", "10s", "30s", "1m"]},
    "annotations": {"list": []},
    "templating": {"list": []},
    "links": [],
    "panels": panels,
}

out = Path(__file__).resolve().parent / "dashboards" / "seclab-overview.json"
out.parent.mkdir(exist_ok=True)
out.write_text(json.dumps(dashboard, indent=1) + "\n")
print(f"written: {out}  ({len(panels)} panels)")
