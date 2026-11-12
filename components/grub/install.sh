#!/bin/bash
# Kernel command line additions for MacBook8,1.
#   intel_iommu=off : Ubuntu enables VT-d by default; brcmfmac (BCM4350) DMA then faults
#                     ("DMAR: PTE Read access is not set" for 01:00.0) and Wi-Fi never associates.
set -euo pipefail
#   mem_sleep_default=deep : real S3 standby. (Speakers survive it since the audio fix for
#                     FINDINGS F-14.) For s2idle instead: MB81_SLEEP=s2idle sudo components/grub/install.sh
SLEEP=${MB81_SLEEP:-deep}
PARAMS="intel_iommu=off mem_sleep_default=$SLEEP"
#   mitigations=off  (opt-in: MB81_MITIGATIONS=off) : drops Spectre/Meltdown-class CPU
#                     mitigations. Big speedup on Broadwell; reopens those side channels
#                     (realistic vector: hostile JavaScript). Set MB81_MITIGATIONS=auto to undo.
case "${MB81_MITIGATIONS:-}" in
  off)  PARAMS="$PARAMS mitigations=off" ;;
  auto) PARAMS="$PARAMS mitigations=auto" ;;
esac
#   intel_pstate=active (opt-in: MB81_PSTATE=active) : Broadwell has no HWP, so the kernel
#                     defaults to intel_cpufreq + schedutil. "active" lets intel_pstate pick
#                     P-states itself. Not benchmarked here. MB81_PSTATE=passive to undo.
case "${MB81_PSTATE:-}" in
  active|passive) PARAMS="$PARAMS intel_pstate=$MB81_PSTATE" ;;
esac
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
