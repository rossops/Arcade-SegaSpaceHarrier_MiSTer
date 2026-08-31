"""segaic16 road generator, HANGON/SHARRIER variant, ported from MAME
segaic16_road.cpp (segaic16_road_hangon_decode + segaic16_road_hangon_draw
— a literal netlist emulation: counters 9M/9N/9P, flip-flops 9J, shift
register 8S). One road, rendered from live road RAM; a line whose control
word has PLYCONT (bits 11:10) = 0 belongs to the background pass (under
the tile layers), any other value to the foreground pass (over them,
under text). The draw writes every pixel of its line.

Road RAM (word offsets): 0x000+y control; 0x100+idx horizontal position;
0x200+idx colour word 0 (two 6-bit background colours); 0x300+idx colour
word 1. idx = control & 0xFF, which is also the ROM line. Colour bases
(segahang_v.cpp): road pixels 0x038, background 0x7C0.

The HANGON/SHARRIER difference is control bit 9: stripe enable (forces
ff9j2 set, Hang-On) versus ROM /CE (disables road data, Space Harrier).
"""
WIDTH, HEIGHT = 320, 224
COLORBASE1 = 0x038
COLORBASE2 = 0x7C0


def decode(gfx_region):
    """256 rows x 512 2-bit pixels from the two 16 KB bitplanes."""
    n = len(gfx_region)
    rows = []
    for y in range(256):
        src = (y & 0xFF) * 0x40 % n
        row = []
        for x in range(512):
            b = (~x) & 7
            p0 = (gfx_region[src + (x >> 3)] >> b) & 1
            p1 = (gfx_region[src + (x >> 3) + 0x4000] >> b) & 1
            row.append(p0 | (p1 << 1))
        rows.append(row)
    return rows


def render(roadram, gfx, sharrier=False):
    """Return (color, plycont) per pixel: HEIGHT x WIDTH of palette
    indices, plus the per-line PLYCONT value for the mixer."""
    out = [[0] * WIDTH for _ in range(HEIGHT)]
    ply = [0] * HEIGHT
    for y in range(HEIGHT):
        control = roadram[0x000 + y]
        idx = control & 0xFF
        hpos = roadram[0x100 + idx]
        color0 = roadram[0x200 + idx]
        color1 = roadram[0x300 + idx]
        ply[y] = (control >> 10) & 3
        src = gfx[control & 0xFF]
        ctr9m = hpos & 7
        ctr9n9p = (hpos >> 3) & 0xFF
        ff9j1 = (hpos >> 11) & 1
        ff9j2 = 1
        ss8j = 0
        for x in range(-24, WIDTH):
            ctr9n9p_ena = (ctr9m == 7)
            if (ctr9n9p & 0xFF) == 0xFF:
                ff9j1 = 0
            if not (control & 0x100):
                ff9j1 = 1
            if not sharrier and not (control & 0x200):
                ff9j2 = 1
            md = 3
            if not sharrier or not (control & 0x200):
                if (ctr9n9p & 0xC0) == 0xC0:
                    if ss8j & 1:
                        md = src[((ctr9n9p & 0x3F) << 3) | ctr9m]
                    else:
                        md = src[((ctr9n9p & 0x3F) << 3) | (ctr9m ^ 7)]
            select = (ss8j >> 3) & 1
            if ff9j2 and md == 3:
                color = ((color0 >> (0 if select else 8)) & 0x3F) | COLORBASE2
            else:
                if (color1 & 0x80) and md == 3:
                    md = 0
                color = (color1 >> ((md << 1) | select)) & 1
                color |= select << 3
                color |= md << 1
                color |= COLORBASE1
            if x >= 0:
                out[y][x] = color
            ctr9m = (ctr9m + 1) & 7
            if ctr9n9p_ena:
                ctr9n9p = (ctr9n9p + (1 if ff9j1 else -1)) & 0x1FF
            ff9j2 = 0 if (not ff9j1 and (ss8j & 0x80)) else 1
            ss8j = ((ss8j << 1) | ff9j1) & 0xFF
        # MAME keeps ctr9n9p as a plain int; only its low 8/6 bits are read
    return out, ply


def mix(road, ply, fg, bg, tx):
    """segahang screen_update with the road: per line, PLYCONT 0 puts the
    road under the tile layers, anything else paints it over bg and fg
    (the foreground pass rewrites every pixel) with only text on top.
    Returns (idx, mark) grids; the road contributes mark 0 (sprites in M4
    compare against the tile marks only)."""
    idx = [[0] * WIDTH for _ in range(HEIGHT)]
    mark = [[0] * WIDTH for _ in range(HEIGHT)]
    for y in range(HEIGHT):
        under = ply[y] == 0
        for x in range(WIDTH):
            t = tx[y][x]
            f = fg[y][x]
            b = bg[y][x]
            if t is not None:
                idx[y][x] = t[1]
                mark[y][x] |= 8
            elif under and f is not None:
                idx[y][x] = f[1]
                mark[y][x] |= 4 if f[0] else 2
            elif under and b is not None:
                idx[y][x] = b[1]
                mark[y][x] |= 2 if b[0] else 1
            else:
                idx[y][x] = road[y][x]
    return idx, mark
