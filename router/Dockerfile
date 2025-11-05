FROM ubuntu:24.04

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update && apt-get install -y \
    iproute2 iptables iputils-ping dnsutils curl net-tools nmap procps iptables-persistent \
  && apt-get clean && rm -rf /var/lib/apt/lists/*

COPY router-entrypoint.sh /usr/local/bin/router-entrypoint.sh
RUN chmod +x /usr/local/bin/router-entrypoint.sh

ENTRYPOINT ["/usr/local/bin/router-entrypoint.sh"]

