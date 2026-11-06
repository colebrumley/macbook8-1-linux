#!/bin/bash
# Find which CS4208 pin carries the real internal microphone, by acoustic loopback.
# For each candidate pin: make it the only internal mic (other mic pins N/A), reconfigure
# the codec, record 2 s quiet and 2 s while the speakers play a 1 kHz tone.
# A real mic shows a large 1 kHz ratio (>20 dB) in the tone run and ~0 dB when quiet.
# The tone run also proves the speakers work.
#
# Audio servers must not hold the card (reconfig needs it closed). This script stops
# PipeWire/WirePlumber for gdm-greeter and the caller, and restarts them at the end.
# Usage: sudo scripts/mic-probe.sh [hwCxD0]
set -uo pipefail
[ "$(id -u)" = 0 ] || exec sudo "$0" "$@"
HERE=$(cd "$(dirname "$0")" && pwd)
HW=/sys/class/sound/${1:-$(cd /sys/class/sound && for h in hwC*D0; do grep -q 0x10134208 $h/vendor_id && echo $h; done | head -1)}
CARD=$(basename "$HW" | sed -E 's/hwC([0-9]+)D.*/\1/')
MICS=(${MICS:-0x15 0x16 0x19 0x1a 0x1b 0x1c})
NA=0x411111f0
INT_MIC=0x90a00030

audio_servers() { # stop|start
  local units="pipewire.socket pipewire-pulse.socket pipewire.service pipewire-pulse.service wireplumber.service"
  [ "$1" = start ] && units="pipewire.socket pipewire-pulse.socket wireplumber.service"
  for u in gdm-greeter ${SUDO_USER:-}; do
    [ -n "$u" ] && systemctl --user -M "$u@" "$1" $units >/dev/null 2>&1
  done
}
reconfig() { echo 1 > "$HW/reconfig" || echo "reconfig failed (card busy?)" >&2; sleep 1; }
measure() { # [tone]
  local f; f=$(mktemp --suffix=.wav)
  if [ "${1:-}" = tone ]; then
    ( sleep 0.3; python3 "$HERE/tone.py" 1000 1.2 | aplay -q -D "plughw:$CARD,0" -f S16_LE -r 48000 -c2 ) &
  fi
  arecord -q -D "plughw:$CARD,0" -f S16_LE -r 48000 -c2 -d2 "$f" 2>/dev/null || { echo "arecord failed"; rm -f "$f"; wait; return; }
  wait
  python3 "$HERE/tone.py" analyze "$f"
  rm -f "$f"
}

trap 'audio_servers start' EXIT
audio_servers stop; sleep 1

orig=$(cat "$HW/user_pin_configs")
echo "card $CARD ($HW)"
for pin in "${MICS[@]}"; do
  for m in "${MICS[@]}"; do
    if [ "$m" = "$pin" ]; then echo "$m $INT_MIC"; else echo "$m $NA"; fi > "$HW/user_pin_configs"
  done
  echo "0x18 $NA" > "$HW/user_pin_configs"   # keep the headset mic out of auto-mic switching
  reconfig
  amixer -q -c "$CARD" sset Capture 50% cap 2>/dev/null
  amixer -q -c "$CARD" sset "Mic Boost" 0 2>/dev/null
  amixer -q -c "$CARD" sset Speaker 60% unmute 2>/dev/null
  printf "pin %s: quiet [%s]  tone [%s]\n" "$pin" "$(measure)" "$(measure tone)"
done

# restore the driver's own pin config
for m in "${MICS[@]}" 0x18; do
  v=$(awk -v n="$m" '$1==n{print $2}' "$HW/init_pin_configs"); echo "$m $v" > "$HW/user_pin_configs"
done
[ -n "$orig" ] && while read -r n v; do echo "$n $v" > "$HW/user_pin_configs"; done <<<"$orig"
reconfig
echo "restored"
