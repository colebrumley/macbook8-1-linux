#!/bin/bash
# Acoustic loopback: 1 kHz on the internal speakers (TDM PCM hw:PCH,1, 4 ch, 44.1 kHz),
# recorded by the internal mic (hw:PCH,0, DMIC1). Proves speakers AND mic.
# Writes /var/lib/mb81-linux/last-audio for verify.sh AUD-1/AUD-2. Makes an audible beep.
# Usage: sudo scripts/test-audio.sh [--keep-servers]
set -uo pipefail
[ "$(id -u)" = 0 ] || exec sudo "$0" "$@"
HERE=$(cd "$(dirname "$0")" && pwd)
OUT=/var/lib/mb81-linux/last-audio; mkdir -p "$(dirname $OUT)"
HW=$(for h in /sys/class/sound/hwC*D0; do grep -q 0x10134208 $h/vendor_id && echo $h; done | head -1)
H=/dev/snd/$(basename "$HW")
v() { hda-verb $H "$@" 2>/dev/null | grep -o "value = 0x[0-9a-f]*" | cut -d" " -f3; }
pll() { v 0x24 0x500 0x1f >/dev/null; v 0x24 0xc00 0; }
servers() { for u in gdm-greeter ${SUDO_USER:-}; do systemctl --user -M "$u@" "$1" pipewire.socket pipewire-pulse.socket wireplumber.service $([ "$1" = stop ] && echo pipewire.service pipewire-pulse.service) >/dev/null 2>&1; done; }
[ "${1:-}" = --keep-servers ] || { servers stop; trap 'servers start' EXIT; sleep 1; }

problems=()
p0=$(pll)   # bit 10 = headset-jack mic bias status (F-10), informational only
aplay -l 2>/dev/null | grep -q "PCH \[HDA Intel PCH\], device 1" || problems+=("no TDM speaker PCM (hw:PCH,1)")

amixer -q -c PCH sset Capture 70% cap 2>/dev/null
amixer -q -c PCH sset "Mic Boost" 1 2>/dev/null
amixer -q -c PCH sset IEC958 on 2>/dev/null

rec() { arecord -q -D hw:PCH,0 -f S16_LE -r 44100 -c2 -d "$1" "$2" 2>/tmp/test-audio.rec.err; }
q=$(mktemp --suffix=.wav); t=$(mktemp --suffix=.wav)
rec 2 "$q"
( sleep 0.4; python3 "$HERE/tone.py" 1000 1.5 44100 4 | aplay -q -D hw:PCH,1 -f S16_LE -r 44100 -c4 2>/tmp/test-audio.play.err ) &
rec 3 "$t"; wait
[ -s /tmp/test-audio.play.err ] && problems+=("aplay: $(head -1 /tmp/test-audio.play.err)")
[ -s /tmp/test-audio.rec.err ] && problems+=("arecord: $(head -1 /tmp/test-audio.rec.err)")

quiet=$(python3 "$HERE/tone.py" analyze "$q" 2>&1); tone=$(python3 "$HERE/tone.py" analyze "$t" 2>&1)
peaks=$(python3 "$HERE/tone.py" sweep "$t" 2>&1)
ratio=$(sed -n 's/.*1kHz= *\([-0-9.]*\)dB.*/\1/p' <<<"$tone")
qrms=$(sed -n 's/.*rms= *\([0-9.]*\).*/\1/p' <<<"$quiet")
p1=$(pll)
awk -v r="${ratio:--99}" 'BEGIN{exit !(r >= 20)}' || problems+=("1 kHz not heard (ratio ${ratio:-?} dB)")
awk -v q="${qrms:-0}" 'BEGIN{exit !(q > 2)}' || problems+=("mic silent when quiet (rms ${qrms:-?})")
rm -f "$q" "$t"

{
  echo "date=$(date -Is)"; echo "kernel=$(uname -r)"
  echo "quiet=$quiet"; echo "tone=$tone"; echo "$peaks"; echo "ratio=$ratio"
  echo "fmt_0a=$(v 0x0a 0xa00 0) gpio=$(v 0x01 0xf15 0) coef1f=$p0/$p1"
  if [ ${#problems[@]} -eq 0 ]; then echo "result=ok"; else echo "result=fail"; printf 'problem=%s\n' "${problems[@]}"; fi
} | tee $OUT
[ ${#problems[@]} -eq 0 ]
