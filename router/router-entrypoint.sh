#!/bin/bash
set -e

# Enable IP forwarding (also set as sysctl in compose)
sysctl -w net.ipv4.ip_forward=1

iptables -F; iptables -t nat -F; iptables -X
iptables -P FORWARD DROP
iptables -A FORWARD -m conntrack --ctstate RELATED,ESTABLISHED -j ACCEPT

iptables -A FORWARD -i eth0 -o eth1 -s 10.77.10.0/24 -d 10.77.20.0/24 -j ACCEPT
iptables -A FORWARD -i eth0 -o eth2 -s 10.77.10.0/24 -d 10.77.30.0/24 -j ACCEPT
iptables -A FORWARD -i eth1 -o eth2 -s 10.77.20.0/24 -d 10.77.30.0/24 -j ACCEPT

iptables -t nat -A POSTROUTING -s 10.77.10.0/24 -o eth2 -j MASQUERADE
iptables -t nat -A POSTROUTING -s 10.77.20.0/24 -o eth2 -j MASQUERADE

# If you want to allow access from Internet-Internal to the real host network,
# you may need additional NAT/forwarding rules here.

echo "RouterFW configured. ip_forward=$(sysctl -n net.ipv4.ip_forward)"
# keep container running and provide a shell
exec /bin/bash -l
