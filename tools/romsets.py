"""ROM set table for the Sega Space Harrier / Hang-On core.

One entry per supported MAME set, copied from the ROM_START blocks in
src/mame/sega/segahang.cpp. The format follows the X and Y Board cores:
`regions` lists (region, loader, [files]) in stream order, files are
(name, size, crc) or (name, size, crc, repeat) for ROM_RELOAD mirrors,
and the loaders are 'w16' (LOAD16_BYTE pairs), 'flat', and whatever the
sprite ROM interleave turns out to need. SLOT/ORDER and the descriptor
are decided in M0 with the memory map; see docs/DESIGN.md.
"""

SLOT = {}      # region -> stream slot size; written in M0 with sh_pkg.sv
ORDER = []     # stream order; written in M0
DESC_SIZE = 64

# Sega's standard coinage table (SEGA_COINAGE_LOC), value order 0..15
COINAGE = ("Free Play (if both) or 1C/1C,1C/1C 2/3,1C/1C 4/5,1C/1C 5/6,2C/1C 4/3,"
           "2C/1C 3/2 5/3 6/4,2C/3C,4C/1C,3C/1C,2C/1C,7C/1C,6C/1C,5C/1C,1C/3C,1C/2C,1C/1C")

ROMSETS = {}
