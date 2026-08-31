#!/usr/bin/env python3
"""Render one frame's sprites from a MAME RAM dump with the RTL (iverilog)
and compare every pixel with the Python model.

    run_sprite.py <dumpdir>
"""
import os, subprocess, sys, zipfile
HERE = os.path.dirname(os.path.abspath(__file__)); ROOT = os.path.join(HERE, "..", "..", "..")
sys.path.insert(0, os.path.join(ROOT, "verif"))
sys.path.insert(0, os.path.join(ROOT, "tools"))
from models import sprite_hangon as sp
from romsets import ROMSETS

ZIPDIR = "/Volumes/roms/Arcade/MAME 0.289 ROMs (merged)"


def words(p):
    b = open(p, "rb").read(); return [b[i] | (b[i + 1] << 8) for i in range(0, len(b), 2)]


def main(dumpdir):
    spriteram = words(os.path.join(dumpdir, "spriteram.bin"))
    with open(os.path.join(HERE, "spriteram.hex"), "w") as f:
        f.write("\n".join(f"{w:04x}" for w in spriteram))
    for name in ("sprite.hex", "zoomrom.hex"):
        dst = os.path.join(HERE, name)
        if os.path.lexists(dst): os.remove(dst)
        os.symlink(os.path.join(ROOT, "verif", "golden", "hangon", name), dst)
    srcs = [os.path.join(ROOT, s) for s in ("rtl/sh_pkg.sv", "rtl/video/sh_video_timing.sv", "rtl/mem/sh_dpram.sv",
            "rtl/video/sh_zoomrom.sv", "rtl/video/sh_sprite.sv")]
    subprocess.check_call(["iverilog", "-g2012", "-DSIMULATION", "-o", "tb.vvp", "-s", "tb_sprite"]
                          + srcs + [os.path.join(HERE, "tb_sprite.sv")], cwd=HERE)
    subprocess.check_call(["vvp", "-n", "tb.vvp"], cwd=HERE, stdout=subprocess.DEVNULL)
    rs = ROMSETS["hangon"]
    zf = zipfile.ZipFile(os.path.join(ZIPDIR, rs["zipfile"] + ".zip"))
    files = rs["regions"]["sprite"][1]
    sprrom = []
    for i in range(0, len(files), 2):
        e, o = zf.read(files[i][0]), zf.read(files[i + 1][0])
        sprrom.extend((e[j] << 8) | o[j] for j in range(len(e)))
    sprrom.extend([0] * (0x8000 * rs["spr_banks"] - len(sprrom)))
    zoomrom = zf.read(rs["regions"]["zoom"][1][0][0])
    grid = sp.draw(spriteram, sprrom, zoomrom, rs["spr_banks"])
    ok = tot = 0
    first = None
    for line in open(os.path.join(HERE, "sprites.txt")):
        y, x, v = line.split(); y, x, v = int(y), int(x), int(v, 16)
        m = grid[y][x]
        got = None if (v & 0xF) == 0 else v
        tot += 1
        if got == m: ok += 1
        elif first is None: first = (x, y, None if m is None else hex(m), hex(v))
    print(f"sprites: {ok}/{tot} ({100.0*ok/max(1,tot):.2f}%) first mismatch {first}")
    return 0 if ok == tot else 1


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1]))
