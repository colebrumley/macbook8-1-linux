#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"
install -m 0755 mb81-power-limit /usr/local/sbin/mb81-power-limit
install -m 0644 mb81-power-limit.service /etc/systemd/system/mb81-power-limit.service
install -m 0755 system-sleep-hook /usr/lib/systemd/system-sleep/mb81-power-limit
install -m 0644 90-mb81-power-limit.rules /etc/udev/rules.d/90-mb81-power-limit.rules
udevadm control --reload
systemctl daemon-reload
systemctl enable --now mb81-power-limit.service
echo "power-limit: PL1 $(( $(cat /sys/class/powercap/intel-rapl:0/constraint_0_power_limit_uw) / 1000000 )) W"
