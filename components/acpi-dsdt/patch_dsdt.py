"""Patch a decompiled MacBook8,1 DSDT: SSDC._STA -> 0, bump OEM revision.

usage: patch_dsdt.py in.dsl out.dsl
"""
import re
import sys

src, dst = sys.argv[1], sys.argv[2]
s = open(src).read()

# 1. Disable SSDC (first child of URT0). Match the _STA inside Device (SSDC) only.
m = re.search(r"(Device \(SSDC\)\s*\{.*?Method \(_STA, 0, NotSerialized\)[^{]*\{\s*Return \()0x0F(\))",
              s, re.S)
if not m:
    sys.exit("SSDC._STA not found; DSDT layout changed, review by hand")
s = s[:m.start()] + m.group(1) + "0x00" + m.group(2) + \
    " /* macbook8-1-linux: frees URT0 serdev for BCM2E7C bluetooth */" + s[m.end():]

# 1b. Keep the speaker amp powered across S3. HDEF._PS3 drives PCH GPIO51 low as an
#     output, which cuts the class-D amp's power; only EFI's boot-time chime path
#     configures the amp, so after resume the speakers stay silent. Drop the two writes
#     (GPIO51 stays an input, as it is while running) and keep the 20 ms settle.
m = re.search(r"(Device \(HDEF\)\s*\{.*?Method \(_PS3, 0, Serialized\)[^{]*\{)(\s*GP51 = 0x00\s*GD51 = 0x00)",
              s, re.S)
if not m:
    sys.exit("HDEF._PS3 GP51/GD51 writes not found; DSDT layout changed, review by hand")
s = s[:m.start()] + m.group(1) + " /* macbook8-1-linux: keep amp power (GPIO51) on through S3 */" + s[m.end():]

# 2. Bump OEM revision so the kernel's table-upgrade accepts it.
m = re.search(r'DefinitionBlock \("", "DSDT", (\d+), "APPLE ", "MacBook", 0x([0-9A-Fa-f]+)\)', s)
if not m:
    sys.exit("DefinitionBlock header not found")
rev = int(m.group(2), 16) + 1
s = s[:m.start()] + f'DefinitionBlock ("", "DSDT", {m.group(1)}, "APPLE ", "MacBook", 0x{rev:08X})' + s[m.end():]

open(dst, "w").write(s)
print(f"patched: SSDC disabled, HDEF._PS3 keeps GPIO51, OEM revision -> 0x{rev:08X}")
