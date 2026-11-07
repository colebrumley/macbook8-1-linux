#!/bin/bash
# Keyboard backlight keys + persistence for desktops other than GNOME (see mb81-kbd-backlight).
set -euo pipefail
cd "$(dirname "$0")"
install -m 0755 mb81-kbd-backlight /usr/local/sbin/mb81-kbd-backlight
install -m 0644 mb81-kbd-backlight.service /etc/systemd/system/mb81-kbd-backlight.service
install -m 0755 system-sleep-hook /usr/lib/systemd/system-sleep/mb81-kbd-backlight
systemctl daemon-reload
systemctl enable --now mb81-kbd-backlight.service
echo "kbd-backlight: installed"
