#!/usr/bin/env python3
"""Render every layer — tiles, text, road and sprites — from a MAME RAM
dump with the Python models and compare the composed frame against MAME's
screenshot, pixel for pixel. Writes model.png next to the dump.

    model_check.py verif/golden/hangon/f60 [hangon]
"""
import os, sys, zipfile
from PIL import Image
sys.path.insert(0, os.path.join(os.path.dirname(__file__), "..", "verif"))
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from romsets import ROMSETS
from models import tilemap_hangon as tm
from models import road_hangon as rd
from models import sprite_hangon as sp
from models import sprite_sharrier as spsh
from models import palette5242 as pal


def load_words(path):
    b = open(path, "rb").read()
    return [b[i] | (b[i + 1] << 8) for i in range(0, len(b), 2)]


ZIPDIR = "/Volumes/roms/Arcade/MAME 0.289 ROMs (merged)"


def main(dumpdir, setname="hangon"):
    rs = ROMSETS[setname]
    zippath = os.path.join(ZIPDIR, rs["zipfile"] + ".zip")
    sharrier = bool(rs.get("sharrier", 0))
    tileram = load_words(os.path.join(dumpdir, "tileram.bin"))[:0x2000]
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
    roadram = load_words(os.path.join(dumpdir, "roadram.bin"))
    roadrom = zf.read([m for m in zf.namelist() if m.split("/")[-1] == rs["regions"]["road"][1][0][0]][0])
    road, ply = rd.render(roadram, rd.decode(roadrom), sharrier)
    spriteram = load_words(os.path.join(dumpdir, "spriteram.bin"))
    sprrom = []
    files = rs["regions"]["sprite"][1]
    zoomrom = zf.read([m for m in zf.namelist() if m.split("/")[-1] == rs["regions"]["zoom"][1][0][0]][0])
    if sharrier:
        for i in range(0, len(files), 4):
            bs = [zf.read([m for m in zf.namelist() if m.split("/")[-1] == files[i + k][0]][0]) for k in range(4)]
            sprrom.extend(bs[0][j] | (bs[1][j] << 8) | (bs[2][j] << 16) | (bs[3][j] << 24) for j in range(len(bs[0])))
        sprrom.extend([0] * (0x8000 * rs["spr_banks"] - len(sprrom)))
        spr = spsh.draw(spriteram, sprrom, zoomrom, rs["spr_banks"])
        idx, bank = spsh.mix_full(road, ply, fg, bg, tx, spr)
    else:
        for i in range(0, len(files), 2):
            even = zf.read([m for m in zf.namelist() if m.split("/")[-1] == files[i][0]][0])
            odd = zf.read([m for m in zf.namelist() if m.split("/")[-1] == files[i + 1][0]][0])
            sprrom.extend((even[j] << 8) | odd[j] for j in range(len(even)))
        sprrom.extend([0] * (0x8000 * rs["spr_banks"] - len(sprrom)))
        spr = sp.draw(spriteram, sprrom, zoomrom, rs["spr_banks"])
        # MAME video_lamps_w: m_shadow = ~portB & 0x40; truthy picks the
        # hilight bank (palette base + 2*entries)
        shade_hilight = not (pb & 0x40)
        idx, bank = sp.mix_full(road, ply, fg, bg, tx, spr, shade_hilight)
    img = Image.open(os.path.join(dumpdir, "frame.png")).convert("RGB")
    assert img.size == (320, 224), img.size
    total = match = 0
    out = Image.new("RGB", (320, 224))
    for y in range(224):
        for x in range(320):
            rgb = pal.entry_rgb_bank(palram[idx[y][x]], bank[y][x])
            out.putpixel((x, y), rgb)
            if img.getpixel((x, y)) == rgb:
                match += 1
            total += 1
    out.save(os.path.join(dumpdir, "model.png"))
    pct = 100.0 * match / total
    print(f"full frame: {match}/{total} matching MAME PNG ({pct:.2f}%)")
    print(f"scroll enables: col={colscroll} row={rowscroll}; portB={pb:02x} portC={pc:02x}")
    return pct


if __name__ == "__main__":
    main(sys.argv[1], sys.argv[2] if len(sys.argv) > 2 else "hangon")
