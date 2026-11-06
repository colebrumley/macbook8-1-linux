#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"
install -m 0755 mb81-bt-recover /usr/local/sbin/mb81-bt-recover
install -m 0644 mb81-bt-recover.service /etc/systemd/system/mb81-bt-recover.service
install -m 0755 system-sleep-hook /usr/lib/systemd/system-sleep/mb81-bt-recover
systemctl daemon-reload
systemctl enable mb81-bt-recover.service
echo "bt-recover: installed"
