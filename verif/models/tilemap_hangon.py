"""315-5011/5012 'TILEMAP_HANGON' renderer, ported from MAME segaic16.cpp
(tilemap_16a_draw_layer, draw_virtual_tilemap, tilemap_16a_tile_info,
tilemap_16a_text_info) reduced to per-pixel form. The 16A-style tilemap:
4 pages of 64x32 tiles (a 1024x512 virtual space in 2x2 page quadrants),
8x8x3 planar tiles, scroll registers in text RAM, row/column scroll
enabled by external signals (PPI0 port C bits 1 and 2, active low), and
x scroll effective as (0xC8 - x). Unlike 16B there is no register latch
and no alternate register sets.

Inputs: tileram (8192 words, 4 pages), textram (2048 words), tile ROM
planes (three 32 KB byte strings; pen bit 2 comes from the third ROM),
and the two enables. Produces, per layer, (priority, palette index) of
each opaque pixel, and the MAME screen_update mix without road/sprites.
"""
WIDTH, HEIGHT = 320, 224
COLORBASE = 0


def tile_pen(planes, code, row, col):
    code &= (len(planes[0]) >> 3) - 1        # gfxdecode wraps code % elements
    a = (code << 3) | row
    b = 7 - col
    return (((planes[2][a] >> b) & 1) << 2) | (((planes[1][a] >> b) & 1) << 1) | ((planes[0][a] >> b) & 1)


def layer_regs(textram, which):
    """which: 0 = foreground, 1 = background (MAME's draw_layer 'which')."""
    xscroll = textram[0xFF8 // 2 + which] & 0x1FF
    yscroll = textram[0xF24 // 2 + which] & 0x0FF
    pages = textram[0xE9E // 2 - which]
    pages = ((pages >> 4) & 0x0707) | ((pages << 4) & 0x7070)
    pages &= 0x3333                          # 4 pages on HANGON
    return xscroll, yscroll, pages


def render_layer(which, tileram, textram, planes, colscroll=False, rowscroll=False):
    """Return a HEIGHT x WIDTH list of (category, pal_index) or None (pen 0)."""
    xscroll, yscroll, pages = layer_regs(textram, which)
    out = [[None] * WIDTH for _ in range(HEIGHT)]
    for y in range(HEIGHT):
        if rowscroll:
            effx = textram[0xF80 // 2 + (y >> 3) * 2 + which] & 0x1FF
        else:
            effx = xscroll
        ex = (0xC8 - effx) & 0x3FF
        for x in range(WIDTH):
            if colscroll:
                effy = textram[0xF30 // 2 + (x >> 4) * 2 + which] & 0x0FF
            else:
                effy = yscroll
            px = (x + ex) & 0x3FF
            py = (y + effy) & 0x1FF
            quadrant = ((py >> 8) << 1) | (px >> 9)
            page = (pages >> (4 * quadrant)) & 0xF
            word = tileram[page * 0x800 + ((py & 0xFF) >> 3) * 64 + ((px & 0x1FF) >> 3)]
            code = ((word >> 1) & 0x1000) | (word & 0xFFF)
            pen = tile_pen(planes, code, py & 7, px & 7)
            if pen:
                out[y][x] = ((word >> 12) & 1, COLORBASE + ((word >> 5) & 0x7F) * 8 + pen)
    return out


def render_text(textram, planes):
    out = [[None] * WIDTH for _ in range(HEIGHT)]
    for y in range(HEIGHT):
        for x in range(WIDTH):
            col = 24 + (x >> 3)
            word = textram[(y >> 3) * 64 + col]
            pen = tile_pen(planes, word & 0xFF, y & 7, x & 7)
            if pen:
                out[y][x] = ((word >> 11) & 1, COLORBASE + ((word >> 8) & 7) * 8 + pen)
    return out


def mix(fg, bg, tx):
    """MAME segahang screen_update order without road/sprites:
    bg cat 0 (mark 1), bg cat 1 (2), fg cat 0 (2), fg cat 1 (4),
    text cat 0 (8), text cat 1 (8). Returns (idx, mark) grids."""
    idx = [[0] * WIDTH for _ in range(HEIGHT)]
    mark = [[0] * WIDTH for _ in range(HEIGHT)]
    passes = [(bg, 0, 1), (bg, 1, 2), (fg, 0, 2), (fg, 1, 4), (tx, 0, 8), (tx, 1, 8)]
    for layer, cat, m in passes:
        for y in range(HEIGHT):
            row = layer[y]
            for x in range(WIDTH):
                p = row[x]
                if p is not None and p[0] == cat:
                    idx[y][x] = p[1]
                    mark[y][x] |= m
    return idx, mark
