#!/bin/bash
# Dump every CS4208 vendor coefficient 0x00-0xff, normal view and test-mode view
# (coef 0x40 = 0x9999 exposes hidden registers), plus GPIO and key widget state.
# Usage: sudo scripts/cs4208-fulldump.sh > dump.txt      (compare two with diff)
set -u
[ "$(id -u)" = 0 ] || exec sudo "$0" "$@"
HW=$(for h in /sys/class/sound/hwC*D0; do grep -q 0x10134208 $h/vendor_id && echo $h; done | head -1)
H=/dev/snd/$(basename "$HW")
v() { hda-verb $H "$@" 2>/dev/null | grep -o "value = 0x[0-9a-f]*" | cut -d" " -f3; }
rc() { v 0x24 0x500 $1 >/dev/null; v 0x24 0xc00 0; }
wc() { v 0x24 0x500 $1 >/dev/null; v 0x24 0x400 $2 >/dev/null; }
for i in $(seq 0 255); do printf "coef %02x %s\n" $i "$(rc $(printf 0x%x $i))"; done
wc 0x40 0x9999
for i in $(seq 0 255); do printf "tcoef %02x %s\n" $i "$(rc $(printf 0x%x $i))"; done
wc 0x40 0x0000
for p in "0xf15 gpio_data" "0xf16 gpio_en" "0xf17 gpio_dir" "0xf18 gpio_wake" "0xf1a gpio_sticky" "0xf05 afg_pwr" "0xf20 ssid"; do
  set -- $p; printf "afg %s %s\n" $2 "$(v 0x01 $1 0)"
done
for n in 0x0a 0x1d 0x24; do printf "node %s pwr=%s ff0=%s ff1=%s f24=%s\n" $n "$(v $n 0xf05 0)" "$(v $n 0xff0 0)" "$(v $n 0xff1 0)" "$(v $n 0xf24 0)"; done
