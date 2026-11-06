#!/bin/bash
# After S3 the MacBook8,1 speaker amp is silent. Try candidate amp bring-up steps, one at a
# time, each followed by a quiet acoustic loopback (scripts/test-audio.sh). Audible.
# Usage: sudo scripts/mb81-amp-recover.sh
set -uo pipefail
[ "$(id -u)" = 0 ] || exec sudo "$0" "$@"
HERE=$(cd "$(dirname "$0")" && pwd)
HW=$(for h in /sys/class/sound/hwC*D0; do grep -q 0x10134208 $h/vendor_id && echo $h; done | head -1)
H=/dev/snd/$(basename "$HW")
v() { hda-verb $H "$@" 2>/dev/null | grep -o "value = 0x[0-9a-f]*" | cut -d" " -f3; }
cg() { v 0x24 0x500 $1 >/dev/null; v 0x24 0xc00 0; }
cs() { v 0x24 0x500 $1 >/dev/null; v 0x24 0x400 $2 >/dev/null; }
t() { printf "%-46s " "$1"; "$HERE/test-audio.sh" --keep-servers 2>&1 | grep -E "^ratio" | tr '\n' ' '; echo; }

for u in gdm-greeter ${SUDO_USER:-}; do systemctl --user -M "$u@" stop pipewire.socket pipewire-pulse.socket pipewire.service pipewire-pulse.service wireplumber.service >/dev/null 2>&1; done
trap 'for u in gdm-greeter ${SUDO_USER:-}; do systemctl --user -M "$u@" start pipewire.socket pipewire-pulse.socket wireplumber.service >/dev/null 2>&1; done' EXIT

echo "state: gpio data=$(v 0x01 0xf15 0) en=$(v 0x01 0xf16 0) dir=$(v 0x01 0xf17 0) coef00=$(cg 0x00)"
t "0. as-is"

# 1. DFET rails: GPIO4/5 as outputs, driven low (= rails on); GPIO0 left to the driver
v 0x01 0x716 0x39 >/dev/null; v 0x01 0x717 0x31 >/dev/null; v 0x01 0x715 0x00 >/dev/null
sleep 0.1
t "1. GPIO4/5 out low (DFET rails on)"

# 2. charge pump enable: coef 0x00 bit 14
c=$(cg 0x00); cs 0x00 $(printf 0x%x $(( c | 0x4000 ))); sleep 0.01
t "2. + charge pump (coef00 |= 0x4000)"

# 3. full DFET power-up sequence as in the reference driver: rails off, then on
v 0x01 0x715 0x30 >/dev/null; sleep 0.05; v 0x01 0x715 0x10 >/dev/null; sleep 0.05; v 0x01 0x715 0x00 >/dev/null; sleep 0.1
t "3. + DFET off->on sequence"
echo "final: gpio data=$(v 0x01 0xf15 0) en=$(v 0x01 0xf16 0) dir=$(v 0x01 0xf17 0) coef00=$(cg 0x00)"
