#!/usr/bin/env python3
"""Render one frame's road from a MAME RAM dump with the RTL (iverilog)
and compare every pixel and every line's PLYCONT with the Python model.

    run_road.py <dumpdir> [--sharrier]
"""
import os, subprocess, sys, zipfile
HERE = os.path.dirname(os.path.abspath(__file__)); ROOT = os.path.join(HERE, "..", "..", "..")
sys.path.insert(0, os.path.join(ROOT, "verif"))
sys.path.insert(0, os.path.join(ROOT, "tools"))
from models import road_hangon as rd
from romsets import ROMSETS

ZIPDIR = "/Volumes/roms/Arcade/MAME 0.289 ROMs (merged)"


def words(p):
    b = open(p, "rb").read(); return [b[i] | (b[i + 1] << 8) for i in range(0, len(b), 2)]


def main(dumpdir, sharrier=False):
    roadram = words(os.path.join(dumpdir, "roadram.bin"))
    with open(os.path.join(HERE, "roadram.hex"), "w") as f: f.write("\n".join(f"{w:04x}" for w in roadram))
    zf = zipfile.ZipFile(os.path.join(ZIPDIR, ROMSETS["hangon"]["zipfile"] + ".zip"))
    rom = zf.read(ROMSETS["hangon"]["regions"]["road"][1][0][0])
    for pl in range(2):
        with open(os.path.join(HERE, f"roadrom{pl}.hex"), "w") as f:
            f.write("\n".join(f"{b:02x}" for b in rom[pl * 0x4000:(pl + 1) * 0x4000]))
    srcs = [os.path.join(ROOT, s) for s in ("rtl/sh_pkg.sv", "rtl/video/sh_video_timing.sv", "rtl/mem/sh_dpram.sv",
            "rtl/video/sh_roadrom.sv", "rtl/video/sh_road.sv")]
    subprocess.check_call(["iverilog", "-g2012", "-DSIMULATION", "-o", "tb.vvp", "-s", "tb_road"]
                          + srcs + [os.path.join(HERE, "tb_road.sv")], cwd=HERE)
    plus = ["+sharrier"] if sharrier else []
    subprocess.check_call(["vvp", "-n", "tb.vvp"] + plus, cwd=HERE, stdout=subprocess.DEVNULL)
    road, ply = rd.render(roadram, rd.decode(rom), sharrier)
    ok = tot = 0
    first = None
    for line in open(os.path.join(HERE, "road.txt")):
        y, x, pix, p = line.split(); y, x, pix, p = int(y), int(x), int(pix, 16), int(p)
        tot += 1
        if pix == road[y][x] and p == ply[y]:
            ok += 1
        elif first is None:
            first = (x, y, hex(road[y][x]), ply[y], hex(pix), p)
    print(f"road: {ok}/{tot} ({100.0*ok/max(1,tot):.2f}%) first mismatch {first}")
    return 0 if ok == tot else 1


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1], "--sharrier" in sys.argv))
