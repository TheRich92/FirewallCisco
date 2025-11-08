#!/bin/bash
set -euo pipefail

echo "[+] Application du pare-feu et du routage..."
sysctl -w net.ipv4.ip_forward=1 >/dev/null

normalize_if(){ sed 's/@.*$//' <<<"$1"; }

LAN_IF=$(normalize_if "$(ip -br addr | awk '/10\.10\.0\.254\/24/ {print $1}')")
DMZ_IF=$(normalize_if "$(ip -br addr | awk '/10\.20\.0\.254\/24/ {print $1}')")
INT_IF=$(normalize_if "$(ip -br addr | awk '/10\.30\.0\.254\/24/ {print $1}')")
WAN_IF=$(normalize_if "$(ip -br addr | awk '/^.* 172\./ {print $1; exit}')")

[[ -z "$LAN_IF" || -z "$DMZ_IF" || -z "$INT_IF" || -z "$WAN_IF" ]] && { echo "[!] IF detect fail"; ip -br addr; exit 1; }
echo "[i] IFaces: LAN=$LAN_IF DMZ=$DMZ_IF INT=$INT_IF WAN=$WAN_IF"

WAN_IP=$(ip -4 addr show dev "$WAN_IF" | awk '/inet /{print $2}' | cut -d/ -f1)
WAN_GW=${WAN_IP:+$(awk -F. '{printf "%s.%s.%s.1\n",$1,$2,$3}' <<<"$WAN_IP")}
ip route replace default via "${WAN_GW:-172.18.0.1}" dev "$WAN_IF" || true

iptables -F; iptables -X
iptables -t nat -F; iptables -t nat -X
iptables -t mangle -F; iptables -t mangle -X

iptables -P INPUT ACCEPT
iptables -P OUTPUT ACCEPT
iptables -P FORWARD DROP

# Connexions établies/relatives
iptables -A FORWARD -m conntrack --ctstate RELATED,ESTABLISHED -j ACCEPT

# ====================== Filtrage inter-zones ======================
# 🔒 DMZ -> LAN : bloquer explicitement
# TCP : renvoyer un RST (échec immédiat pour nc/HTTP)
iptables -A FORWARD -s 10.20.0.0/24 -d 10.10.0.0/24 -p tcp -m conntrack --ctstate NEW -j REJECT --reject-with tcp-reset
# Autres protocoles : rejet standard
iptables -A FORWARD -s 10.20.0.0/24 -d 10.10.0.0/24 -m conntrack --ctstate NEW -j REJECT

# LAN -> DMZ : autorisé
iptables -A FORWARD -i "$LAN_IF" -o "$DMZ_IF" -j ACCEPT
# Filet de sécurité DMZ -> LAN (au cas où)
iptables -A FORWARD -i "$DMZ_IF" -o "$LAN_IF" -j DROP

# LAN -> INT + WAN : autorisés
iptables -A FORWARD -i "$LAN_IF" -o "$INT_IF" -j ACCEPT
iptables -A FORWARD -i "$LAN_IF" -o "$WAN_IF" -j ACCEPT

# DMZ -> WAN : web uniquement (80/443)
iptables -A FORWARD -i "$DMZ_IF" -o "$WAN_IF" -p tcp -m multiport --dports 80,443 -j ACCEPT

# WAN -> DMZ/INT : publication web
iptables -A FORWARD -i "$WAN_IF" -o "$DMZ_IF" -p tcp -m multiport --dports 80,443 -j ACCEPT
iptables -A FORWARD -i "$WAN_IF" -o "$INT_IF" -p tcp -m multiport --dports 80,443 -j ACCEPT
iptables -A FORWARD -i "$INT_IF" -o "$WAN_IF" -p tcp -m multiport --dports 80,443 -j ACCEPT

# Autoriser explicitement les flux destinés aux IP publiées (DNAT), peu importe l'entrée
iptables -A FORWARD -p tcp -d 10.20.0.20 --dport 80 -j ACCEPT   # web_dmz
iptables -A FORWARD -p tcp -d 10.30.0.20 --dport 80 -j ACCEPT   # dvwa

# (Optionnel) ICMP
# iptables -A FORWARD -p icmp -j ACCEPT

# ====================== NAT sortant ======================
iptables -t nat -A POSTROUTING -o "$WAN_IF" -j MASQUERADE
iptables -t nat -A POSTROUTING -s 10.10.0.0/24 -d 10.20.0.0/24 -o "$DMZ_IF" -j MASQUERADE   # LAN->DMZ
iptables -t nat -A POSTROUTING -s 10.10.0.0/24 -d 10.30.0.0/24 -o "$INT_IF" -j MASQUERADE   # LAN->INT

# ====================== DNAT publication ======================
iptables -t nat -A PREROUTING -p tcp --dport 80 -j DNAT --to-destination 10.20.0.20:80
iptables -t nat -A PREROUTING -p tcp --dport 81 -j DNAT --to-destination 10.30.0.20:80
iptables -t nat -A POSTROUTING -p tcp -d 10.20.0.20 --dport 80 -j MASQUERADE
iptables -t nat -A POSTROUTING -p tcp -d 10.30.0.20 --dport 80 -j MASQUERADE

echo "[✓] Pare-feu configuré."
iptables -S FORWARD
iptables -t nat -S
