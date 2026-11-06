#!/bin/bash
# Suspend to RAM (S3, "deep"), wake by RTC, then check that the hardware came back.
# Result goes to /var/lib/mb81-linux/last-suspend, which verify.sh PWR-3 reads.
#
# Run it detached so a hung resume doesn't take your shell with it:
#   sudo systemd-run --unit=mb81-suspend-test --collect ~/src/macbook8-1-linux/scripts/test-suspend.sh [seconds]
#   journalctl -u mb81-suspend-test -f
set -uo pipefail
[ "$(id -u)" = 0 ] || exec sudo "$0" "$@"
SLEEP=${1:-30}
OUT=/var/lib/mb81-linux/last-suspend
mkdir -p "$(dirname $OUT)"

log() { echo "[test-suspend] $*"; }
fail=()
HERE=$(cd "$(dirname "$0")" && pwd)
STATE=/var/lib/mb81-linux/s3-$(date +%Y%m%d-%H%M%S)
mkdir -p "$STATE"
capture() { # $1 = pre|post
  for d in 00:1c.4 03:00.0 00:15.4 00:15.5 01:00.0; do lspci -vvv -xxx -s $d > "$STATE/$1-lspci-${d//:/_}.txt" 2>&1; done
  python3 "$HERE/lpss-regs.py" > "$STATE/$1-lpss.txt" 2>&1
  cat /proc/interrupts > "$STATE/$1-interrupts.txt"
}
nvme_probe() { # direct read that must not wait on an I/O timeout
  local s e; s=$(date +%s%N)
  timeout 20 dd if=/dev/nvme0n1 of=/dev/null bs=1M count=64 skip=$((RANDOM % 100000)) iflag=direct status=none || return 1
  e=$(date +%s%N); echo $(( (e-s)/1000000 ))
}

# deep (S3) or s2idle; default = the system's current choice (macbook8-1-linux sets s2idle, F-14)
MODE=${MODE:-$(sed -n 's/.*\[\([a-z0-9]*\)\].*/\1/p' /sys/power/mem_sleep)}
AUDIO=${AUDIO:-0}    # AUDIO=1: also run the (audible, quiet) speaker/mic loopback after resume
echo "$MODE" > /sys/power/mem_sleep
irq21_before=$(awk '$1=="21:"{s=0; for(i=2;i<=5;i++) s+=$i; print s}' /proc/interrupts)
t0=$(date '+%Y-%m-%d %H:%M:%S')
log "suspending for ${SLEEP}s at $t0 (mem_sleep: $(cat /sys/power/mem_sleep))"
capture pre
sync
# Suspend the way a lid close does (systemctl suspend), so systemd-sleep hooks run;
# `rtcwake -m mem` would write /sys/power/state directly and skip them. Wake by RTC alarm.
echo 0 > /sys/class/rtc/rtc0/wakealarm
echo "+$SLEEP" > /sys/class/rtc/rtc0/wakealarm
if ! systemctl suspend; then fail+=("systemctl suspend failed"); fi
# systemctl suspend returns once the sleep job is queued: wait for the resume
for i in $(seq 1 $((SLEEP + 120))); do
  journalctl -k --since "$t0" --no-pager | grep -q "PM: suspend exit" && break
  sleep 1
done
sleep 2
log "resumed at $(date '+%H:%M:%S')"

# give drivers and NetworkManager time to come back
for i in $(seq 1 45); do
  [ "$(nmcli -g GENERAL.STATE dev show wlp1s0 2>/dev/null | cut -d' ' -f1)" = 100 ] && break
  sleep 1
done
sleep 3
capture post
ms=$(nvme_probe) || ms=timeout
log "nvme 64MiB direct read after resume: ${ms}ms"
[ "$ms" != timeout ] && [ "$ms" -lt 3000 ] || fail+=("NVMe direct read slow after resume (${ms}ms)")
bt_n=$(timeout 25 bluetoothctl --timeout 12 scan on 2>/dev/null | grep -c NEW)
[ "$bt_n" -gt 0 ] || fail+=("Bluetooth scan found nothing after resume")

if [ "$AUDIO" = 1 ]; then
  audio=$("$HERE/test-audio.sh" 2>&1 | grep -E "^(ratio|result)=" | tr '\n' ' ')
  log "audio after resume: $audio"
  grep -q "result=ok" <<<"$audio" || fail+=("speakers/mic loopback failed after resume ($audio)")
fi

klog=$(journalctl -k --since "$t0" --no-pager)
grep -q "PM: suspend entry ($MODE)" <<<"$klog" || fail+=("never entered $MODE suspend")
grep -q "PM: suspend exit" <<<"$klog" || fail+=("no suspend exit in log")
n=$(grep -c "SPI transfer timed out" <<<"$klog"); [ "$n" -eq 0 ] || fail+=("$n SPI timeouts after resume")
grep -qE "applespi.*(error|failed)" <<<"$klog" && fail+=("applespi errors after resume")
grep -q 'Name="Apple SPI Keyboard"' /proc/bus/input/devices || fail+=("keyboard input device gone")
grep -q 'Name="Apple SPI Touchpad"' /proc/bus/input/devices || fail+=("touchpad input device gone")
irq21_after=$(awk '$1=="21:"{s=0; for(i=2;i<=5;i++) s+=$i; print s}' /proc/interrupts)
[ "$irq21_after" -gt "$irq21_before" ] || fail+=("IRQ 21 (SPI/UART) silent after resume")
[ "$(nmcli -g GENERAL.STATE dev show wlp1s0 2>/dev/null | cut -d' ' -f1)" = 100 ] || fail+=("wlp1s0 did not reconnect within 45s")
grep -qE "brcmf.*(Timeout|firmware has halted|bus is down)" <<<"$klog" && fail+=("brcmfmac errors after resume")
timeout 10 bluetoothctl show 2>/dev/null | grep -q "Powered: yes" || fail+=("hci0 not powered after resume")
grep -qE "Bluetooth: hci0: .*(tx timeout|Reset failed)" <<<"$klog" && fail+=("Bluetooth UART errors after resume")
grep -qiE "nvme.*(timeout|reset)" <<<"$klog" && fail+=("NVMe errors after resume")
grep -qiE "i915.*(GPU HANG|failed)" <<<"$klog" && fail+=("i915 errors after resume")

{
  echo "date=$(date -Is)"
  echo "kernel=$(uname -r)"
  echo "slept=${SLEEP}s"
  echo "mode=$MODE"
  echo "audio=$AUDIO"
  echo "state=$STATE"
  if [ ${#fail[@]} -eq 0 ]; then echo "result=ok"; else echo "result=fail"; printf 'problem=%s\n' "${fail[@]}"; fi
} > $OUT
cat $OUT
[ ${#fail[@]} -eq 0 ]
