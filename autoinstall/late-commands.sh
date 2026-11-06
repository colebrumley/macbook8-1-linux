#!/bin/sh
# Run by Ubuntu's installer at the end of an install (autoinstall late-commands), with the
# new system mounted at /target. Prepares the MacBook8,1 setup to run on first boot:
#   1. kernel parameter intel_iommu=off, so internal Wi-Fi works on first boot
#   2. this repo in /target/opt/macbook8-1-linux (from the install media, else GitHub)
#   3. mb81-firstboot.service, which runs install.sh once and reboots
set -eu
T=${TARGET:-/target}
grep -q "MacBook8,1" /sys/class/dmi/id/product_name 2>/dev/null || { echo "not a MacBook8,1, skipping"; exit 0; }

DEST=$T/opt/macbook8-1-linux
mkdir -p "$DEST"
SRC=""
for d in /cdrom/macbook8-1-linux /isodevice/macbook8-1-linux "$(dirname "$0")/.."; do
  [ -f "$d/install.sh" ] && { SRC=$d; break; }
done
if [ -n "$SRC" ]; then
  cp -a "$SRC"/. "$DEST"/
else
  curl -fsSL https://github.com/colebrumley/macbook8-1-linux/archive/refs/heads/main.tar.gz \
    | tar xz --strip-components=1 -C "$DEST"
fi

G=$T/etc/default/grub
if ! grep -q "intel_iommu=off" "$G"; then
  sed -i 's/^GRUB_CMDLINE_LINUX_DEFAULT="\(.*\)"/GRUB_CMDLINE_LINUX_DEFAULT="\1 intel_iommu=off"/' "$G"
fi
curtin in-target --target="$T" -- update-grub
curtin in-target --target="$T" -- /opt/macbook8-1-linux/components/firstboot/install.sh
echo "macbook8-1-linux: first-boot setup armed"
