
# ---------------------------------------------------------------- base ------
FROM ubuntu:24.04 AS base
ENV DEBIAN_FRONTEND=noninteractive
RUN apt-get update && apt-get install -y --no-install-recommends \
      tini iproute2 iputils-ping nftables openssh-server openssh-client \
      ca-certificates curl jq tcpdump procps less nano netcat-openbsd \
      prometheus-node-exporter openssl sudo rsyslog \
 && rm -rf /var/lib/apt/lists/* \
 # rsyslog gives every node a normal /var/log/auth.log. The kernel-log module
 # is switched off because a container must not read the host's kernel log.
 && sed -i '/imklog/s/^/#/' /etc/rsyslog.conf
# One unprivileged administrator account, used for all SSH access.
# usermod -p '*' gives it a password field that no password can ever match,
# so the only way in is an SSH key. (A *locked* account, "!", would also be
# refused for key logins by sshd.)
RUN useradd --create-home --shell /bin/bash labadmin \
 && usermod -p '*' labadmin \
 && echo 'labadmin ALL=(ALL) NOPASSWD: /usr/sbin/nft list ruleset, /usr/bin/tail' \
      > /etc/sudoers.d/labadmin \
 && chmod 440 /etc/sudoers.d/labadmin \
 && mkdir -p /run/sshd /var/lib/node_exporter/textfile
# tini is a minimal init: it reaps zombie processes and forwards signals.
ENTRYPOINT ["/usr/bin/tini", "--"]
CMD ["sleep", "infinity"]

# -------------------------------------------------------------- router ------
FROM base AS router
RUN apt-get update && apt-get install -y --no-install-recommends \
      frr wireguard-tools wireguard-go suricata conntrack traceroute \
 && rm -rf /var/lib/apt/lists/*

# -------------------------------------------------------------- server ------
FROM base AS server
RUN apt-get update && apt-get install -y --no-install-recommends \
      nginx postgresql postgresql-client python3-flask python3-psycopg2 gunicorn \
      fail2ban python3-systemd prometheus prometheus-blackbox-exporter \
 && rm -rf /var/lib/apt/lists/*
# A second, deliberately weak account. It is only unlocked by the BASELINE
# profile, to give the brute-force test something to find.
RUN useradd --create-home --shell /bin/bash jsmith

# -------------------------------------------------------------- client ------
FROM base AS client
RUN apt-get update && apt-get install -y --no-install-recommends \
      wireguard-tools wireguard-go apache2-utils sshpass python3 traceroute dnsutils \
 && rm -rf /var/lib/apt/lists/*

# ------------------------------------------------------------ attacker ------
FROM base AS attacker
RUN apt-get update && apt-get install -y --no-install-recommends \
      nmap hydra nikto dirb postgresql-client sshpass apache2-utils python3 traceroute \
 && rm -rf /var/lib/apt/lists/*
