#!/usr/bin/env bash
#
# subdomain_enum.sh — Passive subdomain enumeration
#
# Collects subdomains from crt.sh (always) and subfinder (if installed),
# merges and dedupes them, and optionally checks which are live.
#
# Usage:
#   ./subdomain_enum.sh -d example.com [-o output_dir] [-l]
#
# Options:
#   -d    Target domain (required)
#   -o    Output directory (default: ./output)
#   -l    Also resolve and filter to live hosts (needs dnsx, or falls back to `host`)
#   -h    Show this help
#
# Requirements:
#   curl, jq  (required)
#   subfinder (optional, adds another passive source)
#   dnsx      (optional, faster live-host resolution)
#
# Output:
#   <output_dir>/<domain>_all.txt    - every unique subdomain found
#   <output_dir>/<domain>_live.txt   - live subdomains only (if -l used)

set -euo pipefail

DOMAIN=""
OUTDIR="./output"
CHECK_LIVE=false

usage() {
    grep '^#' "$0" | sed -n '2,20p' | sed 's/^# \{0,1\}//'
    exit 1
}

while getopts "d:o:lh" opt; do
    case "$opt" in
        d) DOMAIN="$OPTARG" ;;
        o) OUTDIR="$OPTARG" ;;
        l) CHECK_LIVE=true ;;
        h) usage ;;
        *) usage ;;
    esac
done

if [[ -z "$DOMAIN" ]]; then
    echo "[!] Error: domain is required (-d example.com)" >&2
    usage
fi

for bin in curl jq; do
    if ! command -v "$bin" &>/dev/null; then
        echo "[!] Error: required tool '$bin' is not installed." >&2
        exit 1
    fi
done

mkdir -p "$OUTDIR"
RAW_FILE="$OUTDIR/${DOMAIN}_all.txt"
LIVE_FILE="$OUTDIR/${DOMAIN}_live.txt"
TMP_FILE=$(mktemp)
trap 'rm -f "$TMP_FILE"' EXIT

echo "[*] Enumerating subdomains for: $DOMAIN"

# --- Source 1: crt.sh (certificate transparency logs) ---
echo "[*] Querying crt.sh..."
if ! curl -s --max-time 30 "https://crt.sh/?q=%25.${DOMAIN}&output=json" \
    | jq -r '.[].name_value' 2>/dev/null \
    | sed 's/\*\.//g' \
    | tr '[:upper:]' '[:lower:]' >> "$TMP_FILE"; then
    echo "[!] Warning: crt.sh query failed or returned no data." >&2
fi

# --- Source 2: subfinder (if installed) ---
if command -v subfinder &>/dev/null; then
    echo "[*] Running subfinder..."
    subfinder -d "$DOMAIN" -silent >> "$TMP_FILE" 2>/dev/null || \
        echo "[!] Warning: subfinder run failed, continuing with other sources." >&2
else
    echo "[i] subfinder not found, skipping (install it for broader coverage)."
fi

# --- Merge, filter to in-scope subdomains, dedupe, sort ---
grep -E "(^|\.)${DOMAIN//./\\.}\$" "$TMP_FILE" \
    | grep -v '^\*' \
    | sort -u > "$RAW_FILE"

TOTAL=$(wc -l < "$RAW_FILE" | tr -d ' ')
echo "[+] Found $TOTAL unique subdomains -> $RAW_FILE"

# --- Optional: live host check ---
if [[ "$CHECK_LIVE" == true ]]; then
    echo "[*] Checking for live hosts..."
    : > "$LIVE_FILE"

    if command -v dnsx &>/dev/null; then
        dnsx -silent -l "$RAW_FILE" >> "$LIVE_FILE" 2>/dev/null || true
    else
        echo "[i] dnsx not found, falling back to slower 'host' lookups."
        while IFS= read -r sub; do
            if host "$sub" &>/dev/null; then
                echo "$sub" >> "$LIVE_FILE"
            fi
        done < "$RAW_FILE"
    fi

    LIVE_TOTAL=$(wc -l < "$LIVE_FILE" | tr -d ' ')
    echo "[+] $LIVE_TOTAL live hosts -> $LIVE_FILE"
fi

echo "[*] Done."
