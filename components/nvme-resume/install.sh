#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"
install -m 0755 system-sleep-hook /usr/lib/systemd/system-sleep/mb81-nvme-resume
echo "nvme-resume: installed"
