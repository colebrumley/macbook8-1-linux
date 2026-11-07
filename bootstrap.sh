#!/bin/bash
# One-shot setup for a MacBook8,1 running Ubuntu:
#   curl -fsSL https://raw.githubusercontent.com/colebrumley/macbook8-1-linux/main/bootstrap.sh | sudo bash
#
# Clones (or updates) this repo into /opt/macbook8-1-linux, runs install.sh, and reboots
# unless MB81_NO_REBOOT=1. Environment variables are passed through to install.sh.
set -euo pipefail
REPO=${MB81_REPO:-https://github.com/colebrumley/macbook8-1-linux.git}
REF=${MB81_REF:-main}
DIR=${MB81_DIR:-/opt/macbook8-1-linux}

[ "$(id -u)" = 0 ] || { echo "run as root: curl ... | sudo bash" >&2; exit 1; }
command -v git >/dev/null || { apt-get update -q && DEBIAN_FRONTEND=noninteractive apt-get install -y -q git; }

if [ -d "$DIR/.git" ]; then
  git -C "$DIR" fetch -q origin "$REF" && git -C "$DIR" checkout -q -B "$REF" "origin/$REF"
else
  git clone -q --branch "$REF" "$REPO" "$DIR"
fi
# root owns the checkout; let any user run git in it (status, log) without "dubious ownership"
git config --system --get-all safe.directory 2>/dev/null | grep -qx "$DIR" || git config --system --add safe.directory "$DIR"
echo "macbook8-1-linux $(git -C "$DIR" rev-parse --short HEAD) in $DIR"

"$DIR/install.sh"

if [ "${MB81_NO_REBOOT:-0}" != 1 ]; then
  echo "Rebooting in 10 s to load the new drivers (Ctrl-C to cancel)..."
  sleep 10
  systemctl reboot
fi
