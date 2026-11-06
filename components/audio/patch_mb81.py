"""Add a MacBook8,1 (codec SSID 106b:6400) fixup to the CS4208 driver (sound/hda/codecs/cirrus/cs420x.c).

Speakers on this machine are NOT on the analog DACs: converter 0x0a drives pin 0x1d, a
4-slot TDM link to the class-D amp. The internal mic is DMIC1 on pin 0x19.
Verified by acoustic loopback (scripts/test-audio.sh): 1 kHz on hw:PCH,1 is recorded by
the internal mic at +61 dB over neighbouring bins with GPIO0 high, room noise with it low.
Findings (docs/FINDINGS.md F-9) that shape this fixup:
  * GPIO0 is the class-D amp ENABLE, active high. EFI parks it low after the chime. The
    stock driver drives it high but never enables the TDM converter, so it is silent too.
  * Running converter 0x0a at 48 kHz latches the codec PLL fault (coef 0x1f = 0x400) until
    a power cycle. The TDM PCM is therefore locked to 44.1 kHz / 4 ch / S16, and the
    "IEC958 Default PCM" share switch (which clones the analog stream format onto 0x0a)
    is forced off.
  * The stock init rewrites coefs 0x33/0x34 and leaves 0x00/0x03-0x05/0x36 at reset values;
    the EFI image (captured with scripts/hda-imm.py, components/audio/efi-codec-state.json)
    is rewritten on every init, which also runs on resume.

usage: patch_mb81.py cs420x.c
"""
import sys

p = sys.argv[1]
s = open(p).read()


def sub(old, new, count=1):
    global s
    assert s.count(old) == count, f"anchor found {s.count(old)}x (want {count}): {old[:60]!r}"
    s = s.replace(old, new)


# 1. enum / model name / codec-SSID quirk
sub("\tCS4208_GPIO0,\n};", "\tCS4208_GPIO0,\n\tCS4208_MB81,\n};")
sub('\t{ .id = CS4208_GPIO0, .name = "gpio0" },\n',
    '\t{ .id = CS4208_GPIO0, .name = "gpio0" },\n\t{ .id = CS4208_MB81, .name = "mb81" },\n')
sub('\tSND_PCI_QUIRK(0x106b, 0x5e00, "MacBookPro 11,2", CS4208_MBP11),\n',
    '\tSND_PCI_QUIRK(0x106b, 0x5e00, "MacBookPro 11,2", CS4208_MBP11),\n'
    '\t/* codec SSID: must precede the 8086:7270 PCI-SSID entry, which this machine also matches */\n'
    '\tHDA_CODEC_QUIRK(0x106b, 0x6400, "MacBook 8,1", CS4208_MB81),\n')

# 1b. DMI selection. The codec SSID (106b:6400) is programmed into the codec by EFI and
#     reads back as the chip default 0x10134208 after any codec reset (driver reload,
#     resume); the PCI SSID 8086:7270 is shared with the MacBookAir7,2. DMI is reliable.
sub("#include \"../generic.h\"\n", "#include \"../generic.h\"\n#include <linux/delay.h>\n#include <linux/dmi.h>\n")
sub("\tcodec->fixup_id = HDA_FIXUP_ID_NOT_SET;\n\tsnd_hda_pick_fixup(codec, NULL, cs4208_mac_fixup_tbl, cs4208_fixups);\n",
    "\tcodec->fixup_id = HDA_FIXUP_ID_NOT_SET;\n"
    "\tif (dmi_match(DMI_SYS_VENDOR, \"Apple Inc.\") && dmi_match(DMI_PRODUCT_NAME, \"MacBook8,1\"))\n"
    "\t\tcodec->fixup_id = CS4208_MB81;\n"
    "\telse\n"
    "\t\tsnd_hda_pick_fixup(codec, NULL, cs4208_mac_fixup_tbl, cs4208_fixups);\n")

