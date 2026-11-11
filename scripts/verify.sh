#!/bin/bash
# macbook8-1-linux acceptance checks. Each check maps to a requirement ID in REQUIREMENTS.md.
# Exit status: 0 if no FAIL. MANUAL checks need a human and never count as PASS.
# Usage: scripts/verify.sh [-v] [ID...]
set -u   # no pipefail: checks pipe into grep -q, which would turn SIGPIPE into false FAILs
VERBOSE=0; [ "${1:-}" = -v ] && { VERBOSE=1; shift; }
ONLY=("$@")
pass=0; fail=0; manual=0
R=$'\e[31m'; G=$'\e[32m'; Y=$'\e[33m'; N=$'\e[0m'
[ -t 1 ] || { R=; G=; Y=; N=; }

want() { [ ${#ONLY[@]} -eq 0 ] && return 0; for i in "${ONLY[@]}"; do [ "$i" = "$1" ] && return 0; done; return 1; }
ok()   { printf "%sPASS%s   %-5s %s\n" "$G" "$N" "$1" "$2"; pass=$((pass+1)); }
bad()  { printf "%sFAIL%s   %-5s %s\n" "$R" "$N" "$1" "$2"; fail=$((fail+1)); }
man()  { printf "%sMANUAL%s %-5s %s\n" "$Y" "$N" "$1" "$2"; manual=$((manual+1)); }
check() { # id description command...
  local id=$1 desc=$2; shift 2
  want "$id" || return 0
  local out; out=$("$@" 2>&1); local rc=$?
  # rc 2 = can't be checked right now (e.g. nobody logged in): report MANUAL, not FAIL
  if [ $rc -eq 0 ]; then ok "$id" "$desc"
  elif [ $rc -eq 2 ]; then man "$id" "$desc${out:+ -- ${out//$'\n'/; }}"
  else bad "$id" "$desc${out:+ -- ${out//$'\n'/; }}"; fi
  [ $VERBOSE = 1 ] && [ -n "$out" ] && echo "$out" | sed 's/^/         /'
}
# Cache the kernel log once. Never pipe a live command into grep -q under pipefail:
# grep exits early, the writer gets SIGPIPE, and the pipeline reports failure.
KLOG=$(sudo journalctl -k -b --no-pager 2>/dev/null)
klog() { printf "%s\n" "$KLOG"; }
input_present() { grep -q "Name=\"$1\"" /proc/bus/input/devices || { echo "no input device '$1'"; return 1; }; }
sysval() { [ -r "$1" ] && cat "$1"; }

# --- input ------------------------------------------------------------------
c_kbd() {
  input_present "Apple SPI Keyboard" || return 1
  local n; n=$(klog | grep -c "SPI transfer timed out"); [ "$n" -eq 0 ] || { echo "$n SPI timeouts this boot"; return 1; }
  klog | grep -q "applespi.*modeswitch done" || { echo "applespi modeswitch not done"; return 1; }
}
c_tp() {
  input_present "Apple SPI Touchpad" || return 1
  sudo libinput list-devices 2>/dev/null | grep -A10 "Apple SPI Touchpad" | grep -q "^Capabilities:.*pointer" || { echo "libinput doesn't see touchpad as pointer"; return 1; }
}
c_kbdlight() {
  local d=/sys/class/leds/spi::kbd_backlight
  [ -d $d ] || { echo "no $d"; return 1; }
  local old; old=$(cat $d/brightness)
  echo 128 | sudo tee $d/brightness >/dev/null; local got; got=$(cat $d/brightness)
  echo "$old" | sudo tee $d/brightness >/dev/null
  [ "$got" = 128 ] || { echo "write 128, read $got"; return 1; }
  # desktop path: UPower KbdBacklight (GNOME slider, Fn+F5/F6)
  gdbus call --system --dest org.freedesktop.UPower --object-path /org/freedesktop/UPower/KbdBacklight \
    --method org.freedesktop.UPower.KbdBacklight.GetMaxBrightness 2>/dev/null | grep -q "255" || { echo "UPower has no keyboard backlight"; return 1; }
}

# --- network ----------------------------------------------------------------
c_wifi() {
  local dev=wlp1s0
  [ -d /sys/class/net/$dev ] || { echo "no $dev"; return 1; }
  [ "$(nmcli -g GENERAL.STATE dev show $dev | cut -d' ' -f1)" = 100 ] || { echo "$dev not connected"; return 1; }
  local gw; gw=$(ip -4 route show dev $dev default | awk '{print $3; exit}')
  [ -n "$gw" ] || gw=$(ip -4 route show dev $dev | awk '/via/{print $3; exit}')
  [ -n "$gw" ] || { echo "no IPv4 gateway on $dev"; return 1; }
  ping -c3 -W2 -I $dev "$gw" >/dev/null || { echo "ping $gw via $dev failed"; return 1; }
  klog | grep -q "DMAR.*fault.*01:00.0" && { echo "IOMMU faults for brcmfmac"; return 1; }
  return 0
}
c_bt() {
  [ -d /sys/class/bluetooth/hci0 ] || { echo "no hci0"; return 1; }
  timeout 10 bluetoothctl show 2>/dev/null | grep -q "Powered: yes" || { echo "hci0 not powered"; return 1; }
  local n; n=$(timeout 25 bluetoothctl --timeout 12 scan on 2>/dev/null | grep -c NEW)
  [ "$n" -gt 0 ] || { echo "scan found nothing"; return 1; }
}
c_btfw() {
  klog | grep -q "BCM: firmware Patch file not found" && { echo "no patchram firmware loaded"; return 1; }
  klog | grep -q "Bluetooth: hci0: BCM.*\.hcd" || { echo "no firmware load message"; return 1; }
}
c_btbaud() {
  # On Macs hci_bcm opens the UART at the ACPI "baud" property (BLTH _DSM: 3,000,000).
  # The chip is already at that speed, so the redundant HCI 0xfc18 "set baud" is rejected
  # (Command Disallowed -> -EBUSY, logged as "failed to write update baudrate (-16)").
  # What matters: the chip answers HCI commands on a 3 Mbaud host link.
  local dsm
  dsm=$(sudo cat /sys/firmware/acpi/tables/DSDT | od -An -tx1 | tr -d ' \n' | grep -o "626175640011..0a08c0c62d00" | head -1)
  [ -n "$dsm" ] || { echo "BLTH baud property is not 3000000 (0x2DC6C0)"; return 1; }
  klog | grep -q "Bluetooth: hci0: BCM: chip id" || { echo "chip never answered on the UART"; return 1; }
  klog | grep -qE "Bluetooth: hci0: .*(tx timeout|Reset failed)" && { echo "HCI timeouts on the UART"; return 1; }
  return 0
}

c_btrec() { systemctl is-enabled --quiet mb81-bt-recover.service || { echo "mb81-bt-recover.service not enabled"; return 1; }; [ -x /usr/lib/systemd/system-sleep/mb81-bt-recover ] || { echo "no resume hook"; return 1; }; }

# --- media ------------------------------------------------------------------
c_audio() {
  # Opening the PCM proves nothing on this codec (F-9). Require a real acoustic loopback:
  # scripts/test-audio.sh plays 1 kHz on the speakers and records it on the internal mic.
  local f=/var/lib/mb81-linux/last-audio
  sudo aplay -l 2>/dev/null | grep -q "\[HDA Intel PCH\].*CS4208" || { echo "no PCH/CS4208 playback device"; return 1; }
  [ -f $f ] || { echo "no loopback result (run scripts/test-audio.sh)"; return 1; }
  grep -q "^result=ok" $f || { echo "loopback: $(grep -E "^(result|ratio)" $f | tr "\n" " ")"; return 1; }
}
c_mic() { c_audio; }
c_sink() {
  # the logged-in desktop session must see the speaker sink, not "Dummy Output" (F-16)
  local uid; uid=$(loginctl list-sessions --no-legend | awk '$4=="seat0" && $2>=1000 {print $2; exit}')
  [ -n "$uid" ] || { echo "no desktop session logged in; log in and re-run"; return 2; }
  sudo -u "#$uid" XDG_RUNTIME_DIR=/run/user/$uid pw-cli ls Node 2>/dev/null | grep -q 'node.name = "macbook_speakers"' \
    || { echo "MacBook Speakers sink missing in the desktop session (Dummy Output)"; return 1; }
}
c_codec() {
  # the CS4208 must have answered the codec probe, and the re-probe service must be armed (F-17)
  grep -qs "CS4208" /proc/asound/card*/codec#* || { echo "CS4208 codec not found (dmesg: no codecs found?); run mb81-audio-recover"; return 1; }
  systemctl is-enabled -q mb81-audio-recover.service || { echo "mb81-audio-recover.service not enabled"; return 1; }
}
c_cam() {
  ls /dev/video* >/dev/null 2>&1 || { echo "no /dev/video*"; return 1; }
  sudo v4l2-ctl --list-devices 2>/dev/null | grep -qi "facetime" || { echo "no FaceTime device in v4l2"; return 1; }
  # root creates the file: fs.protected_regular blocks root writing a user's file in /tmp
  local d f sz; d=$(sudo v4l2-ctl --list-devices | grep -iA1 facetime | tail -1 | tr -d '\t ')
  f=$(sudo mktemp --suffix=.raw)
  sudo timeout 15 v4l2-ctl -d "$d" --stream-mmap --stream-count=5 --stream-to="$f" >/dev/null 2>&1
  sz=$(sudo stat -c %s "$f" 2>/dev/null || echo 0); sudo rm -f "$f"
  [ "$sz" -gt 0 ] || { echo "captured 0 bytes"; return 1; }
}

# --- display / gpu ----------------------------------------------------------
c_gpu() {
  [ -e /dev/dri/renderD128 ] || { echo "no render node"; return 1; }
  klog | grep -qiE "i915.*(GPU HANG|failed)" && { echo "i915 errors"; return 1; }
  sudo vainfo --display drm --device /dev/dri/renderD128 2>/dev/null | grep -q VAProfileH264 || { echo "no VA-API H264"; return 1; }
}
c_backlight() {
  # GNOME's gsd-power (ambient light) re-adjusts brightness ~100 ms after any write, so
  # don't assert the value we wrote. Assert the hardware: the panel PWM duty cycle
  # (BLC_PWM_PCH_CTL2, 0xC8254: period<<16 | duty) must match actual_brightness.
  local b; b=$(ls -d /sys/class/backlight/* 2>/dev/null | head -1)
  [ -n "$b" ] || { echo "no backlight device"; return 1; }
  # a blanked screen (GNOME idle) has the panel off and PWM at 0: wake it first
  local edp; edp=$(ls -d /sys/class/drm/card*-eDP-* 2>/dev/null | head -1)
  if [ -n "$edp" ] && [ "$(cat "$edp/dpms")" != On ]; then
    local uid; uid=$(loginctl list-sessions --no-legend | awk '$4=="seat0"{print $2; exit}')
    [ -n "$uid" ] && sudo -u "#$uid" env XDG_RUNTIME_DIR=/run/user/$uid DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/$uid/bus \
      gdbus call --session --dest org.gnome.ScreenSaver --object-path /org/gnome/ScreenSaver \
      --method org.gnome.ScreenSaver.SetActive false >/dev/null 2>&1
    sleep 2
    [ "$(cat "$edp/dpms")" = On ] || { echo "internal panel is off (lid closed or display disabled); can't test"; return 1; }
  fi
  local max old; max=$(cat "$b/max_brightness"); old=$(cat "$b/brightness")
  local v a r p d pct want rc=0
  for v in $((max/5)) $((max*7/10)); do
    echo $v | sudo tee "$b/brightness" >/dev/null; sleep 0.6
    a=$(cat "$b/actual_brightness")
    r=$(sudo intel_reg read 0xc8254 2>/dev/null | grep -o "0x[0-9a-f]*$"); [ -n "$r" ] || { echo "intel_reg unavailable"; rc=1; break; }
    p=$(( (r>>16) & 0xffff )); d=$(( r & 0xffff )); [ $p -gt 0 ] || { echo "PWM period 0"; rc=1; break; }
    pct=$((100*d/p)); want=$((100*a/max))
    [ $((pct-want)) -le 5 ] && [ $((want-pct)) -le 5 ] || { echo "actual=$a/$max but PWM duty ${pct}%"; rc=1; }
  done
  echo "$old" | sudo tee "$b/brightness" >/dev/null
  return $rc
}
c_als() {
  [ -r /sys/devices/platform/applesmc.768/light ] || { echo "no applesmc light"; return 1; }
  # iio-sensor-proxy's hwmon-als backend reads applesmc "light"; GNOME auto-brightness uses it
  gdbus introspect --system --dest net.hadess.SensorProxy --object-path /net/hadess/SensorProxy --only-properties 2>/dev/null \
    | grep -q "HasAmbientLight = true" || { echo "iio-sensor-proxy has no ambient light"; return 1; }
}

# --- power ------------------------------------------------------------------
c_batt() {
  [ "$(sysval /sys/class/power_supply/BAT0/present)" = 1 ] || { echo "no battery"; return 1; }
  [ -n "$(sysval /sys/class/power_supply/BAT0/capacity)" ] || { echo "no capacity"; return 1; }
  [ -n "$(sysval /sys/class/power_supply/ADP1/online)" ] || { echo "no AC adapter status"; return 1; }
}
c_sensors() {
  sensors 2>/dev/null | grep -q "applesmc" || { echo "no applesmc sensors"; return 1; }
  sensors 2>/dev/null | grep -q "coretemp\|Package id" || { echo "no coretemp"; return 1; }
  systemctl is-active --quiet thermald || { echo "thermald not active"; return 1; }
}
c_suspend() {
  # last suspend cycle recorded by scripts/test-suspend.sh
  local f=/var/lib/mb81-linux/last-suspend
  [ -f $f ] || { echo "never tested (run scripts/test-suspend.sh)"; return 1; }
  grep -q "^result=ok" $f || { echo "$(cat $f | tr '\n' ' ')"; return 1; }
  grep -q "^kernel=$(uname -r)$" $f || { echo "last test was on another kernel"; return 1; }
  grep -q "^audio=1$" $f || { echo "last test did not include the after-resume audio loopback (AUDIO=1)"; return 1; }
}
c_lid() { input_present "Lid Switch"; }
c_nvme() {
  [ -e /dev/nvme0n1 ] || { echo "no nvme0n1"; return 1; }
  # judge the current state: only look at the log since the last resume (or boot)
  local since; since=$(klog | grep -n "PM: suspend exit" | tail -1 | cut -d: -f1); since=${since:-1}
  klog | tail -n +"$since" | grep -qiE "nvme.*(timeout|reset controller)" && { echo "nvme timeouts since last resume/boot"; return 1; }
  return 0
}

# --- run ----------------------------------------------------------------------
echo "macbook8-1-linux verify  $(date -Is)  kernel $(uname -r)"
check KBD-1 "internal keyboard (applespi) works, no SPI timeouts" c_kbd
check KBD-2 "keyboard backlight controllable"                    c_kbdlight
check TP-1  "trackpad present and seen by libinput"              c_tp
check NET-1 "internal Wi-Fi (brcmfmac) connected and passing traffic" c_wifi
check BT-1  "Bluetooth controller up and scanning"               c_bt
check BT-2  "Bluetooth UART link at 3 Mbaud"                     c_btbaud
want BT-3 && man BT-3 "patchram: n/a, no BCM4350C0 patch exists (FINDINGS F-12)"
check BT-4  "Bluetooth auto-recovery installed (mb81-bt-recover)" c_btrec
check AUD-1 "speakers/headphone playback device works"           c_audio
check AUD-2 "internal microphone records"                        c_mic
check AUD-4 "desktop session has the MacBook Speakers sink"     c_sink
check AUD-5 "speaker codec present, re-probe service armed"      c_codec
check CAM-1 "FaceTime HD camera captures frames"                 c_cam
check GPU-1 "i915 render + VA-API decode"                        c_gpu
check DSP-1 "display backlight control"                          c_backlight
check DSP-2 "ambient light sensor drives brightness"             c_als
check PWR-1 "battery and AC status"                              c_batt
check PWR-2 "thermal sensors and thermald"                       c_sensors
check PWR-3 "suspend/resume round trip incl. speakers after resume" c_suspend
check PWR-4 "lid switch"                                          c_lid
check STO-1 "NVMe healthy"                                        c_nvme
c_manual() {
  local f=/var/lib/mb81-linux/manual-check
  [ -f $f ] || { echo "not done yet: run scripts/manual-check.sh at the machine"; return 2; }
  local bad; bad=$(grep -vE "^date=|=ok|=skipped" $f | tr '\n' ' ')
  [ -z "$bad" ] || { echo "$bad"; return 1; }
}
if want MAN-1; then
  out=$(c_manual); rc=$?
  case $rc in 0) ok MAN-1 "hands-on checks (scripts/manual-check.sh)";; 2) man MAN-1 "$out";; *) bad MAN-1 "hands-on: $out";; esac
fi

echo "---"
echo "pass=$pass fail=$fail manual=$manual"
[ $fail -eq 0 ]
