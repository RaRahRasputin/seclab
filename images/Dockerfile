# SecLab node images.
# ---------------------------------------------------------------- base ------
FROM ubuntu:24.04 AS base
ENV DEBIAN_FRONTEND=noninteractive
RUN apt-get update && apt-get install -y --no-install-recommends \
      tini iproute2 iputils-ping nftables openssh-server openssh-client \
      ca-certificates curl jq tcpdump procps less nano netcat-openbsd \
      prometheus-node-exporter openssl sudo rsyslog \
 && rm -rf /var/lib/apt/lists/* \
 && sed -i '/imklog/s/^/#/' /etc/rsyslog.conf

RUN useradd --create-home --shell /bin/bash labadmin \
 && usermod -p '*' labadmin \
 && echo 'labadmin ALL=(ALL) NOPASSWD: /usr/sbin/nft list ruleset, /usr/bin/tail' > /etc/sudoers.d/labadmin \
 && chmod 440 /etc/sudoers.d/labadmin \
 && mkdir -p /run/sshd /var/lib/node_exporter/textfile

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

