"""SEGA_HANGON_SPRITES, ported line for line from MAME sega16sp.cpp
(sega_hangon_sprite_device::draw). Sprite RAM entry, 8 words:
  w0 bottom-1 (15:8), top-1 (7:0); list ends at bottom > 0xF0
  w1 bank 15:12, x 8:0 (0xBD = screen 0; MAME origin 189)
  w2 signed 16-bit pitch (words per row)
  w3 ROM offset; the 16-bit value's top bit is the flip flag, and address
     overflow into it mid-row flips the fetch direction (games use this)
  w4 colour 13:8, vzoom 7:2 (the zoom ROM row-skip index), priority 1:0;
     hzoom = vzoom * 2, a source pixel is emitted while
     (xacc & 0xFF) + hzoom < 0x100
  w7 scratch: the chip's working address (the RTL keeps it in its private
     copy, stepped line by line)
ROM words are 4 pens, MSB first; pen 0 and 15 transparent, pen 15 in the
last position ends the row. Banks of 0x8000 words, bank % numbanks.
Output pixel: 11:10 priority, 9:4 colour, 3:0 pen; 0xFFFF = empty.
"""
WIDTH, HEIGHT = 320, 224
XORIGIN = 189   # set_local_origin(189, -1): sprite x 0xBD = screen 0, rows shift down one


def draw(spriteram, rom_words, zoom_rom, numbanks):
    """Return a HEIGHT x WIDTH grid of sprite pixels (None = empty)."""
    out = [[None] * WIDTH for _ in range(HEIGHT)]
    for e in range(0, len(spriteram), 8):
        data = spriteram[e:e + 8]
        bottom = data[0] >> 8
        if bottom > 0xF0:
            break
        top = data[0] & 0xFF
        bank = (data[1] >> 12) & 0xF
        xpos = data[1] & 0x1FF
        pitch = data[2] - 0x10000 if data[2] & 0x8000 else data[2]
        addr = data[3]
        colpri = (((data[4] >> 8) & 0x3F) << 4) | (((data[4] >> 0) & 0x3) << 10)
        vzoom = (data[4] >> 2) & 0x3F
        hzoom = vzoom << 1
        if top >= bottom:
            continue
        bank %= numbanks
        base = 0x8000 * bank
        zaddr = (vzoom & 0x38) << 5
        zmask = 1 << (vzoom & 7)
        # set_local_origin(189, -1): screen row = y - yoffs = y + 1
        for y in range(top, bottom):
            addr = (addr + pitch) & 0xFFFF
            if zoom_rom[zaddr] & zmask:
                addr = (addr + pitch) & 0xFFFF
            zaddr += 1
            sy = y + 1
            if sy < 0 or sy >= HEIGHT:
                continue
            row = out[sy]
            xacc = 0
            x = xpos - XORIGIN
            cur = addr
            if not (addr & 0x8000):
                cur = (addr - 1) & 0xFFFF
                while x <= WIDTH - 1:
                    cur = (cur + 1) & 0xFFFF
                    pixels = rom_words[base + (cur & 0x7FFF)]
                    pix = 0
                    for shift in (12, 8, 4, 0):
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
            else:
                cur = (addr + 1) & 0xFFFF
                while x <= WIDTH - 1:
                    cur = (cur - 1) & 0xFFFF
                    pixels = rom_words[base + (cur & 0x7FFF)]
                    pix = 0
                    for shift in (0, 4, 8, 12):
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


def mix_full(road, ply, fg, bg, tx, spr, shade_hilight):
    """The complete segahang screen_update: road passes and tile layers as
    road_hangon.mix, then sprites compared against the tile priority marks
    (mark bits: bg cat0 1, bg cat1 2, fg cat0 2, fg cat1 4, text 8; the
    road leaves no mark). A sprite pixel whose colour bits 9:4 are all
    ones is the shadow pen: the underlying index moves to the shadow or
    hilight bank (SHADE0). Returns (idx, bank) grids."""
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
            if s is not None and (1 << (s >> 10)) > mark:
                if (s & 0x3F0) == 0x3F0:
                    bank[y][x] = 2 if shade_hilight else 1
                else:
                    idx[y][x] = 0x400 | (s & 0x3FF)
    return idx, bank
