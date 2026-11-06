#!/bin/bash
# Arm the first-boot service (used by autoinstall/late-commands.sh). Not run by install.sh.
set -euo pipefail
cd "$(dirname "$0")"
install -m 0644 mb81-firstboot.service /etc/systemd/system/mb81-firstboot.service
chmod +x mb81-firstboot
systemctl enable mb81-firstboot.service
echo "firstboot: armed"
