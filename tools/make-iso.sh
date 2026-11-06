#!/bin/bash
# Build a MacBook8,1-ready Ubuntu installer ISO from a stock Ubuntu ISO.
#
#   tools/make-iso.sh ubuntu-26.10-desktop-amd64.iso  [out.iso]
#
# The result:
#   * boots the live/installer session with intel_iommu=off, so the internal Wi-Fi works
#     during installation (without it the Broadcom card's DMA faults and it never connects)
#   * carries this repo at /macbook8-1-linux and /autoinstall.yaml at the root: the normal
#     interactive installer runs, and at the end it arms the hardware setup to run on first
#     boot (autoinstall/late-commands.sh). The first boot then installs everything and reboots.
#
# The internal keyboard and trackpad do NOT work in the installer (they need the patched
# SPI driver this repo builds), so use a USB keyboard/mouse during installation.
# Requires: xorriso (apt install xorriso / brew install xorriso). Doesn't modify the input.
set -euo pipefail
IN=${1:?usage: make-iso.sh <ubuntu.iso> [out.iso]}
OUT=${2:-${IN%.iso}-macbook8-1.iso}
HERE=$(cd "$(dirname "$0")/.." && pwd)
command -v xorriso >/dev/null || { echo "xorriso not found (apt install xorriso / brew install xorriso)" >&2; exit 1; }
[ -f "$IN" ] || { echo "no such file: $IN" >&2; exit 1; }

work=$(mktemp -d); trap 'rm -rf "$work"' EXIT
stage=$work/macbook8-1-linux; mkdir -p "$stage"
if git -C "$HERE" rev-parse --git-dir >/dev/null 2>&1; then
  git -C "$HERE" archive HEAD | tar -x -C "$stage"
else
  (cd "$HERE" && tar --exclude=.git -cf - .) | tar -x -C "$stage"
fi

# patch every GRUB config that boots the installer kernel
maps=()
for cfg in /boot/grub/grub.cfg /boot/grub/loopback.cfg; do
  f=$work/$(basename "$cfg")
  if xorriso -osirrox on -indev "$IN" -extract "$cfg" "$f" >/dev/null 2>&1; then
    chmod u+w "$f"
    # add the parameter to each kernel line that doesn't have it yet (before "---" if present)
    awk '/^[[:space:]]*linux[[:space:]]/ && !/intel_iommu=off/ {
           if (!sub(/ ---/, " intel_iommu=off ---")) $0 = $0 " intel_iommu=off" }
         { print }' "$f" > "$f.new" && mv "$f.new" "$f"
    echo "patched $cfg: $(grep -c intel_iommu=off "$f") boot entries"
    maps+=(-map "$f" "$cfg")
  fi
done
[ ${#maps[@]} -gt 0 ] || { echo "no /boot/grub/grub.cfg in $IN; is this an Ubuntu ISO?" >&2; exit 1; }

rm -f "$OUT"
xorriso -indev "$IN" -outdev "$OUT" \
  "${maps[@]}" \
  -map "$stage" /macbook8-1-linux \
  -map "$HERE/autoinstall/autoinstall.yaml" /autoinstall.yaml \
  -boot_image any replay \
  >/dev/null 2>"$work/xorriso.log" || { cat "$work/xorriso.log" >&2; exit 1; }
echo "wrote $OUT"
echo "Write it to a USB stick (e.g. with dd or Balena Etcher), boot the MacBook holding Option (⌥),"
echo "pick \"EFI Boot\", install as usual with a USB keyboard, and let the first boot finish setup."
