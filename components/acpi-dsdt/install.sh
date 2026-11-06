#!/bin/bash
# DSDT override: disable \_SB.PCI0.URT0.SSDC so Linux's serdev binds the Bluetooth
# node (BCM2E7C, \_SB.PCI0.URT0.BLTH) on the LPSS UART. Without this, serdev registers
# SSDC first and Bluetooth fails with "failure adding ACPI serdev device -EBUSY".
#
# Always builds from the firmware's *original* DSDT, so it stays correct after an
# EFI update. If the firmware table is already our override, it reuses the saved original.
set -euo pipefail
cd "$(dirname "$0")"
# this machine's unmodified firmware DSDT (Apple's table; kept locally, never committed)
ORIG=/var/lib/mb81-linux/original-dsdt.dat
mkdir -p "$(dirname "$ORIG")"
[ -f "$ORIG" ] || { [ -f original/dsdt.dat ] && cp original/dsdt.dat "$ORIG"; } || true
command -v iasl >/dev/null || apt-get install -y acpica-tools

work=$(mktemp -d); trap 'rm -rf "$work"' EXIT
klog=$(journalctl -k -b --no-pager)
if grep -q "ACPI: Table Upgrade: override \[DSDT" <<<"$klog"; then
  # booted with an override: /sys has the override, so rebuild from the stashed original
  [ -f "$ORIG" ] || { echo "running DSDT is an override but $ORIG is missing" >&2; exit 1; }
  cp "$ORIG" "$work/dsdt.dat"
else
  cat /sys/firmware/acpi/tables/DSDT > "$work/dsdt.dat"
  cp "$work/dsdt.dat" "$ORIG"
fi

# SSDTs must be passed as externals (-e) or iasl guesses argument counts for
# methods they define and the recompiled AML is wrong.
for t in /sys/firmware/acpi/tables/SSDT*; do cat "$t" > "$work/$(basename "$t").dat"; done
(cd "$work" && iasl -e SSDT*.dat -d dsdt.dat >/dev/null 2>&1)
python3 patch_dsdt.py "$work/dsdt.dsl" "$work/dsdt-mod.dsl"
(cd "$work" && iasl -p dsdt-mod dsdt-mod.dsl 2>&1 | grep "Compilation successful" >/dev/null)
# Sanity: recompile the *unmodified* source the same way, decompile both, and require
# that they differ only in the two patched lines (header revision + SSDC._STA).
# (Comparing against the firmware AML directly is useless: iasl's optimizer
# rewrites constants, so every recompile "differs" in ~1000 lines.)
(cd "$work" && cp dsdt.dsl ref.dsl && iasl -p ref ref.dsl >/dev/null 2>&1 \
  && cp dsdt-mod.aml chk.aml \
  && iasl -e SSDT*.dat -d ref.aml >/dev/null 2>&1 && iasl -e SSDT*.dat -d chk.aml >/dev/null 2>&1)
changed=$(diff <(grep -v '^ \*' "$work/ref.dsl") <(grep -v '^ \*' "$work/chk.dsl") | grep -c '^>' || true)
[ "$changed" -le 2 ] || { echo "override differs from original in $changed lines; refusing" >&2; exit 1; }

install -D -m 0644 "$work/dsdt-mod.aml" /usr/lib/firmware/acpi/dsdt.aml
install -D -m 0644 90-acpi-override.conf /etc/dracut.conf.d/90-acpi-override.conf
echo "acpi-dsdt: installed /usr/lib/firmware/acpi/dsdt.aml (rebuild initramfs to apply)"
