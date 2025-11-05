#!/usr/bin/env bash
set -euo pipefail

# Noms des conteneurs — adapte si nécessaire
PC_LAN="pc_lan"
PC_DMZ="pc_dmz"
PC_INT="pc_internet_inside"
ROUTER="routerfw"
WEB_DMZ_IP="10.77.20.20"
PC_DMZ_IP="10.77.20.10"
PC_LAN_IP="10.77.10.10"
PC_INT_IP="10.77.30.10"
DVWA_IP="10.77.30.20"
ROUTER_LAN_GW="10.77.10.254"
ROUTER_DMZ_GW="10.77.20.254"
ROUTER_INT_GW="10.77.30.254"

OUTDIR="./connectivity-report"
mkdir -p "$OUTDIR"

# util: run docker exec (no -it) and save output
dexec() {
  local ctr=$1; shift
  echo "=== [$ctr] $* ===" | tee -a "$OUTDIR/$ctr.exec.log"
  docker exec "$ctr" bash -lc "$*" 2>&1 | tee -a "$OUTDIR/$ctr.exec.log"
  echo "" >> "$OUTDIR/$ctr.exec.log"
}

# 0) Vérifier que les conteneurs existent
for c in $ROUTER $PC_LAN $PC_DMZ $PC_INT; do
  if ! docker ps --format '{{.Names}}' | grep -q "^${c}\$"; then
    echo "ERREUR: le conteneur $c n'est pas démarré. Lance: docker compose up -d --build"
    exit 2
  fi
done

# 1) Installer outils si manquant (idempotent, silencieux)
PKGS="iproute2 iputils-ping net-tools dnsutils curl wget nmap tcpdump traceroute netcat-openbsd python3"
for c in $PC_LAN $PC_DMZ $PC_INT $ROUTER; do
  echo ">>> Installing packages in $c (if missing)..."
  docker exec "$c" bash -lc "apt-get update -qq && DEBIAN_FRONTEND=noninteractive apt-get install -y -qq $PKGS || true" > "$OUTDIR"/install_"$c".log 2>&1 || true
done

# 2) Forcer les routes par défaut (exécuter en root)
echo ">>> Forcer les routes par défaut (root exec)..."
docker exec -u 0 "$PC_LAN" bash -lc "ip route del default || true; ip route add default via $ROUTER_LAN_GW || true; ip route" > "$OUTDIR/route_pc_lan.txt" 2>&1 || true
docker exec -u 0 "$PC_DMZ" bash -lc "ip route del default || true; ip route add default via $ROUTER_DMZ_GW || true; ip route" > "$OUTDIR/route_pc_dmz.txt" 2>&1 || true
docker exec -u 0 "$PC_INT" bash -lc "ip route del default || true; ip route add default via $ROUTER_INT_GW || true; ip route" > "$OUTDIR/route_pc_int.txt" 2>&1 || true
docker exec -u 0 "$ROUTER" bash -lc "ip -br addr; ip route" > "$OUTDIR/route_router.txt" 2>&1 || true

# 3) Vérif passerelles (ping .254)
echo ">>> Vérif passerelles (ping .254 depuis chaque poste) ..."
docker exec "$PC_LAN" bash -lc "ping -c 3 -W 1 $ROUTER_LAN_GW" > "$OUTDIR"/ping_gw_pc_lan.txt 2>&1 || true
docker exec "$PC_DMZ" bash -lc "ping -c 3 -W 1 $ROUTER_DMZ_GW" > "$OUTDIR"/ping_gw_pc_dmz.txt 2>&1 || true
docker exec "$PC_INT" bash -lc "ping -c 3 -W 1 $ROUTER_INT_GW" > "$OUTDIR"/ping_gw_pc_int.txt 2>&1 || true

# 4) Tests réels de connectivité (ICMP, HTTP, TCP)
echo ">>> Tests de connectivité réels (ICMP, HTTP, TCP)..."

# ICMP: LAN -> DMZ
docker exec "$PC_LAN" bash -lc "ping -c 4 -W 1 $PC_DMZ_IP" > "$OUTDIR"/ping_lan_dmz.txt 2>&1 || true

# ICMP: LAN -> DVWA
docker exec "$PC_LAN" bash -lc "ping -c 4 -W 1 $DVWA_IP" > "$OUTDIR"/ping_lan_dvwa.txt 2>&1 || true

# ICMP: INT -> LAN (doit être bloqué si firewall OK)
docker exec "$PC_INT" bash -lc "ping -c 4 -W 1 $PC_LAN_IP" > "$OUTDIR"/ping_int_lan.txt 2>&1 || true

# HTTP: LAN -> web_dmz
docker exec "$PC_LAN" bash -lc "curl -s -I --max-time 5 http://$WEB_DMZ_IP || true" > "$OUTDIR"/curl_lan_webdmz.txt 2>&1 || true

# HTTP: LAN -> dvwa
docker exec "$PC_LAN" bash -lc "curl -s -I --max-time 5 http://$DVWA_IP || true" > "$OUTDIR"/curl_lan_dvwa.txt 2>&1 || tru
