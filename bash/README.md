# bash

Bash scripts, organized by category.

## Categories

- [`recon/`](./recon) — Reconnaissance and enumeration scripts

## Scripts

| Script | Category | Description |
|---|---|---|
| [`recon/subdomain_enum.sh`](./recon/subdomain_enum.sh) | recon | Passive subdomain enumeration from multiple sources, with optional live-host resolution |
| [`recon/port_scan.sh`](./recon/port_scan.sh) | recon | Nmap wrapper: full-port sweep, then targeted service/version detection on open ports |

## Requirements

- Bash 4+
- `curl`, `jq`
- Optional: `subfinder`, `dnsx` (for extended source coverage and live resolution)
