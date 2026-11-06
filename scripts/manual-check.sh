#!/bin/bash
# Hands-on checks (MAN-1, AUD-3, USB-1). Run AT the MacBook, in a terminal on its own screen:
#   sudo ~/src/macbook8-1-linux/scripts/manual-check.sh          all steps
#   sudo ~/src/macbook8-1-linux/scripts/manual-check.sh hp       only step 4 (headphones)
#   sudo ~/src/macbook8-1-linux/scripts/manual-check.sh headset  only step 5 (headset mic)
# Each step tells you what to do and, where possible, detects the result itself.
# Results go to /var/lib/mb81-linux/manual-check, which verify.sh reads.
set -u
[ "$(id -u)" = 0 ] || exec sudo "$0" "$@"
HERE=$(cd "$(dirname "$0")" && pwd)
OUT=/var/lib/mb81-linux/manual-check; mkdir -p "$(dirname $OUT)"
declare -A R
ONLY=${1:-all}
step() { [ "$ONLY" = all ] || [ "$ONLY" = "$1" ]; }
# keep earlier results when re-running a single step
[ "$ONLY" != all ] && [ -f $OUT ] && while IFS='=' read -r k v; do [ "$k" != date ] && R[$k]=$v; done < $OUT
ask() { local a; read -r -p "$1 [y/n] " a; [[ $a == [yY]* ]]; }
rec() { R[$1]=$2; printf '  -> %s: %s\n' "$1" "$2"; }
kbd=$(grep -l "Apple SPI Keyboard" /sys/class/input/event*/device/name | head -1 | sed 's|/device/name||; s|.*/||')
tp=$(grep -l "Apple SPI Touchpad" /sys/class/input/event*/device/name | head -1 | sed 's|/device/name||; s|.*/||')

if step fn; then
echo "== 1. Fn row. Press, one after another: F1 F2 (brightness), F5 F6 (keyboard light),"
echo "      F7 F8 F9 (media), F10 F11 F12 (mute/volume). You have 25 seconds."
keys=$(timeout 25 libinput debug-events --device /dev/input/$kbd 2>/dev/null | grep -oE "KEY_[A-Z0-9_]+ \([0-9]+\) pressed" | awk '{print $1}' | sort -u | tr '\n' ' ')
echo "  seen: $keys"
want="KEY_BRIGHTNESSDOWN KEY_BRIGHTNESSUP KEY_KBDILLUMDOWN KEY_KBDILLUMUP KEY_PREVIOUSSONG KEY_PLAYPAUSE KEY_NEXTSONG KEY_MUTE KEY_VOLUMEDOWN KEY_VOLUMEUP"
miss=""; for k in $want; do grep -qw "$k" <<<"$keys" || miss+="$k "; done
[ -z "$miss" ] && rec fn-row ok || rec fn-row "missing: $miss"

fi
if step keys; then
echo "== 2. Every other key: type the alphabet, digits and punctuation in the prompt."
ask "  Did every key you pressed type the right character?" && rec keys ok || rec keys fail

fi
if step tp; then
echo "== 3. Trackpad: click, tap, two-finger scroll, three-finger swipe. 20 seconds."
ev=$(timeout 20 libinput debug-events --device /dev/input/$tp 2>/dev/null | awk '{print $2}' | sort | uniq -c | tr '\n' ' ')
echo "  events: $ev"
for e in POINTER_BUTTON POINTER_SCROLL_FINGER GESTURE_SWIPE_BEGIN; do
  grep -q "$e" <<<"$ev" && rec "tp-$e" ok || rec "tp-$e" "not seen"
done

fi
if step hp; then
echo "== 4. Headphones: plug them in now."
for i in $(seq 1 30); do amixer -c PCH cget iface=CARD,name='Headphone Jack' 2>/dev/null | grep -q "values=on" && break; sleep 1; done
if amixer -c PCH cget iface=CARD,name='Headphone Jack' | grep -q "values=on"; then
  rec hp-detect ok
  ask "  Play a sound on the desktop: is it in the headphones and NOT the speakers?" && rec hp-route ok || rec hp-route fail
else rec hp-detect "jack not detected"; fi

fi
if step headset; then
echo "== 5. Headset mic: plug in a headset with a mic (skip if you have none)."
if ask "  Is a headset with a mic plugged in?"; then
  amixer -c PCH cget iface=CARD,name='Mic Jack' | grep -q "values=on" && rec headset-detect ok || rec headset-detect "not detected"
  f=$(mktemp --suffix=.wav); echo "  Talk into the headset mic for 3 seconds..."
  arecord -q -D hw:PCH,0 -f S16_LE -r 44100 -c2 -d3 "$f"; a=$(python3 "$HERE/tone.py" analyze "$f"); rm -f "$f"
  echo "  $a"; rms=$(sed -n 's/.*rms= *\([0-9.]*\).*/\1/p' <<<"$a")
  awk -v r="$rms" 'BEGIN{exit !(r>200)}' && rec headset-mic ok || rec headset-mic "quiet (rms $rms)"
else rec headset-mic skipped; fi

fi
if step usbc; then
echo "== 6. USB-C display: connect a monitor through a USB-C adapter (skip if none)."
if ask "  Is an external display connected?"; then
  c=$(grep -l "^connected" /sys/class/drm/card*-DP-*/status 2>/dev/null | head -1)
  [ -n "$c" ] && rec usbc-display "ok ($(basename "$(dirname "$c")"))" || rec usbc-display "no DP connector connected"
  ask "  Does the desktop show on it?" && rec usbc-picture ok || rec usbc-picture fail
else rec usbc-display skipped; fi

fi
{ echo "date=$(date -Is)"; for k in "${!R[@]}"; do echo "$k=${R[$k]}"; done | sort; } > $OUT
echo; echo "saved to $OUT"; cat $OUT
