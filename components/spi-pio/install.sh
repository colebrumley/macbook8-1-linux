#!/bin/bash
# Patched spi-pxa2xx (core + platform + pci) for MacBook8,1, built with DKMS:
#   patch_pio.py     force PIO (LPSS DMA never completes) and keep runtime PM off
#                    -> fixes the keyboard/trackpad (applespi "SPI transfer timed out")
#   patch_resume.py  save/restore LPSS private registers across S3
#                    -> prevents a watchdog reset on resume
# Sources in upstream/<kernel tag>/ are vanilla drivers/spi/*.c,h at the running kernel's tag.
set -euo pipefail
# The generated patch goes next to the DKMS sources in /usr/src (the copy in this repo is a
# reference for the vendored kernel tag; installing never modifies the checkout).
cd "$(dirname "$0")"

NAME=spi-pxa2xx-pio
VER=$(sed -n 's/^PACKAGE_VERSION="\(.*\)"/\1/p' dkms.conf)
SRC=/usr/src/$NAME-$VER
KTAG="v$(uname -r | cut -d. -f1-2)"   # 7.3.0-9-generic -> v7.3
FILES=(spi-pxa2xx.c spi-pxa2xx.h spi-pxa2xx-dma.c spi-pxa2xx-platform.c spi-pxa2xx-pci.c internals.h)

mkdir -p "upstream/$KTAG"
for f in "${FILES[@]}"; do
  [ -f "upstream/$KTAG/$f" ] || curl -fsSL -o "upstream/$KTAG/$f" \
    "https://git.kernel.org/pub/scm/linux/kernel/git/torvalds/linux.git/plain/drivers/spi/$f?h=$KTAG"
done

work=$(mktemp -d); trap 'rm -rf "$work"' EXIT
for f in "${FILES[@]}"; do cp "upstream/$KTAG/$f" "$work/"; done
python3 patch_pio.py "$work/spi-pxa2xx-pci.c"
python3 patch_resume.py "$work/spi-pxa2xx.c" "$work/spi-pxa2xx.h"
( cd "upstream/$KTAG" && for f in "${FILES[@]}"; do diff -u "$f" "$work/$f" --label "a/drivers/spi/$f" --label "b/drivers/spi/$f" || true; done ) > "$work/macbook81.patch"

# remove every installed version of this package, then install this one
for v in $(dkms status -m $NAME 2>/dev/null | sed -n "s|^$NAME/\([^,:]*\)[,:].*|\1|p" | sort -u); do
  dkms remove -m $NAME -v "$v" --all || true
  rm -rf "/usr/src/$NAME-$v"
done
mkdir -p "$SRC"
for f in "${FILES[@]}"; do cp "$work/$f" "$SRC/"; done
cp dkms.conf "$SRC/"; cp Makefile.kbuild "$SRC/Makefile"; cp "$work/macbook81.patch" "$SRC/"

dkms add -m $NAME -v "$VER"
dkms install -m $NAME -v "$VER"
for m in spi_pxa2xx_core spi_pxa2xx_platform spi_pxa2xx_pci; do echo "spi-pio: $m -> $(modinfo -n $m)"; done
