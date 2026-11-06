#!/bin/bash
# ============================================================
# CVE-2026-63686 — Target VM Setup Script
# ============================================================
# Works in two modes:
#   1. Vagrant provisioner  — networking handled by Vagrant,
#      vhost.conf already at /tmp/vhost.conf
#   2. Standalone VM        — configures static IP manually,
#      vhost.conf expected in the same directory as this script
#
# Cross-platform: auto-detects the host gateway IP so it works
# on both VirtualBox (10.0.2.2) and VMware Fusion (172.16.x.x).
#
# Usage (standalone):
#   chmod +x setup.sh
#   sudo ./setup.sh
# ============================================================

set -euo pipefail

# ── Configuration ──────────────────────────────────────────
VM_IP="192.168.56.10"
VM_NETMASK="255.255.255.0"
ATTACKER_PORT="9090"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

info()  { echo -e "${GREEN}[+]${NC} $*"; }
warn()  { echo -e "${YELLOW}[!]${NC} $*"; }
error() { echo -e "${RED}[-]${NC} $*"; }

# ── Pre-checks ─────────────────────────────────────────────
if [[ $EUID -ne 0 ]]; then
    error "Run this script as root (sudo ./setup.sh)"
    exit 1
fi

IS_VAGRANT="${VAGRANT:-0}"

echo "============================================================"
echo "  CVE-2026-63686 — Target Apache Setup"
if [[ "$IS_VAGRANT" == "1" ]]; then
    echo "  Mode: Vagrant provisioner"
else
    echo "  Mode: Standalone VM"
fi
echo "============================================================"
echo

# ── 1. Detect host gateway IP ─────────────────────────────
# VirtualBox NAT gateway:  10.0.2.2
# VMware NAT gateway:      172.16.x.2 or similar
# We detect the default route gateway automatically.
GATEWAY_IP=$(ip route show default | awk '{print $3}' | head -1)
if [[ -z "$GATEWAY_IP" ]]; then
    GATEWAY_IP="10.0.2.2"
    warn "Could not detect gateway, falling back to ${GATEWAY_IP}"
else
    info "Detected host gateway: ${GATEWAY_IP}"
fi
ATTACKER_IP="${GATEWAY_IP}"

# ── 2. Configure network (standalone only) ─────────────────
if [[ "$IS_VAGRANT" == "1" ]]; then
    info "Vagrant mode — skipping network config (Vagrant handles it)"
else
    IFACE="ens33"
    info "Configuring static IP ${VM_IP} on ${IFACE}..."

    if command -v nmcli &>/dev/null && systemctl is-active --quiet NetworkManager; then
        nmcli con mod "Wired connection 1" \
            ipv4.addresses "${VM_IP}/24" \
            ipv4.method manual 2>/dev/null || \
        nmcli con add type ethernet con-name static-cve \
            ifname "$IFACE" \
            ipv4.addresses "${VM_IP}/24" \
            ipv4.method manual
        nmcli con up "static-cve" 2>/dev/null || nmcli con up "Wired connection 1"
    else
        cat > /etc/network/interfaces.d/cve-static <<EOF
auto ${IFACE}
iface ${IFACE} inet static
    address ${VM_IP}
    netmask ${VM_NETMASK}
EOF
        ifdown "$IFACE" 2>/dev/null || true
        ifup "$IFACE" 2>/dev/null || true
    fi
    info "IP configured."
fi

# ── 3. Install Apache ─────────────────────────────────────
info "Installing Apache and required packages..."
export DEBIAN_FRONTEND=noninteractive
apt-get update -qq
apt-get install -y -qq apache2 libxml2 curl

# ── 4. Enable vulnerable modules ──────────────────────────
info "Enabling modules: proxy, proxy_http, proxy_html, xml2enc..."
a2enmod proxy proxy_http proxy_html xml2enc

info "Disabling deflate (interferes with xml2enc filter chain)..."
a2dismod -f deflate 2>/dev/null || true

# ── 5. Deploy vhost config ────────────────────────────────
# Always generate the vhost inline using the detected gateway IP.
# This ensures it works on both VirtualBox and VMware regardless
# of what the static vhost.conf file contains.
info "Deploying reverse proxy vhost config..."
info "  Proxy target: http://${ATTACKER_IP}:${ATTACKER_PORT}/"

cat > /etc/apache2/sites-available/000-default.conf <<EOF
<VirtualHost *:80>
    ServerName vulnerable.local

    # Reverse proxy to attacker backend on the host machine
    ProxyPass        / http://${ATTACKER_IP}:${ATTACKER_PORT}/
    ProxyPassReverse / http://${ATTACKER_IP}:${ATTACKER_PORT}/

    # VULNERABLE CONFIG — triggers mod_xml2enc transcoding
    ProxyHTMLEnable  On
    xml2EncDefault   utf-8

    ErrorLog  /var/log/apache2/error.log
    CustomLog /var/log/apache2/access.log combined
    LogLevel  notice
</VirtualHost>
EOF
info "Vhost config written with gateway ${ATTACKER_IP}:${ATTACKER_PORT}"

# ── 6. Enable server-status for monitoring ─────────────────
info "Enabling server-status..."
echo 'SetHandler server-status' > /etc/apache2/conf-available/server-status.conf
a2enconf server-status 2>/dev/null || true

# ── 7. Restart Apache ──────────────────────────────────────
info "Testing Apache config..."
if apachectl configtest 2>&1 | grep -q "Syntax OK"; then
    info "Config syntax OK"
else
    error "Config syntax error!"
    apachectl configtest
    exit 1
fi

info "Restarting Apache..."
systemctl restart apache2

# ── 8. Verify ──────────────────────────────────────────────
echo
echo "============================================================"
echo "  Verification"
echo "============================================================"

info "Apache status: $(systemctl is-active apache2)"

echo
info "Loaded modules:"
apachectl -M 2>/dev/null | grep -E "proxy_html|xml2enc|proxy_http" || warn "Some modules missing!"

echo
info "Listening on:"
ss -tlnp | grep ':80 ' || warn "Apache not listening on port 80"

echo
info "Vhost proxy target:"
grep ProxyPass /etc/apache2/sites-available/000-default.conf | head -1

echo
echo "============================================================"
echo "  Setup Complete!"
echo "============================================================"
echo
echo "  Attacker backend: ${ATTACKER_IP}:${ATTACKER_PORT}"
echo
echo "  Next steps:"
echo "  1. On your host, run:  python3 attacker/poison.py --port ${ATTACKER_PORT}"
echo "  2. On your host, run:  curl http://localhost:8080/"
echo "  3. Check crash here:   sudo tail /var/log/apache2/error.log"
echo "     Look for: 'exit signal Segmentation fault (11)'"
echo
