#!/usr/bin/env python3
"""Render the tile layers from a MAME RAM dump with the Python model and
compare against MAME's screenshot. Pixels where the model says a tile
layer is opaque must match the PNG except where a sprite or the road
covers them (higher-priority sprites legitimately draw over tiles; the
raw match statistic is reported and the gate sets the threshold per
capture). Writes model.png next to the dump for eyeballing.

    model_check.py verif/golden/hangon/f60 [hangon]
"""
import os, sys, zipfile
from PIL import Image
sys.path.insert(0, os.path.join(os.path.dirname(__file__), "..", "verif"))
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from romsets import ROMSETS
from models import tilemap_hangon as tm
from models import palette5242 as pal


def load_words(path):
    b = open(path, "rb").read()
    return [b[i] | (b[i + 1] << 8) for i in range(0, len(b), 2)]


ZIPDIR = "/Volumes/roms/Arcade/MAME 0.289 ROMs (merged)"


def main(dumpdir, setname="hangon"):
    rs = ROMSETS[setname]
    zippath = os.path.join(ZIPDIR, rs["zipfile"] + ".zip")
    tileram = load_words(os.path.join(dumpdir, "tileram.bin"))
    textram = load_words(os.path.join(dumpdir, "textram.bin"))
    palram = load_words(os.path.join(dumpdir, "paletteram.bin"))
    zf = zipfile.ZipFile(zippath)
    planes = [zf.read([m for m in zf.namelist() if m.split("/")[-1] == n][0]) for n, _, _ in rs["regions"]["tile"][1]]
    # PPI0 port C latches: bit 2 = column scroll enable, bit 1 = row scroll,
    # both active low (MAME tilemap_sound_w)
    pb, pc = [int(v) for v in open(os.path.join(dumpdir, "ppi.txt")).read().split()]
    colscroll = not (pc & 0x04)
    rowscroll = not (pc & 0x02)
    fg = tm.render_layer(0, tileram, textram, planes, colscroll, rowscroll)
    bg = tm.render_layer(1, tileram, textram, planes, colscroll, rowscroll)
    tx = tm.render_text(textram, planes)
    idx, mark = tm.mix(fg, bg, tx)
    img = Image.open(os.path.join(dumpdir, "frame.png")).convert("RGB")
    assert img.size == (320, 224), img.size
    total = match = opaque = 0
    out = Image.new("RGB", (320, 224))
    for y in range(224):
        for x in range(320):
            rgb = pal.entry_rgb(palram[idx[y][x]])
            out.putpixel((x, y), rgb)
            if mark[y][x]:
                opaque += 1
                if img.getpixel((x, y)) == rgb:
                    match += 1
            total += 1
    out.save(os.path.join(dumpdir, "model.png"))
    pct = 100.0 * match / max(1, opaque)
    print(f"tile-opaque pixels {opaque}/{total}; matching MAME PNG: {match} ({pct:.2f}%)")
    print(f"scroll enables: col={colscroll} row={rowscroll}; portB={pb:02x} portC={pc:02x}")
    return pct


if __name__ == "__main__":
    main(sys.argv[1], sys.argv[2] if len(sys.argv) > 2 else "hangon")
