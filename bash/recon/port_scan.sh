#!/usr/bin/env bash
#
# port_scan.sh — Port scan + service detection wrapper around nmap
#
# Runs a fast full-port sweep to find open ports, then a targeted
# version/script scan (-sV -sC) against just those ports. This is
# much faster than running -sV -sC across all 65535 ports directly.
#
# Usage:
#   ./port_scan.sh -t target [-o output_dir] [-p ports] [-u] [-v]
#
# Options:
#   -t    Target IP, hostname, or CIDR range (required)
#   -o    Output directory (default: ./output)
#   -p    Port range for the initial sweep (default: 1-65535)
#   -u    Also scan top 100 UDP ports
#   -v    Run default vuln scripts (--script vuln) on open ports
#   -h    Show this help
#
# Requirements:
#   nmap (must be run with sufficient privileges for SYN scan; falls
#   back to a TCP connect scan automatically if not run as root)
#
# Output (all under <output_dir>/<target>/):
#   sweep.txt              - raw output of the initial full-port sweep
#   open_ports.txt         - comma-separated list of open TCP ports found
#   service_scan.txt       - -sV -sC results against the open ports
#   service_scan.xml       - same, in XML (for tool chaining / parsing)
#   udp_scan.txt           - top-100 UDP scan results (if -u used)
#   vuln_scan.txt          - vuln script results (if -v used)

set -euo pipefail

TARGET=""
OUTDIR="./output"
PORT_RANGE="1-65535"
DO_UDP=false
DO_VULN=false

usage() {
    grep '^#' "$0" | sed -n '2,25p' | sed 's/^# \{0,1\}//'
    exit 1
}

while getopts "t:o:p:uvh" opt; do
    case "$opt" in
        t) TARGET="$OPTARG" ;;
        o) OUTDIR="$OPTARG" ;;
        p) PORT_RANGE="$OPTARG" ;;
        u) DO_UDP=true ;;
        v) DO_VULN=true ;;
        h) usage ;;
        *) usage ;;
    esac
done

if [[ -z "$TARGET" ]]; then
    echo "[!] Error: target is required (-t 10.10.10.10)" >&2
    usage
fi

if ! command -v nmap &>/dev/null; then
    echo "[!] Error: nmap is not installed." >&2
    exit 1
fi

SCAN_TYPE="-sS"
if [[ "$EUID" -ne 0 ]]; then
    echo "[i] Not running as root, falling back to TCP connect scan (-sT)." >&2
    SCAN_TYPE="-sT"
fi

TARGET_DIR="$OUTDIR/$TARGET"
mkdir -p "$TARGET_DIR"

echo "[*] Target: $TARGET"
echo "[*] Output directory: $TARGET_DIR"

# --- Step 1: fast full-port sweep ---
echo "[*] Running initial port sweep ($PORT_RANGE)..."
nmap "$SCAN_TYPE" -Pn -T4 -p "$PORT_RANGE" --min-rate 1000 \
    -oN "$TARGET_DIR/sweep.txt" "$TARGET" >/dev/null

OPEN_PORTS=$(grep -E '^[0-9]+/tcp.*open' "$TARGET_DIR/sweep.txt" \
    | cut -d/ -f1 | paste -sd, -)

if [[ -z "$OPEN_PORTS" ]]; then
    echo "[!] No open TCP ports found in range $PORT_RANGE."
else
    echo "$OPEN_PORTS" > "$TARGET_DIR/open_ports.txt"
    echo "[+] Open ports: $OPEN_PORTS -> $TARGET_DIR/open_ports.txt"

    # --- Step 2: targeted service/version scan ---
    echo "[*] Running service/version detection on open ports..."
    nmap "$SCAN_TYPE" -Pn -sV -sC -T4 -p "$OPEN_PORTS" \
        -oN "$TARGET_DIR/service_scan.txt" \
        -oX "$TARGET_DIR/service_scan.xml" \
        "$TARGET" >/dev/null
    echo "[+] Service scan results -> $TARGET_DIR/service_scan.txt"

    # --- Step 3 (optional): vuln scripts ---
    if [[ "$DO_VULN" == true ]]; then
        echo "[*] Running vuln scripts on open ports (this can take a while)..."
        nmap "$SCAN_TYPE" -Pn --script vuln -T4 -p "$OPEN_PORTS" \
            -oN "$TARGET_DIR/vuln_scan.txt" \
            "$TARGET" >/dev/null
        echo "[+] Vuln scan results -> $TARGET_DIR/vuln_scan.txt"
    fi
fi

# --- Optional: top 100 UDP ports ---
if [[ "$DO_UDP" == true ]]; then
    echo "[*] Running top-100 UDP scan..."
    nmap -sU -Pn -T4 --top-ports 100 \
        -oN "$TARGET_DIR/udp_scan.txt" \
        "$TARGET" >/dev/null
    echo "[+] UDP scan results -> $TARGET_DIR/udp_scan.txt"
fi

echo "[*] Done."
