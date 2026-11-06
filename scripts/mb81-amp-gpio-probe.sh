#!/bin/bash
# Post-S3 speaker amp probe: while a quiet 1 kHz tone plays on hw:PCH,1, drive codec GPIO
# data to each candidate value (GPIO0 = amp enable; GPIO4/5 = amp supply DFETs, polarity
# unknown) and record the internal mic. Prints the 1 kHz ratio per value. Audible, quiet.
# Usage: sudo scripts/mb81-amp-gpio-probe.sh [data ...]   (default: 0x01 0x31 0x11 0x21)
set -uo pipefail
[ "$(id -u)" = 0 ] || exec sudo "$0" "$@"
HERE=$(cd "$(dirname "$0")" && pwd)
HW=$(for h in /sys/class/sound/hwC*D0; do grep -q 0x10134208 $h/vendor_id && echo $h; done | head -1)
H=/dev/snd/$(basename "$HW")
v() { hda-verb $H "$@" 2>/dev/null | grep -o "value = 0x[0-9a-f]*" | cut -d" " -f3; }
VALS=("${@:-0x01 0x31 0x11 0x21}"); [ $# -eq 0 ] && VALS=(0x01 0x31 0x11 0x21)

for u in gdm-greeter ${SUDO_USER:-}; do systemctl --user -M "$u@" stop pipewire.socket pipewire-pulse.socket pipewire.service pipewire-pulse.service wireplumber.service >/dev/null 2>&1; done
trap 'for u in gdm-greeter ${SUDO_USER:-}; do systemctl --user -M "$u@" start pipewire.socket pipewire-pulse.socket wireplumber.service >/dev/null 2>&1; done' EXIT
amixer -q -c PCH sset Capture 70% cap 2>/dev/null; amixer -q -c PCH sset "Mic Boost" 1 2>/dev/null

for d in "${VALS[@]}"; do
  f=$(mktemp --suffix=.wav)
  arecord -q -D hw:PCH,0 -f S16_LE -r 44100 -c2 -d3 "$f" &
  sleep 0.3
  python3 "$HERE/tone.py" 1000 2.2 44100 4 | aplay -q -D hw:PCH,1 -f S16_LE -r 44100 -c4 &
  sleep 0.3   # after prepare (which rewrites GPIO data)
  v 0x01 0x716 0x39 >/dev/null; v 0x01 0x717 0x31 >/dev/null; v 0x01 0x715 "$d" >/dev/null
  sleep 0.2
  got="data=$(v 0x01 0xf15 0) en=$(v 0x01 0xf16 0) dir=$(v 0x01 0xf17 0)"
  wait
  printf "gpio %s (%s): %s\n" "$d" "$got" "$(python3 "$HERE/tone.py" analyze "$f")"
  rm -f "$f"
done
v 0x01 0x716 0x09 >/dev/null; v 0x01 0x717 0x01 >/dev/null; v 0x01 0x715 0x00 >/dev/null
