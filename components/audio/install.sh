#!/bin/bash
# CS4208 MacBook8,1 fixup (speakers over TDM, DMIC1 internal mic). See patch_mb81.py.
set -euo pipefail
cd "$(dirname "$0")"
NAME=cs4208-mb81
VER=$(sed -n 's/^PACKAGE_VERSION="\(.*\)"/\1/p' dkms.conf)
SRC=/usr/src/$NAME-$VER
KTAG="v$(uname -r | cut -d. -f1-2)"
BASE=https://git.kernel.org/pub/scm/linux/kernel/git/torvalds/linux.git/plain/sound/hda
FILES=(codecs/cirrus/cs420x.c codecs/generic.h common/hda_local.h common/hda_auto_parser.h common/hda_jack.h)

for f in "${FILES[@]}"; do
  [ -f "upstream/$KTAG/$f" ] || { mkdir -p "upstream/$KTAG/$(dirname "$f")"; curl -fsSL -o "upstream/$KTAG/$f" "$BASE/$f?h=$KTAG"; }
done

work=$(mktemp -d); trap 'rm -rf "$work"' EXIT
cp -r upstream/$KTAG/. "$work/"
python3 patch_mb81.py "$work/codecs/cirrus/cs420x.c"
diff -u upstream/$KTAG/codecs/cirrus/cs420x.c "$work/codecs/cirrus/cs420x.c" \
  --label a/sound/hda/codecs/cirrus/cs420x.c --label b/sound/hda/codecs/cirrus/cs420x.c > macbook81-cs4208.patch || true

for v in $(dkms status -m $NAME 2>/dev/null | sed -n "s|^$NAME/\([^,:]*\)[,:].*|\1|p" | sort -u); do
  dkms remove -m $NAME -v "$v" --all || true; rm -rf "/usr/src/$NAME-$v"
done
mkdir -p "$SRC"; cp -r "$work"/. "$SRC/"; cp dkms.conf "$SRC/"
cat > "$SRC/Makefile" <<'MK'
obj-m := snd-hda-codec-cs420x.o
snd-hda-codec-cs420x-y := codecs/cirrus/cs420x.o
ccflags-y += -I$(src)/common
MK
dkms add -m $NAME -v "$VER"
dkms install -m $NAME -v "$VER"
install -m 0644 mb81-audio.conf /etc/modprobe.d/mb81-audio.conf
install -D -m 0644 pipewire/60-macbook81-speakers.conf /etc/pipewire/pipewire.conf.d/60-macbook81-speakers.conf
echo "audio: snd-hda-codec-cs420x -> $(modinfo -n snd_hda_codec_cs420x)"

# remove the obsolete forced-profile rule from earlier versions
rm -f /etc/wireplumber/wireplumber.conf.d/60-macbook81-pch.conf
