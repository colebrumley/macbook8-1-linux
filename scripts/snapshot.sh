#!/bin/bash
# Recursive ZFS snapshot of the root dataset (and bpool for /boot) before risky changes.
set -euo pipefail
label=${1:?usage: snapshot.sh <label>}
ts=$(date +%Y%m%d-%H%M%S)
root=$(findmnt -no SOURCE /)
sudo zfs snapshot -r "$root@mb81-$label-$ts"
boot=$(findmnt -no SOURCE /boot 2>/dev/null || true)
case "$boot" in bpool/*) sudo zfs snapshot -r "$boot@mb81-$label-$ts";; esac
echo "snapshot: $root@mb81-$label-$ts"; case "$boot" in bpool/*) echo "snapshot: $boot@mb81-$label-$ts";; *) echo "note: /boot ($boot) is not ZFS; kernel/initrd are not covered";; esac
