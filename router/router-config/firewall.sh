#!/bin/bash
set -e

###
# Contexte interfaces (ATTENTION : ordre Docker)
# dmz_net               -> eth0 -> 10.77.20.254/24 (DMZ)
# internet_internal_net -> eth1 -> 10.77.30.254/24 (Internet "externe")
# lan_net               -> eth2 -> 10.77.10.254/24 (LAN interne)
#
# Réseaux:
# LAN                10.77.10.0/24
# DMZ                10.77.20.0/24
# Internet interne   10.77.30.0/24
###

echo "[*] Activation du routage IP"
sysctl -w net.ipv4.ip_forward=1 >/dev/null

echo "[*] Flush des anciennes règles"
iptables -F
iptables -t nat -F
iptables -X

echo "[*] Politiques par défaut strictes"
iptables -P INPUT DROP
iptables -P FORWARD DROP
iptables -P OUTPUT ACCEPT

echo "[*] Autoriser trafic établi/relatif"
iptables -A INPUT   -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT
iptables -A FORWARD -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT

###
# Règles autorisées (politique sécurité)
###

echo "[*] Autoriser le LAN -> DMZ (HTTP uniquement)"
iptables -A FORWARD \
  -i eth2 -o eth0 \
  -s 10.77.10.0/24 -d 10.77.20.0/24 \
  -p tcp --dport 80 \
  -m conntrack --ctstate NEW \
  -j ACCEPT

echo "[*] Autoriser le LAN -> Internet interne (HTTP uniquement)"
iptables -A FORWARD \
  -i eth2 -o eth1 \
  -s 10.77.10.0/24 -d 10.77.30.0/24 \
  -p tcp --dport 80 \
  -m conntrack --ctstate NEW \
  -j ACCEPT

echo "[*] Autoriser Internet interne -> DMZ (HTTP uniquement)"
iptables -A FORWARD \
  -i eth1 -o eth0 \
  -s 10.77.30.0/24 -d 10.77.20.0/24 \
  -p tcp --dport 80 \
  -m conntrack --ctstate NEW \
  -j ACCEPT

echo "[*] (Debug) Autoriser l ICMP (ping)"
iptables -A FORWARD -p icmp -j ACCEPT

###
# NAT
# On "masquerade" le LAN et la DMZ quand ils sortent vers l'Internet interne (eth1)
###
echo "[*] Mise en place du NAT/MASQUERADE"
iptables -t nat -A POSTROUTING -s 10.77.10.0/24 -o eth1 -j MASQUERADE
iptables -t nat -A POSTROUTING -s 10.77.20.0/24 -o eth1 -j MASQUERADE

echo "[*] État final des tables"
echo "=== FILTER ==="
iptables -L -v -n --line-numbers
echo
echo "=== NAT ==="
iptables -t nat -L -v -n --line-numbers
echo
echo "[*] Pare-feu appliqué."

########################################
# 7. Journalisation des paquets bloqués
########################################

# Loguer tout ce qui est bloqué par la politique FORWARD (DROP par défaut)
# avec une limitation pour éviter le spam (1 ligne/sec max)
iptables -A FORWARD -m limit --limit 1/second -j LOG --log-prefix "FW DROP: " --log-level 4

# Loguer aussi ce qui est bloqué en entrée directe sur le routeur
iptables -A INPUT -m limit --limit 1/second -j LOG --log-prefix "FW INPUT DROP: " --log-level 4
