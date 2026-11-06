#!/bin/bash
# Live experiment for the MacBook8,1 speaker (TDM via 0x0a/0x1d) + internal mic (DMIC1, 0x19).
# Reconfigures the stock driver, applies the EFI codec image, unmutes the amp (GPIO0=0),
# then plays 1 kHz into the speaker link while recording the mic; prints the tone ratio.
# Usage: sudo scripts/mb81-audio-live.sh [tdm-nid ...]
set -uo pipefail
[ "$(id -u)" = 0 ] || exec sudo "$0" "$@"
HERE=$(cd "$(dirname "$0")" && pwd)
HW=$(for h in /sys/class/sound/hwC*D0; do grep -q 0x10134208 $h/vendor_id && echo $h; done | head -1)
H=/dev/snd/$(basename $HW); C=PCH   # card numbers swap between boots; the ALSA id "PCH" is stable
EFI=$HERE/../components/audio/efi-codec-state.json
v() { hda-verb $H "$@" 2>/dev/null | grep -o "value = 0x[0-9a-f]*" | cut -d" " -f3; }

for u in gdm-greeter ${SUDO_USER:-}; do systemctl --user -M "$u@" stop pipewire.socket pipewire-pulse.socket pipewire.service pipewire-pulse.service wireplumber.service >/dev/null 2>&1; done

# Minimal pin map. The full Apple layout map (HP 0x10 as line-out, headset 0x18, analog
# speaker pins N/A, ...) latches the codec PLL fault at reconfig time; this one does not.
PINS=${PINS:-"0x1d 0x90400010|0x19 0x90a00070|0x1c 0x770000f0"}
IFS='|' read -ra PIN_LIST <<<"$PINS"
for p in "${PIN_LIST[@]}"; do echo "$p" > $HW/user_pin_configs; done
[ "$(v 0x24 0x500 0x1f >/dev/null; v 0x24 0xc00 0)" = 0x0 ] || { echo "PLL fault already latched (coef 0x1f=0x400): reboot first"; exit 1; }
echo 1 > $HW/reconfig || { echo "reconfig failed"; exit 1; }
sleep 1
aplay -l | grep "\[PCH\]"; arecord -l | grep "\[PCH\]"

setup() {
  v 0x01 0x705 0x00 >/dev/null          # AFG D0
  v 0x24 0x703 0x01 >/dev/null          # VPW processing on
  python3 $HERE/cs4208-coef.py apply $EFI >/dev/null
  v 0x24 0x500 0x40 >/dev/null; v 0x24 0x400 0x9999 >/dev/null   # test mode on
  v 0x24 0x500 0x50 >/dev/null; v 0x24 0x400 0x00cb >/dev/null
  v 0x24 0x500 0x40 >/dev/null; v 0x24 0x400 0x0000 >/dev/null   # test mode off
  v 0x01 0x716 0x09 >/dev/null; v 0x01 0x717 0x01 >/dev/null; v 0x01 0x715 0x00 >/dev/null  # GPIO0 out, low = unmuted
  for n in "$@"; do v $n 0x7f0 0x01 >/dev/null; done
  v 0x1d 0x701 0x00 >/dev/null; v 0x1d 0x707 0x40 >/dev/null   # pin out
}
[ "$(v 0x24 0x500 0x1f >/dev/null; v 0x24 0xc00 0)" = 0x0 ] || { echo "PLL fault already latched (coef 0x1f=0x400): reboot first"; exit 1; }
setup "$@"
echo "gpio data=$(v 0x01 0xf15 0) en=$(v 0x01 0xf16 0) dir=$(v 0x01 0xf17 0); tdm: $(for n in 0x01 0x0a 0x1d 0x24; do printf '%s=%s ' $n $(v $n 0xff0 0); done)"

amixer -q -c $C sset IEC958 on 2>/dev/null
amixer -q -c $C sset Capture 70% cap 2>/dev/null
amixer -q -c $C sset "Mic Boost" 1 2>/dev/null
for ch in ${CHANNELS:-2}; do
  f=$(mktemp --suffix=.wav)
  # NEVER run converter 0x0a at 48 kHz: it latches the codec PLL fault (coef 0x1f=0x400) until reboot.
  ( sleep 0.4; setup "$@"; python3 $HERE/tone.py 1000 1.5 44100 $ch | aplay -q -D hw:$C,1 -f S16_LE -r 44100 -c $ch 2>&1 | head -1 ) &
  arecord -q -D hw:$C,0 -f S16_LE -r 44100 -c2 -d3 "$f" 2>&1 | head -1
  wait
  echo "mic during speaker tone: $(python3 $HERE/tone.py analyze "$f")"
  echo "  $(python3 $HERE/tone.py sweep "$f")"
  cp "$f" /tmp/mb81-last-tone.wav
  echo "0x0a fmt=$(v 0x0a 0xa00 0) digi=$(v 0x0a 0xf0d 0) stream=$(v 0x0a 0xf06 0); 1f=$(v 0x24 0x500 0x1f >/dev/null; v 0x24 0xc00 0)"
  rm -f "$f"
done
f=$(mktemp --suffix=.wav); arecord -q -D hw:$C,0 -f S16_LE -r 44100 -c2 -d2 "$f"; echo "mic quiet: $(python3 $HERE/tone.py analyze "$f")"; rm -f "$f"
