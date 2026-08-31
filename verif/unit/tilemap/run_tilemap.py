#!/usr/bin/env python3
"""Render one frame from a MAME RAM dump with the RTL tilemap (iverilog) and
compare every layer pixel with the Python model.

    run_tilemap.py <dumpdir>            capture replay (enables from ppi.txt)
    run_tilemap.py <dumpdir> --synth    synthetic row+column scroll: the
        capture's text RAM gets pseudo-random row/col tables and both
        enables assert, exercising the paths no hangon capture uses.
"""
import os, random, subprocess, sys, zipfile
HERE = os.path.dirname(os.path.abspath(__file__)); ROOT = os.path.join(HERE, "..", "..", "..")
sys.path.insert(0, os.path.join(ROOT, "verif"))
sys.path.insert(0, os.path.join(ROOT, "tools"))
from models import tilemap_hangon as tm
from romsets import ROMSETS

ZIPDIR = "/Volumes/roms/Arcade/MAME 0.289 ROMs (merged)"


def words(p):
    b = open(p, "rb").read(); return [b[i] | (b[i + 1] << 8) for i in range(0, len(b), 2)]


def main(dumpdir, synth=False):
    tileram, textram = words(os.path.join(dumpdir, "tileram.bin")), words(os.path.join(dumpdir, "textram.bin"))
    if synth:
        rng = random.Random(5012)
        for i in range(28 * 2):                      # row scroll words, both layers
            textram[0xF80 // 2 + i] = rng.randrange(0x200)
        for i in range(20 * 2):                      # column scroll words
            textram[0xF30 // 2 + i] = rng.randrange(0x100)
        colscroll = rowscroll = True
    else:
        pb, pc = [int(v) for v in open(os.path.join(dumpdir, "ppi.txt")).read().split()]
        colscroll = not (pc & 0x04)
        rowscroll = not (pc & 0x02)
    with open(os.path.join(HERE, "tileram.hex"), "w") as f: f.write("\n".join(f"{w:04x}" for w in tileram))
    with open(os.path.join(HERE, "textram.hex"), "w") as f: f.write("\n".join(f"{w:04x}" for w in textram))
    zf = zipfile.ZipFile(os.path.join(ZIPDIR, ROMSETS["hangon"]["zipfile"] + ".zip"))
    planes = [zf.read(n) for n, _, _ in ROMSETS["hangon"]["regions"]["tile"][1]]
    for p in range(3):
        with open(os.path.join(HERE, f"tilerom{p}.hex"), "w") as f:
            f.write("\n".join(f"{b:02x}" for b in planes[p]))
    srcs = [os.path.join(ROOT, s) for s in ("rtl/sh_pkg.sv", "rtl/video/sh_video_timing.sv", "rtl/mem/sh_dpram.sv",
            "rtl/video/sh_tilerom.sv", "rtl/video/sh_tilemap_5012.sv")]
    subprocess.check_call(["iverilog", "-g2012", "-DSIMULATION", "-o", "tb.vvp", "-s", "tb_tilemap"]
                          + srcs + [os.path.join(HERE, "tb_tilemap.sv")], cwd=HERE)
    plus = (["+rowscroll"] if rowscroll else []) + (["+colscroll"] if colscroll else [])
    subprocess.check_call(["vvp", "-n", "tb.vvp"] + plus, cwd=HERE, stdout=subprocess.DEVNULL)
    layers = {"fg": tm.render_layer(0, tileram, textram, planes, colscroll, rowscroll),
              "bg": tm.render_layer(1, tileram, textram, planes, colscroll, rowscroll),
              "tx": tm.render_text(textram, planes)}
    stats = {k: [0, 0, None] for k in layers}
    n = 0
    for line in open(os.path.join(HERE, "layers.txt")):
        y, x, fgv, bgv, txv = line.split(); y, x = int(y), int(x)
        vals = {"fg": fgv, "bg": bgv, "tx": txv}
        n += 1
        for k, grid in layers.items():
            m = grid[y][x]
            v = int(vals[k], 16)
            pen = v & 7
            if k == "tx": cat, colour = (v >> 6) & 1, (v >> 3) & 7
            else:         cat, colour = (v >> 10) & 1, (v >> 3) & 0x7F
            got = None if pen == 0 else (cat, tm.COLORBASE + colour * 8 + pen)
            stats[k][1] += 1
            if got == m: stats[k][0] += 1
            elif stats[k][2] is None: stats[k][2] = (x, y, m, got, hex(v))
    print("pixels:", n)
    for k, (ok, tot, first) in stats.items():
        print(f"{k}: {ok}/{tot} ({100.0*ok/max(1,tot):.2f}%) first mismatch {first}")
    return 0 if all(s[0] == s[1] for s in stats.values()) else 1


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1], "--synth" in sys.argv))