# 2. the fixup implementation, inserted before the fixup table
impl = r'''
/*
 * MacBook8,1: speakers via TDM (DAC 0x0a -> pin 0x1d), GPIO0 = amp mute (active high)
 */
#define MB81_TDM_NID		0x0a
#define MB81_TDM_PIN		0x1d
#define MB81_HP_PIN		0x10
#define MB81_GPIO_AMP_EN	0x01	/* GPIO0: class-D amp enable, active high */
#define MB81_GPIO_MASK		0x09	/* as left by EFI: GPIO0 (amp enable) + GPIO3 (status, input) */
#define MB81_AMP_PRE_DELAY_MS	75	/* Apple layout: AmpPreDelay */
#define MB81_VERB_SET_TDM_EN	0x7f0	/* vendor verb on NID 0x24; reads back via 0xff0 */

/*
 * Every pin explicitly: EFI programs the pin defaults at boot, but any codec reset
 * (driver reload, some resume paths) brings back chip defaults that make the parser
 * bring up stray inputs. Only DMIC1 (internal) and the headset-jack mic are inputs.
 */
static const struct hda_pintbl mb81_pincfgs[] = {
	{ 0x10, 0x032b401f },	/* HP out jack (EFI value) */
	{ 0x11, 0x411111f0 },	/* analog speaker pins: not connected on this board */
	{ 0x12, 0x411111f0 },
	{ 0x13, 0x411111f0 },
	{ 0x14, 0x411111f0 },
	{ 0x15, 0x411111f0 },
	{ 0x16, 0x411111f0 },
	{ 0x17, 0x411111f0 },
	{ 0x18, 0x03ab4057 },	/* headset-jack mic (EFI value); its bias sets coef 0x1f bit 10, harmless (F-10) */
	{ 0x19, 0x90a00070 },	/* DMIC1: internal mic */
	{ 0x1a, 0x411111f0 },
	{ 0x1b, 0x411111f0 },
	{ 0x1c, 0x411111f0 },
	{ 0x1d, 0x90400010 },	/* TDM speaker link: internal, fixed, digital out */
	{ 0x1e, 0x411111f0 },
	{ 0x1f, 0x411111f0 },
	{ 0x20, 0x411111f0 },
	{ 0x21, 0x411111f0 },
	{ 0x22, 0x411111f0 },
	{ }
};

/* EFI codec state (vendor coefs on NID 0x24), minus status reg 0x1f */
static const unsigned short mb81_efi_coefs[][2] = {
	{ 0x00, 0x00c4 }, { 0x02, 0x003a }, { 0x03, 0x0baa }, { 0x04, 0x0c04 },
	{ 0x05, 0x1000 }, { 0x06, 0x9f9f }, { 0x07, 0x9f9f }, { 0x08, 0x1f1f },
	{ 0x09, 0x1f1f }, { 0x0a, 0x1f1f }, { 0x0b, 0x1f1f }, { 0x0c, 0x9f9f },
	{ 0x0d, 0x9f9f }, { 0x0e, 0x9f9f }, { 0x0f, 0x9f9f }, { 0x10, 0x1f1f },
	{ 0x11, 0x1f1f }, { 0x12, 0x1f1f }, { 0x13, 0x1f1f }, { 0x18, 0x0400 },
	{ 0x19, 0x0088 }, { 0x1a, 0x00f3 }, { 0x1b, 0x0002 }, { 0x1c, 0x0103 },
	{ 0x1d, 0x0bdf }, { 0x1e, 0x016d }, { 0x22, 0x0080 }, { 0x25, 0x0001 },
	{ 0x33, 0x0821 }, { 0x34, 0x3b21 }, { 0x36, 0x0034 },
};

static const struct hda_pcm_stream mb81_tdm_playback = {
	.substreams = 1,
	.channels_min = 4,
	.channels_max = 4,
	.rates = SNDRV_PCM_RATE_44100,	/* 48 kHz on 0x0a latches the PLL fault */
	.formats = SNDRV_PCM_FMTBIT_S16_LE,
	.maxbps = 16,
};

static void mb81_write_efi_coefs(struct hda_codec *codec)
{
	int i;

	snd_hda_codec_write(codec, CS4208_VENDOR_NID, 0, AC_VERB_SET_PROC_STATE, 1);
	for (i = 0; i < ARRAY_SIZE(mb81_efi_coefs); i++)
		cs_vendor_coef_set(codec, mb81_efi_coefs[i][0], mb81_efi_coefs[i][1]);
}

/*
 * GPIO4/GPIO5 switch the amp's supply rails (Apple layout: "CH DFET", "US DFET").
 * EFI leaves them as inputs (external pulls keep the rails up). Experimental control
 * for bringing the amp back after deep S3, see FINDINGS F-14.
 */
static unsigned int mb81_rail_mask;	/* which of GPIO4/5 (0x30) the driver drives */
module_param(mb81_rail_mask, uint, 0644);
MODULE_PARM_DESC(mb81_rail_mask, "MacBook8,1: codec GPIOs (amp rails) to drive as outputs (0 = leave as inputs)");
static unsigned int mb81_rail_data;
module_param(mb81_rail_data, uint, 0644);
MODULE_PARM_DESC(mb81_rail_data, "MacBook8,1: level for the driven amp-rail GPIOs");

static bool mb81_amp_manual;	/* experiment: never drive GPIO0, leave it to the user */
module_param(mb81_amp_manual, bool, 0644);
MODULE_PARM_DESC(mb81_amp_manual, "MacBook8,1: don't drive the amp-enable GPIO (experiments only)");

/* amp on only while the speaker PCM runs and no headphone is plugged in */
static bool mb81_update_amp(struct hda_codec *codec)
{
	struct cs_spec *spec = codec->spec;
	bool on = spec->mb81_playing && !snd_hda_jack_detect(codec, MB81_HP_PIN);

	if (mb81_amp_manual)
		return false;
	bool was = spec->gpio_data & MB81_GPIO_AMP_EN;
	unsigned int rails = mb81_rail_mask & 0x36;	/* GPIO1, GPIO2, GPIO4, GPIO5 */

	spec->gpio_mask = MB81_GPIO_MASK | rails;
	spec->gpio_dir = MB81_GPIO_AMP_EN | rails;
	spec->gpio_data = (on ? MB81_GPIO_AMP_EN : 0) | (mb81_rail_data & rails);
	snd_hda_codec_write(codec, 0x01, 0, AC_VERB_SET_GPIO_MASK, spec->gpio_mask);
	snd_hda_codec_write(codec, 0x01, 0, AC_VERB_SET_GPIO_DIRECTION, spec->gpio_dir);
	snd_hda_codec_write(codec, 0x01, 0, AC_VERB_SET_GPIO_DATA, spec->gpio_data);
	return on && !was;
}

static void mb81_automute(struct hda_codec *codec)
{
	snd_hda_gen_update_outputs(codec);
	mb81_update_amp(codec);
}

static int mb81_tdm_prepare(struct hda_pcm_stream *hinfo, struct hda_codec *codec,
			    unsigned int stream_tag, unsigned int format,
			    struct snd_pcm_substream *substream)
{
	struct cs_spec *spec = codec->spec;
	int err;

	err = snd_hda_multi_out_dig_prepare(codec, &spec->gen.multiout,
					    stream_tag, format, substream);
	if (err < 0)
		return err;
	/* replay the EFI chime path: coef image, amp-block ungate workaround, TDM enable */
	mb81_write_efi_coefs(codec);
	cs_vendor_coef_set(codec, 0x40, 0x9999);	/* test mode on: exposes 0x41-0x6b */
	cs_vendor_coef_set(codec, 0x50, 0x00cb);
	cs_vendor_coef_set(codec, 0x40, 0x0000);	/* test mode off */
	snd_hda_codec_write(codec, CS4208_VENDOR_NID, 0, MB81_VERB_SET_TDM_EN, 1);
	/* the state EFI leaves for the chime: DigEn + Copy, category 0x01 */
	snd_hda_codec_write(codec, MB81_TDM_NID, 0, AC_VERB_SET_DIGI_CONVERT_1, 0x11);
	snd_hda_codec_write(codec, MB81_TDM_NID, 0, AC_VERB_SET_DIGI_CONVERT_2, 0x01);
	snd_hda_codec_write(codec, MB81_TDM_PIN, 0, AC_VERB_SET_CONNECT_SEL, 0);
	snd_hda_set_pin_ctl_cache(codec, MB81_TDM_PIN, PIN_OUT);
	spec->mb81_playing = 1;
	if (mb81_update_amp(codec))
		msleep(MB81_AMP_PRE_DELAY_MS);
	return 0;
}

static int mb81_tdm_cleanup(struct hda_pcm_stream *hinfo, struct hda_codec *codec,
			    struct snd_pcm_substream *substream)
{
	struct cs_spec *spec = codec->spec;

	spec->mb81_playing = 0;
	mb81_update_amp(codec);
	return snd_hda_multi_out_dig_cleanup(codec, &spec->gen.multiout);
}

/* never let the analog stream share (and re-clock) the TDM converter */
static int mb81_share_spdif_put(struct snd_kcontrol *kcontrol,
				struct snd_ctl_elem_value *ucontrol)
{
	ucontrol->value.integer.value[0] = 0;
	return 0;
}

static void cs4208_fixup_mb81(struct hda_codec *codec,
			      const struct hda_fixup *fix, int action)
{
	struct cs_spec *spec = codec->spec;
	struct snd_kcontrol *kctl;
	unsigned int wcaps;

	switch (action) {
	case HDA_FIXUP_ACT_PRE_PROBE:
		snd_hda_apply_pincfgs(codec, mb81_pincfgs);
		spec->mb81 = 1;
		spec->gpio_eapd_hp = 0;
		spec->gpio_eapd_speaker = 0;
		spec->gpio_mask = MB81_GPIO_MASK;
		spec->gpio_dir = MB81_GPIO_AMP_EN;
		spec->gpio_data = 0;
		spec->gen.automute_hook = mb81_automute;
		spec->gen.stream_digital_playback = &mb81_tdm_playback;
		/* 0x0a reports 8 channels; the TDM link carries 4 */
		wcaps = get_wcaps(codec, MB81_TDM_NID);
		wcaps = (wcaps & ~AC_WCAP_CHAN_CNT_EXT) | (1 << 13);
		snd_hda_override_wcaps(codec, MB81_TDM_NID, wcaps);
		break;
	case HDA_FIXUP_ACT_BUILD:
		spec->gen.multiout.share_spdif = 0;
		kctl = snd_hda_find_mixer_ctl(codec, "IEC958 Default PCM Playback Switch");
		if (kctl)
			kctl->put = mb81_share_spdif_put;
		break;
	}
}

static const struct hda_fixup cs4208_fixups[] = {'''
sub("\nstatic const struct hda_fixup cs4208_fixups[] = {", impl)

