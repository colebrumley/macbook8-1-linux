#!/bin/bash
# Make all MacBook8,1 (12-inch, Early 2015) hardware work on an installed Ubuntu system.
# Idempotent: safe to re-run (e.g. after a kernel upgrade if DKMS ever fails).
#
#   sudo ./install.sh                    everything
#   sudo MB81_COMPONENTS="audio camera" ./install.sh   only some components
#   sudo MB81_SLEEP=deep ./install.sh    deep S3 instead of s2idle (see README, "Sleep")
#
# Needs internet (packages, kernel sources from git.kernel.org, camera firmware from
# Apple's CDN). Log: /var/log/mb81-linux-install.log. Reboot when it finishes.
set -euo pipefail
cd "$(dirname "$0")"
[ "$(id -u)" = 0 ] || exec sudo -E "$0" "$@"
exec > >(tee -a /var/log/mb81-linux-install.log) 2>&1
echo "=== macbook8-1-linux install $(date -Is) kernel $(uname -r)"

if ! grep -q "MacBook8,1" /sys/class/dmi/id/product_name 2>/dev/null; then
  [ "${MB81_FORCE:-0}" = 1 ] || { echo "This is not a MacBook8,1 ($(cat /sys/class/dmi/id/product_name 2>/dev/null)). Set MB81_FORCE=1 to override." >&2; exit 1; }
fi

# --- packages: install what exists on this release, warn about the rest ---------------
export DEBIAN_FRONTEND=noninteractive
apt-get update -q
want=$(grep -vE '^\s*(#|$)' packages.txt | tr '\n' ' ')
have=""; miss=""
for p in $want "linux-headers-$(uname -r)"; do
  if apt-cache show "$p" >/dev/null 2>&1; then have+="$p "; else miss+="$p "; fi
done
apt-get install -y -q $have
[ -n "$miss" ] && echo "note: not available on this release, skipped: $miss"

# --- migrate names from the original bring-up repo (pluto-hw) -------------------------
if [ -e /etc/systemd/system/pluto-bt-recover.service ]; then
  systemctl disable --now pluto-bt-recover.service 2>/dev/null || true
  rm -f /etc/systemd/system/pluto-bt-recover.service /usr/local/sbin/pluto-bt-recover \
        /usr/lib/systemd/system-sleep/pluto-bt-recover
fi
rm -f /etc/modprobe.d/pluto-hw-*.conf
[ -d /var/lib/pluto-hw ] && [ ! -d /var/lib/mb81-linux ] && mv /var/lib/pluto-hw /var/lib/mb81-linux

# --- components (order matters: modules before initramfs, initramfs before grub) ------
COMPONENTS=(${MB81_COMPONENTS:-modprobe spi-pio uart-lpss audio camera bt-recover nvme-resume acpi-dsdt grub})
failed=()
for c in "${COMPONENTS[@]}"; do
  echo "== $c"
  if ! "components/$c/install.sh"; then
    echo "!! component $c failed (see above); continuing with the rest"
    failed+=("$c")
  fi
done
update-initramfs -u -k all

echo
if [ ${#failed[@]} -eq 0 ]; then
  echo "Done. Reboot, then run: $(pwd)/scripts/verify.sh"
else
  echo "Finished with failures in: ${failed[*]}. Fix, then re-run install.sh."
  exit 1
fi
