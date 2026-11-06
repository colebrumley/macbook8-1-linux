#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"
for f in *.conf; do install -m 0644 "$f" "/etc/modprobe.d/$f"; done
echo "modprobe: installed $(ls *.conf | tr '\n' ' ')"
