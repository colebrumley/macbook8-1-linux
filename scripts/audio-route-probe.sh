#!/bin/bash
# Acoustic loopback matrix for the CS4208: which output pin really drives the speakers
# and which input pin really carries the internal mic?
# For every (out, in) pair: remap pins so that only `out` is the speaker and only `in`
# is the internal mic, reconfigure, then play 1 kHz and record. A working pair shows
# a 1 kHz ratio well above 20 dB. Makes audible beeps.
# Usage: sudo scripts/audio-route-probe.sh
set -uo pipefail
[ "$(id -u)" = 0 ] || exec sudo "$0" "$@"
HERE=$(cd "$(dirname "$0")" && pwd)
HW=/sys/class/sound/$(cd /sys/class/sound && for h in hwC*D0; do grep -q 0x10134208 $h/vendor_id && echo $h; done | head -1)
CARD=$(basename "$HW" | sed -E 's/hwC([0-9]+)D.*/\1/')
OUTS=(${OUTS:-0x12 0x1d})
INS=(${INS:-0x19 0x1a 0x1b 0x1c 0x1f 0x20})
ALLPINS="0x11 0x12 0x13 0x14 0x15 0x16 0x17 0x18 0x19 0x1a 0x1b 0x1c 0x1d 0x1e 0x1f 0x20"
NA=0x411111f0
SPK_ANALOG=0x90170010; SPK_DIGITAL=0x90160010
MIC_ANALOG=0x90a00030; MIC_DIGITAL=0x90a60030

audio_servers() {
  local units="pipewire.socket pipewire-pulse.socket pipewire.service pipewire-pulse.service wireplumber.service"
  [ "$1" = start ] && units="pipewire.socket pipewire-pulse.socket wireplumber.service"
  for u in gdm-greeter ${SUDO_USER:-}; do systemctl --user -M "$u@" "$1" $units >/dev/null 2>&1; done
}
restore() {
  for n in $ALLPINS; do echo "$n $(awk -v n=$n '$1==n{print $2}' "$HW/init_pin_configs")" > "$HW/user_pin_configs"; done
  echo 1 > "$HW/reconfig"; audio_servers start
}
trap restore EXIT
audio_servers stop; sleep 1

echo "card $CARD; HP pin 0x10 left as-is"
for out in "${OUTS[@]}"; do
  for in in "${INS[@]}"; do
    for n in $ALLPINS; do echo "$n $NA" > "$HW/user_pin_configs"; done
    case $out in 0x1d|0x1e) v=$SPK_DIGITAL;; *) v=$SPK_ANALOG;; esac; echo "$out $v" > "$HW/user_pin_configs"
    case $in  in 0x1f|0x20) v=$MIC_DIGITAL;; *) v=$MIC_ANALOG;; esac; echo "$in $v"  > "$HW/user_pin_configs"
    echo 1 > "$HW/reconfig" 2>/dev/null || { echo "out $out in $in: reconfig failed"; continue; }
    sleep 1
    amixer -q -c "$CARD" sset Capture 60% cap 2>/dev/null
    amixer -q -c "$CARD" sset Speaker 70% unmute 2>/dev/null
    amixer -q -c "$CARD" sset PCM 90% unmute 2>/dev/null
    amixer -q -c "$CARD" sset Master 80% unmute 2>/dev/null
    f=$(mktemp --suffix=.wav)
    ( sleep 0.3; python3 "$HERE/tone.py" 1000 1.2 | aplay -q -D "plughw:$CARD,0" -f S16_LE -r 48000 -c2 2>/tmp/aplay.err ) &
    arecord -q -D "plughw:$CARD,0" -f S16_LE -r 48000 -c2 -d2 "$f" 2>/tmp/arecord.err
    wait
    res=$(python3 "$HERE/tone.py" analyze "$f" 2>&1)
    printf "out %s in %s: %s %s\n" "$out" "$in" "$res" "$(head -c 80 /tmp/aplay.err /tmp/arecord.err 2>/dev/null | tr '\n' ' ')"
    rm -f "$f"
  done
done
