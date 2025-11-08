#!/bin/bash
set -e

echo "[+] Initialisation du routeur..."

# Installation automatique des outils réseau
apt-get update -y
apt-get install -y iproute2 iptables net-tools curl >/dev/null 2>&1

# Appliquer le firewall si présent
if [ -f /router-config/firewall.sh ]; then
  bash /router-config/firewall.sh
  echo "[✓] Firewall appliqué automatiquement."
else
  echo "[!] /router-config/firewall.sh introuvable, aucun pare-feu appliqué."
fi

# Laisser le conteneur actif
tail -f /dev/null
