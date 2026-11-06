#!/bin/bash
# After deep S3 (speakers silent): try GPIO2 as the amp reset/shutdown line, as the EFI
# chime table suggests (pin 0x1d records: GPIO0=1, GPIO2=0). Each variant is followed by
# a quiet loopback. Audible. Usage: sudo scripts/mb81-amp-gpio2-probe.sh
set -uo pipefail
[ "$(id -u)" = 0 ] || exec sudo "$0" "$@"
HERE=$(cd "$(dirname "$0")" && pwd)
HW=$(for h in /sys/class/sound/hwC*D0; do grep -q 0x10134208 $h/vendor_id && echo $h; done | head -1)
H=/dev/snd/$(basename "$HW")
P=/sys/module/snd_hda_codec_cs420x/parameters
v() { hda-verb $H "$@" >/dev/null 2>&1; }
gp() { v 0x01 0x716 $1; v 0x01 0x717 $2; v 0x01 0x715 $3; }   # enable dir data
t() { printf "%-40s " "$1"; "$HERE/test-audio.sh" --keep-servers 2>&1 | grep -E "^ratio"; }
for u in gdm-greeter ${SUDO_USER:-}; do systemctl --user -M "$u@" stop pipewire.socket pipewire-pulse.socket pipewire.service pipewire-pulse.service wireplumber.service >/dev/null 2>&1; done
trap 'echo 0 > $P/mb81_rail_mask; for u in gdm-greeter ${SUDO_USER:-}; do systemctl --user -M "$u@" start pipewire.socket pipewire-pulse.socket wireplumber.service >/dev/null 2>&1; done' EXIT

t "0. as-is (after S3)"
echo 0x04 > $P/mb81_rail_mask; echo 0x00 > $P/mb81_rail_data
t "1. GPIO2 held low"
gp 0x0d 0x05 0x04; sleep 0.05; gp 0x0d 0x05 0x00; sleep 0.05
t "2. GPIO2 pulse high->low (50 ms)"
echo 0x04 > $P/mb81_rail_data
gp 0x0d 0x05 0x00; sleep 0.05; gp 0x0d 0x05 0x04; sleep 0.05
t "3. GPIO2 pulse low->high, held high"
echo 0x00 > $P/mb81_rail_data
gp 0x0d 0x05 0x00; sleep 0.2
gp 0x0c 0x04 0x00; sleep 0.2      # GPIO0 (amp enable) off while GPIO2 low
gp 0x0d 0x05 0x01; sleep 0.1
t "4. amp-enable off/on with GPIO2 low"