# the earlier forward declaration must stay a declaration
# (the original file declares "static const struct hda_fixup cs4208_fixups[];" before cs4208_fixup_mac)

# 3. fixup table entry
sub("\t[CS4208_GPIO0] = {\n", "\t[CS4208_MB81] = {\n\t\t.type = HDA_FIXUP_FUNC,\n\t\t.v.func = cs4208_fixup_mb81,\n\t},\n\t[CS4208_GPIO0] = {\n")

# 4. spec flag
sub("struct cs_spec {\n\tstruct hda_gen_spec gen;\n", "struct cs_spec {\n\tstruct hda_gen_spec gen;\n\n\tunsigned int mb81:1;\t/* MacBook8,1 TDM speaker fixup active */\n\tunsigned int mb81_playing:1;\t/* TDM speaker PCM prepared */\n")

# 4b. cs_init: restore the EFI coef image right after the stock CS4208 init verbs
#     (snd_hda_gen_init does not run fixup INIT actions; cs_init also runs on resume)
sub("static int cs_init(struct hda_codec *codec)\n",
    "static void mb81_write_efi_coefs(struct hda_codec *codec);\n\nstatic int cs_init(struct hda_codec *codec)\n")
sub("\t\tsnd_hda_sequence_write(codec, cs4208_coef_init_verbs);\n",
    "\t\tsnd_hda_sequence_write(codec, cs4208_coef_init_verbs);\n\t\tif (spec->mb81)\n\t\t\tmb81_write_efi_coefs(codec);\n")

# 5. build_pcms wrapper: route the digital PCM's prepare through mb81_tdm_prepare
wrapper = r'''
static int cs_build_pcms(struct hda_codec *codec)
{
	struct cs_spec *spec = codec->spec;
	int err = snd_hda_gen_build_pcms(codec);

	if (err < 0)
		return err;
	if (spec->mb81 && spec->gen.pcm_rec[1]) {
		struct hda_pcm_stream *st = &spec->gen.pcm_rec[1]->stream[SNDRV_PCM_STREAM_PLAYBACK];

		st->ops.prepare = mb81_tdm_prepare;
		st->ops.cleanup = mb81_tdm_cleanup;
	}
	return 0;
}

static const struct hda_codec_ops cs_codec_ops = {'''
sub("\nstatic const struct hda_codec_ops cs_codec_ops = {", wrapper)
sub("\t.build_pcms = snd_hda_gen_build_pcms,\n\t.init = cs_init,", "\t.build_pcms = cs_build_pcms,\n\t.init = cs_init,")

open(p, "w").write(s)
print("patched: CS4208_MB81 fixup")
