#!/bin/bash
# Kernel command line additions for MacBook8,1.
#   intel_iommu=off : Ubuntu enables VT-d by default; brcmfmac (BCM4350) DMA then faults
#                     ("DMAR: PTE Read access is not set" for 01:00.0) and Wi-Fi never associates.
set -euo pipefail
#   mem_sleep_default=s2idle : deep S3 cuts power to the speaker amp, which only EFI can
#                     configure, so speakers stay silent after resume (FINDINGS F-14).
#                     s2idle keeps them working at ~1 W standby. For long standby instead:
#                     MB81_SLEEP=deep sudo components/grub/install.sh
SLEEP=${MB81_SLEEP:-s2idle}
PARAMS="intel_iommu=off mem_sleep_default=$SLEEP"
f=/etc/default/grub
[ -f $f.macbook8-1-linux.orig ] || cp $f $f.macbook8-1-linux.orig
cur=$(sed -n 's/^GRUB_CMDLINE_LINUX_DEFAULT="\(.*\)"/\1/p' $f)
new="$cur"
for p in $PARAMS; do
  key=${p%%=*}
  new=$(echo "$new" | tr ' ' '\n' | grep -v "^$key\(=\|$\)" | tr '\n' ' ')
  new="${new% } $p"
done
new=$(echo "$new" | sed 's/^ *//')
if [ "$new" != "$cur" ]; then
  sed -i "s|^GRUB_CMDLINE_LINUX_DEFAULT=.*|GRUB_CMDLINE_LINUX_DEFAULT=\"$new\"|" $f
  update-grub
fi
echo "grub: GRUB_CMDLINE_LINUX_DEFAULT=\"$new\""
