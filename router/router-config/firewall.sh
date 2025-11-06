#!/bin/bash

sysctl -w net.ipv4.ip_forward=1

iptables -F
iptables -X
iptables -t nat -F
iptables -t nat -X

iptables -P INPUT ACCEPT
iptables -P OUTPUT ACCEPT
iptables -P FORWARD DROP

LAN="eth3"      # 10.10.0.254
DMZ="eth1"      # 10.20.0.254
WAN="eth0"      # 172.18.0.2
INT_INSIDE="eth2"  # 10.30.0.254

# 1) Autoriser trafic établi
iptables -A FORWARD -m state --state RELATED,ESTABLISHED -j ACCEPT

# 2) Bloquer DMZ → LAN (maintenant correct)
iptables -A FORWARD -i $DMZ -o $LAN -j DROP

# 3) Autoriser LAN → DMZ
iptables -A FORWARD -i $LAN -o $DMZ -j ACCEPT

# 4) LAN → Internet + DMZ interne
iptables -A FORWARD -i $LAN -o $WAN -j ACCEPT
iptables -A FORWARD -i $LAN -o $INT_INSIDE -j ACCEPT

# 5) DMZ → Internet (web)
iptables -A FORWARD -i $DMZ -o $WAN -p tcp -m multiport --dports 80,443 -j ACCEPT

# 6) WAN → DMZ (web public)
iptables -A FORWARD -i $WAN -o $DMZ -p tcp -m multiport --dports 80,443 -j ACCEPT

# NAT
iptables -t nat -A POSTROUTING -o $WAN -j MASQUERADE

echo "[+] Firewall appliqué (interfaces corrigées)."

