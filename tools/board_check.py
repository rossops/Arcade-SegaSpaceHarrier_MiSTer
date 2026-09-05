#!/usr/bin/env python3
"""Render the tile, text and road layers from the RTL's own +dumpframe RAM
dumps and compare against the RTL's PPM of that frame, pixel for pixel.
This checks the whole board path (CPU writes -> RAMs -> renderers -> mixer
-> palette) for self-consistency; the models themselves are checked
against MAME by tools/model_check.py. Sprites join in M4.

    board_check.py verif/board/out <frame> [hangon]
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

ZIPDIR = "/Volumes/roms/Arcade/MAME 0.289 ROMs (merged)"


def load_words(path):
    b = open(path, "rb").read()
    return [b[i] | (b[i + 1] << 8) for i in range(0, len(b), 2)]


def main(outdir, frame, setname="hangon"):
    rs = ROMSETS[setname]
    zf = zipfile.ZipFile(os.path.join(ZIPDIR, rs["zipfile"] + ".zip"))
    planes = [zf.read([m for m in zf.namelist() if m.split("/")[-1] == n][0]) for n, _, _ in rs["regions"]["tile"][1]]
    sharrier = bool(rs.get("sharrier", 0))
    tileram = load_words(os.path.join(outdir, "rtl_tileram.bin"))[:0x2000]   # the tilemap reads the first 16 KB
    textram = load_words(os.path.join(outdir, "rtl_textram.bin"))
    palram = load_words(os.path.join(outdir, "rtl_paletteram.bin"))
    pb, pc, disp = [int(v) for v in open(os.path.join(outdir, "rtl_ppi.txt")).read().split()]
    colscroll = not (pc & 0x04)
    rowscroll = not (pc & 0x02)
    fg = tm.render_layer(0, tileram, textram, planes, colscroll, rowscroll)
    bg = tm.render_layer(1, tileram, textram, planes, colscroll, rowscroll)
    tx = tm.render_text(textram, planes)
    roadram = load_words(os.path.join(outdir, "rtl_roadram.bin"))
    roadrom = zf.read([m for m in zf.namelist() if m.split("/")[-1] == rs["regions"]["road"][1][0][0]][0])
    road, ply = rd.render(roadram, rd.decode(roadrom), sharrier)
    spriteram = load_words(os.path.join(outdir, "rtl_spriteram.bin"))
    sprrom = []
    files = rs["regions"]["sprite"][1]
    zoomrom = zf.read([m for m in zf.namelist() if m.split("/")[-1] == rs["regions"]["zoom"][1][0][0]][0])
    if sharrier:
        # LOAD32_BYTE groups of four: byte k of each dword from file k
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
        shade_hilight = not (pb & 0x40)
        idx, bank = sp.mix_full(road, ply, fg, bg, tx, spr, shade_hilight)
    img = Image.open(os.path.join(outdir, f"frame_{frame:04d}.ppm")).convert("RGB")
    assert img.size == (320, 224), img.size
    match = 0
    first = None
    out = Image.new("RGB", (320, 224))
    for y in range(224):
        for x in range(320):
            rgb = pal.entry_rgb_bank(palram[idx[y][x]], bank[y][x]) if disp else (0, 0, 0)
            out.putpixel((x, y), rgb)
            if img.getpixel((x, y)) == rgb:
                match += 1
            elif first is None:
                first = (x, y, img.getpixel((x, y)), rgb)
    out.save(os.path.join(outdir, "board_model.png"))
    print(f"board frame {frame}: {match}/71680 ({100.0*match/71680:.2f}%) first mismatch {first}")
    return 0 if match == 71680 else 1


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1], int(sys.argv[2]), sys.argv[3] if len(sys.argv) > 3 else "hangon"))
