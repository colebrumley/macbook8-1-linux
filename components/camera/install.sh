#!/bin/bash
# FaceTime HD camera (Broadcom 1570, 14e4:1570): patjak/facetimehd driver via DKMS plus
# firmware extracted from Apple's macOS 10.12.6 combo update (downloaded from Apple's CDN).
# Both upstream repos are pinned to reviewed commits; the firmware Makefile's `curl -k`
# (TLS verification off) is replaced with `curl --fail`.
set -euo pipefail
cd "$(dirname "$0")"
DRV_COMMIT=4e588ae
FW_COMMIT=961774d
SRC=${SRC_DIR:-/var/cache/mb81-linux/src}
mkdir -p "$SRC"

fetch() { # repo commit
  [ -d "$SRC/$1" ] || git clone -q "https://github.com/patjak/$1.git" "$SRC/$1"
  git -C "$SRC/$1" fetch -q origin
  git -C "$SRC/$1" checkout -q "$2"
}
fetch facetimehd "$DRV_COMMIT"
fetch facetimehd-firmware "$FW_COMMIT"

# firmware
fw="$SRC/facetimehd-firmware"
if [ ! -s "$fw/firmware.bin" ]; then
  git -C "$fw" checkout -q -- Makefile
  sed -i 's/curl -k /curl --fail /' "$fw/Makefile"
  make -C "$fw"
fi
install -d /usr/lib/firmware/facetimehd
install -m 0644 "$fw/firmware.bin" /usr/lib/firmware/facetimehd/firmware.bin
for f in "$fw"/*.dat; do install -m 0644 "$f" /usr/lib/firmware/facetimehd/; done

# driver
VER=$(sed -n 's/^PACKAGE_VERSION=\(.*\)/\1/p' "$SRC/facetimehd/dkms.conf" | tr -d '"')
for v in $(dkms status -m facetimehd 2>/dev/null | sed -n "s|^facetimehd/\([^,:]*\)[,:].*|\1|p" | sort -u); do
  dkms remove -m facetimehd -v "$v" --all || true; rm -rf "/usr/src/facetimehd-$v"
done
rm -rf "/usr/src/facetimehd-$VER"; cp -r "$SRC/facetimehd" "/usr/src/facetimehd-$VER"; rm -rf "/usr/src/facetimehd-$VER/.git"
dkms add -m facetimehd -v "$VER"
dkms install -m facetimehd -v "$VER"
# bdc_pci (Broadcom USB device controller) claims the camera's PCI ID otherwise
echo "blacklist bdc_pci" > /etc/modprobe.d/mb81-facetimehd.conf
echo "camera: facetimehd $VER -> $(modinfo -n facetimehd)"
