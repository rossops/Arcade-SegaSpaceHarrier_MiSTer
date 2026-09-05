"""SEGA_SHARRIER_SPRITES (sega16sp.cpp, sega_sharrier_sprite_device::draw)
as a Python golden model. Same list walk as the Hang-On variant, different
entry layout and a 32-bit ROM word carrying eight pixels:
  w0 bottom 15:8, top 7:0 (scanline - 1)
  w1 bank 14:12 (128 KB banks, bank % numbanks), x 8:0 (0xBD = screen 0)
  w2 shadow-disable 15, priority 14, colour 13:8, signed 7-bit pitch 6:0
  w3 flip 15 + offset 14:0 (the 16-bit add carries into the flip bit)
  w4 hzoom 13:8 (times two), vzoom 5:0 (zoom ROM row-skip index)
  w7 scratch (current address)
A source pixel is emitted while (xacc & 0xFF) + hzoom < 0x100; pen 0 and
15 transparent, pen 15 in the word's last position ends the row. Output
pixel: {shadow_disable, priority, colour[5:0], pen[3:0]} = colpri | pen,
colpri = w2[15:8] << 4. Banks of 0x8000 dwords.
"""
from .sprite_hangon import WIDTH, HEIGHT, XORIGIN


def draw(spriteram, rom_dwords, zoom_rom, numbanks):
    """Return a HEIGHT x WIDTH grid of sprite pixels (None = empty)."""
    out = [[None] * WIDTH for _ in range(HEIGHT)]
    for e in range(0, len(spriteram), 8):
        data = spriteram[e:e + 8]
        bottom = data[0] >> 8
        if bottom > 0xF0:
            break
        top = data[0] & 0xFF
        bank = (data[1] >> 12) & 0x7
        xpos = data[1] & 0x1FF
        colpri = ((data[2] >> 8) & 0xFF) << 4
        pitch = data[2] & 0x7F
        if pitch & 0x40:
            pitch -= 0x80
        addr = data[3]
        hzoom = ((data[4] >> 8) & 0x3F) << 1
        vzoom = data[4] & 0x3F
        if top >= bottom:
            continue
        bank %= numbanks
        base = 0x8000 * bank
        zaddr = (vzoom & 0x38) << 5
        zmask = 1 << (vzoom & 7)
        for y in range(top, bottom):
            addr = (addr + pitch) & 0xFFFF
            if zoom_rom[zaddr] & zmask:
                addr = (addr + pitch) & 0xFFFF
            zaddr += 1
            sy = y + 1                      # set_local_origin(189, -1)
            if sy < 0 or sy >= HEIGHT:
                continue
            row = out[sy]
            xacc = 0
            x = xpos - XORIGIN
            if not (addr & 0x8000):
                cur = (addr - 1) & 0xFFFF
                shifts = (28, 24, 20, 16, 12, 8, 4, 0)
                step = 1
            else:
                cur = (addr + 1) & 0xFFFF
                shifts = (0, 4, 8, 12, 16, 20, 24, 28)
                step = -1
            while x <= WIDTH - 1:
                cur = (cur + step) & 0xFFFF
                pixels = rom_dwords[base + (cur & 0x7FFF)]
                pix = 0
                for shift in shifts:
                    pix = (pixels >> shift) & 0xF
                    xacc = (xacc & 0xFF) + hzoom
                    if xacc < 0x100:
                        if 0 <= x and pix != 0 and pix != 15:
                            row[x] = colpri | pix
                        x += 1
                        if x > WIDTH - 1:
                            break
                if pix == 15:
                    break
    return out


def mix_full(road, ply, fg, bg, tx, spr):
    """segahang screen_update, the m_sharrier_video branch: a sprite pixel
    wins over the tile priority marks at level ((pix >> 9) & 2) | 1, i.e.
    1 or 3 from its priority bit; a pixel with the shadow-disable bit clear
    and pen 10 is the shadow (the underlying index moves to bank 1, the
    only effect bank on this board); anything else lands at 0x400 | colour
    and pen. Returns (idx, bank) grids."""
    idx = [[0] * WIDTH for _ in range(HEIGHT)]
    bank = [[0] * WIDTH for _ in range(HEIGHT)]
    for y in range(HEIGHT):
        under = ply[y] == 0
        for x in range(WIDTH):
            t = tx[y][x]
            f = fg[y][x]
            b = bg[y][x]
            mark = 0
            if b is not None:
                mark |= 2 if b[0] else 1
            if f is not None:
                mark |= 4 if f[0] else 2
            if t is not None:
                mark |= 8
            if t is not None:
                base = t[1]
            elif under and f is not None:
                base = f[1]
            elif under and b is not None:
                base = b[1]
            else:
                base = road[y][x]
            idx[y][x] = base
            s = spr[y][x]
            if s is not None:
                priority = ((s >> 9) & 2) | 1
                if (1 << priority) > mark:
                    if (s & 0x80F) == 0x00A:
                        bank[y][x] = 1
                    else:
                        idx[y][x] = 0x400 | (s & 0x3FF)
    return idx, bank
