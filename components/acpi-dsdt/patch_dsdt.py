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

# 2. Bump OEM revision so the kernel's table-upgrade accepts it.
m = re.search(r'DefinitionBlock \("", "DSDT", (\d+), "APPLE ", "MacBook", 0x([0-9A-Fa-f]+)\)', s)
if not m:
    sys.exit("DefinitionBlock header not found")
rev = int(m.group(2), 16) + 1
s = s[:m.start()] + f'DefinitionBlock ("", "DSDT", {m.group(1)}, "APPLE ", "MacBook", 0x{rev:08X})' + s[m.end():]

open(dst, "w").write(s)
print(f"patched: SSDC disabled, OEM revision -> 0x{rev:08X}")
