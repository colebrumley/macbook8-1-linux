#!/bin/bash
# 8250_lpss with system-sleep PM ops (see patch_uart.py). Fixes Bluetooth after S3.
set -euo pipefail
# The generated patch goes next to the DKMS sources in /usr/src (the copy in this repo is a
# reference for the vendored kernel tag; installing never modifies the checkout).
cd "$(dirname "$0")"
NAME=8250-lpss-pm
VER=$(sed -n 's/^PACKAGE_VERSION="\(.*\)"/\1/p' dkms.conf)
SRC=/usr/src/$NAME-$VER
KTAG="v$(uname -r | cut -d. -f1-2)"
BASE=https://git.kernel.org/pub/scm/linux/kernel/git/torvalds/linux.git/plain/drivers/tty/serial
# path in kernel tree -> local name (serial_mctrl_gpio.h is included as "../serial_mctrl_gpio.h")
declare -A FILES=([8250/8250_lpss.c]=8250_lpss.c [8250/8250_dwlib.h]=8250_dwlib.h [8250/8250.h]=8250.h [serial_mctrl_gpio.h]=serial_mctrl_gpio.h)

mkdir -p "upstream/$KTAG"
for k in "${!FILES[@]}"; do
  [ -f "upstream/$KTAG/${FILES[$k]}" ] || curl -fsSL -o "upstream/$KTAG/${FILES[$k]}" "$BASE/$k?h=$KTAG"
done

work=$(mktemp -d); trap 'rm -rf "$work"' EXIT
mkdir -p "$work/8250"
cp upstream/$KTAG/8250_lpss.c upstream/$KTAG/8250_dwlib.h upstream/$KTAG/8250.h "$work/8250/"
cp upstream/$KTAG/serial_mctrl_gpio.h "$work/"
python3 patch_uart.py "$work/8250/8250_lpss.c"
diff -u upstream/$KTAG/8250_lpss.c "$work/8250/8250_lpss.c" --label a/drivers/tty/serial/8250/8250_lpss.c --label b/drivers/tty/serial/8250/8250_lpss.c > "$work/macbook81-uart-pm.patch" || true

for v in $(dkms status -m $NAME 2>/dev/null | sed -n "s|^$NAME/\([^,:]*\)[,:].*|\1|p" | sort -u); do
  dkms remove -m $NAME -v "$v" --all || true; rm -rf "/usr/src/$NAME-$v"
done
mkdir -p "$SRC"
cp -r "$work"/* "$SRC/"
cp dkms.conf "$SRC/"
printf 'obj-m := 8250_lpss.o\n8250_lpss-y := 8250/8250_lpss.o\n' > "$SRC/Makefile"
dkms add -m $NAME -v "$VER"
dkms install -m $NAME -v "$VER"
echo "uart-lpss: 8250_lpss -> $(modinfo -n 8250_lpss)"
