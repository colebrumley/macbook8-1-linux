#!/bin/bash
# Run right after a deep-S3 resume, BEFORE any speaker playback: start the TDM stream with
# the amp disabled, let the clocks run, then enable the amp (GPIO0) mid-stream, as Apple's
# chime path does (stream first, unmute after AmpPreDelay). Records the internal mic.
# Audible, quiet. Usage: sudo scripts/mb81-amp-order-probe.sh
set -uo pipefail
[ "$(id -u)" = 0 ] || exec sudo "$0" "$@"
HERE=$(cd "$(dirname "$0")" && pwd)
HW=$(for h in /sys/class/sound/hwC*D0; do grep -q 0x10134208 $h/vendor_id && echo $h; done | head -1)
H=/dev/snd/$(basename "$HW"); P=/sys/module/snd_hda_codec_cs420x/parameters
v() { hda-verb $H "$@" >/dev/null 2>&1; }
for u in gdm-greeter ${SUDO_USER:-}; do systemctl --user -M "$u@" stop pipewire.socket pipewire-pulse.socket pipewire.service pipewire-pulse.service wireplumber.service >/dev/null 2>&1; done
trap 'echo N > $P/mb81_amp_manual; for u in gdm-greeter ${SUDO_USER:-}; do systemctl --user -M "$u@" start pipewire.socket pipewire-pulse.socket wireplumber.service >/dev/null 2>&1; done' EXIT
amixer -q -c PCH sset Capture 70% cap 2>/dev/null; amixer -q -c PCH sset "Mic Boost" 1 2>/dev/null
echo Y > $P/mb81_amp_manual
v 0x01 0x716 0x09; v 0x01 0x717 0x01; v 0x01 0x715 0x00      # amp off
for delay in 0.5 1.5; do
  f=$(mktemp --suffix=.wav)
  arecord -q -D hw:PCH,0 -f S16_LE -r 44100 -c2 -d4 "$f" &
  python3 "$HERE/tone.py" 1000 3.5 44100 4 | aplay -q -D hw:PCH,1 -f S16_LE -r 44100 -c4 &
  sleep "$delay"; v 0x01 0x715 0x01                           # amp on, clocks already running
  wait
  v 0x01 0x715 0x00
  printf "enable %ss after stream start: %s\n" "$delay" "$(python3 "$HERE/tone.py" analyze "$f")"
  rm -f "$f"
done
