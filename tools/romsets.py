"""ROM set table for the Sega Space Harrier / Hang-On core.

One entry per supported MAME set, copied from the ROM_START blocks in
src/mame/sega/segahang.cpp (0.289). The format follows the X and Y Board
cores: `regions` lists (region, loader, [files]) with files (name, size,
crc) or (name, size, crc, repeat) for ROM_RELOAD mirrors; loaders are
'w16' (LOAD16_BYTE pairs, even file first), 'x32' (LOAD32_BYTE groups of
four) and 'flat'. SLOT/ORDER mirror rtl/sh_pkg.sv: the SDRAM regions
first (the loader is a plain copy), then the BRAM regions; every region
is padded to its slot except the last one a set populates.
"""

SLOT = {
    "main":    0x40000,
    "sub":     0x40000,
    "z80":     0x10000,
    "pcm":     0x20000,
    "mainops": 0x40000,   # decrypted-opcode image (FD1089B / bootleg sets)
    "sprite":  0x100000,
    "tile":    0x18000,
    "road":    0x8000,
    "zoom":    0x2000,
    "mcu":     0x1000,
    "key":     0x2000,
}
ORDER = ["main", "sub", "z80", "pcm", "mainops", "sprite",
         "tile", "road", "zoom", "mcu", "key"]
DESC_SIZE = 64

# Sega's standard coinage table (SEGA_COINAGE_NO_FREE_LOC), value order 0..15
COINAGE = ("Free Play (if both) or 1C/1C,1C/1C 2/3,1C/1C 4/5,1C/1C 5/6,2C/1C 4/3,"
           "2C/1C 3/2 5/3 6/4,2C/3C,4C/1C,3C/1C,2C/1C,7C/1C,6C/1C,5C/1C,1C/3C,1C/2C,1C/1C")

ROMSETS = {
    # Hang-On (Rev A). MAME 0.289 `hangon`: two 68000s at 25.1748/4, YM2203
    # sound board, HANGON sprites/road, 3-bank palette.
    "hangon": {
        "name": "Hang-On",
        "zipfile": "hangon",
        "year": "1985",
        "category": "Racing / Driving",
        # descriptor
        "game_id": 0,
        "sound_board": 0,     # YM2203 + 315-5218 at 8 MHz
        "spr_banks": 8,       # 512 KB region / 64 KB banks
        "adc_reverse": 0x01,  # steering (channel 0) is PORT_REVERSE
        "ana_mode": 0,        # hangon driving: steer / gas / brake
        "regions": {
            "main": ("w16", [
                ("epr-6918a.ic22", 0x8000, "20b1c2b0"),
                ("epr-6916a.ic8",  0x8000, "7d9db1bf"),
                ("epr-6917a.ic20", 0x8000, "fea12367"),
                ("epr-6915a.ic6",  0x8000, "ac883240"),
            ]),
            "sub": ("w16", [
                ("epr-6920.ic63", 0x8000, "1c95013e"),
                ("epr-6919.ic51", 0x8000, "6ca30d69"),
            ]),
            "z80": ("flat", [
                ("epr-6833.ic73", 0x4000, "3b942f5f"),
            ]),
            "pcm": ("flat", [
                ("epr-6831.ic5", 0x8000, "cfef5481"),
                ("epr-6832.ic6", 0x8000, "4165aea5"),
            ]),
            # LOAD16_BYTE pairs, even (ic34 column) file first
            "sprite": ("w16", [
                ("epr-6820.ic34", 0x8000, "87cbc6de"),
                ("epr-6819.ic27", 0x8000, "469dad07"),
                ("epr-6822.ic35", 0x8000, "e9718de5"),
                ("epr-6821.ic28", 0x8000, "15792969"),
                ("epr-6824.ic36", 0x8000, "701deaa4"),
                ("epr-6823.ic29", 0x8000, "49422691"),
                ("epr-6826.ic37", 0x8000, "77d0de2c"),
                ("epr-6825.ic30", 0x8000, "6e23c8b4"),
                ("epr-6828.ic38", 0x8000, "8e880c93"),
                ("epr-6827.ic31", 0x8000, "7fa1bfb6"),
                ("epr-6830.ic39", 0x8000, "b1a63aef"),
                ("epr-6829.ic32", 0x8000, "7ca0952d"),
                ("epr-6846.ic25", 0x8000, "f21e57a3"),
                ("epr-6845.ic18", 0x8000, "ba08c9b8"),
            ]),
            "tile": ("flat", [
                ("epr-6841.ic38", 0x8000, "54d295dc"),
                ("epr-6842.ic23", 0x8000, "f677b568"),
                ("epr-6843.ic7",  0x8000, "a257f0da"),
            ]),
            "road": ("flat", [
                ("epr-6840.ic108", 0x8000, "581230e3"),
            ]),
            "zoom": ("flat", [
                ("epr-6844.ic123", 0x2000, "e3ec7bd6"),
            ]),
        },
        # SW A (byte 0) coinage, SW B (byte 1) game options; defaults MAME's
        "dip_default": "FF,FE",
        "dips": [
            (0, 3, "Coin A", COINAGE),
            (4, 7, "Coin B", COINAGE),
            (8, 8, "Demo Sounds", "On,Off"),
            (9, 10, "Difficulty", "Hardest,Hard,Easy,Medium"),
            (11, 12, "Time Adj.", "Hardest,Hard,Medium,Normal"),
            (13, 13, "Play Music", "Off,On"),
        ],
        "buttons": ("Gas,Brake,Start,Coin,Pause,Test,Service",
                    "A,B,Start,R,L,X,Y"),
    },

    # Hang-On, the earlier non-Rev-A program. MAME 0.289 `hangon1`: only the
    # four main CPU ROMs differ from `hangon`.
    "hangon1": {
        "name": "Hang-On (original)",
        "zipfile": "hangon",
        "alt": "Hang-On",   # alternative: releases/_alternatives/_Hang-On/
        "year": "1985",
        "category": "Racing / Driving",
        "game_id": 0,
        "sound_board": 0,
        "spr_banks": 8,
        "adc_reverse": 0x01,
        "ana_mode": 0,
        "regions": {
            "main": ("w16", [
                ("epr-6918.ic22", 0x8000, "0bf4f2ac"),
                ("epr-6916.ic8",  0x8000, "06c21c8a"),
                ("epr-6917.ic20", 0x8000, "f48a6cbc"),
                ("epr-6915.ic6",  0x8000, "75d3b5ee"),
            ]),
            "sub": ("w16", [
                ("epr-6920.ic63", 0x8000, "1c95013e"),
                ("epr-6919.ic51", 0x8000, "6ca30d69"),
            ]),
            "z80": ("flat", [
                ("epr-6833.ic73", 0x4000, "3b942f5f"),
            ]),
            "pcm": ("flat", [
                ("epr-6831.ic5", 0x8000, "cfef5481"),
                ("epr-6832.ic6", 0x8000, "4165aea5"),
            ]),
            "sprite": ("w16", [
                ("epr-6820.ic34", 0x8000, "87cbc6de"),
                ("epr-6819.ic27", 0x8000, "469dad07"),
                ("epr-6822.ic35", 0x8000, "e9718de5"),
                ("epr-6821.ic28", 0x8000, "15792969"),
                ("epr-6824.ic36", 0x8000, "701deaa4"),
                ("epr-6823.ic29", 0x8000, "49422691"),
                ("epr-6826.ic37", 0x8000, "77d0de2c"),
                ("epr-6825.ic30", 0x8000, "6e23c8b4"),
                ("epr-6828.ic38", 0x8000, "8e880c93"),
                ("epr-6827.ic31", 0x8000, "7fa1bfb6"),
                ("epr-6830.ic39", 0x8000, "b1a63aef"),
                ("epr-6829.ic32", 0x8000, "7ca0952d"),
                ("epr-6846.ic25", 0x8000, "f21e57a3"),
                ("epr-6845.ic18", 0x8000, "ba08c9b8"),
            ]),
            "tile": ("flat", [
                ("epr-6841.ic38", 0x8000, "54d295dc"),
                ("epr-6842.ic23", 0x8000, "f677b568"),
                ("epr-6843.ic7",  0x8000, "a257f0da"),
            ]),
            "road": ("flat", [
                ("epr-6840.ic108", 0x8000, "581230e3"),
            ]),
            "zoom": ("flat", [
                ("epr-6844.ic123", 0x2000, "e3ec7bd6"),
            ]),
        },
        "dip_default": "FF,FE",
        "dips": [
            (0, 3, "Coin A", COINAGE),
            (4, 7, "Coin B", COINAGE),
            (8, 8, "Demo Sounds", "On,Off"),
            (9, 10, "Difficulty", "Hardest,Hard,Easy,Medium"),
            (11, 12, "Time Adj.", "Hardest,Hard,Medium,Normal"),
            (13, 13, "Play Music", "Off,On"),
        ],
        "buttons": ("Gas,Brake,Start,Coin,Pause,Test,Service",
                    "A,B,Start,R,L,X,Y"),
    },

    # Hang-On ride-on cabinet. MAME 0.289 `hangon2`: its own main and sub
    # programs, and the rider's foot switches on SERVICE bits 7 (left) and
    # 6 (right) - the two extra buttons at the end of the list.
    "hangon2": {
        "name": "Hang-On (Rev A, ride-on)",
        "zipfile": "hangon",
        "alt": "Hang-On",   # alternative: releases/_alternatives/_Hang-On/
        "year": "1985",
        "category": "Racing / Driving",
        "game_id": 0,
        "sound_board": 0,
        "spr_banks": 8,
        "adc_reverse": 0x01,
        "ana_mode": 0,
        "regions": {
            "main": ("w16", [
                ("epr-6851a.ic22", 0x8000, "1e4d2217"),
                ("epr-6849a.ic8",  0x8000, "3793e50e"),
                ("epr-6850a.ic20", 0x8000, "5d715e3b"),
                ("epr-6848a.ic6",  0x8000, "f1439a30"),
            ]),
            "sub": ("w16", [
                ("epr-6839.ic63", 0x8000, "2747b794"),
                ("epr-6838.ic51", 0x8000, "73e9fa6e"),
            ]),
            "z80": ("flat", [
                ("epr-6833.ic73", 0x4000, "3b942f5f"),
            ]),
            "pcm": ("flat", [
                ("epr-6831.ic5", 0x8000, "cfef5481"),
                ("epr-6832.ic6", 0x8000, "4165aea5"),
            ]),
            "sprite": ("w16", [
                ("epr-6820.ic34", 0x8000, "87cbc6de"),
                ("epr-6819.ic27", 0x8000, "469dad07"),
                ("epr-6822.ic35", 0x8000, "e9718de5"),
                ("epr-6821.ic28", 0x8000, "15792969"),
                ("epr-6824.ic36", 0x8000, "701deaa4"),
                ("epr-6823.ic29", 0x8000, "49422691"),
                ("epr-6826.ic37", 0x8000, "77d0de2c"),
                ("epr-6825.ic30", 0x8000, "6e23c8b4"),
                ("epr-6828.ic38", 0x8000, "8e880c93"),
                ("epr-6827.ic31", 0x8000, "7fa1bfb6"),
                ("epr-6830.ic39", 0x8000, "b1a63aef"),
                ("epr-6829.ic32", 0x8000, "7ca0952d"),
                ("epr-6846.ic25", 0x8000, "f21e57a3"),
                ("epr-6845.ic18", 0x8000, "ba08c9b8"),
            ]),
            "tile": ("flat", [
                ("epr-6841.ic38", 0x8000, "54d295dc"),
                ("epr-6842.ic23", 0x8000, "f677b568"),
                ("epr-6843.ic7",  0x8000, "a257f0da"),
            ]),
            "road": ("flat", [
                ("epr-6840.ic108", 0x8000, "581230e3"),
            ]),
            # MAME calls this epr-6844.ic119 (the ride-on board's socket);
            # same content, and the zips only carry the parent's file
            "zoom": ("flat", [
                ("epr-6844.ic123", 0x2000, "e3ec7bd6"),
            ]),
        },
        "dip_default": "FF,FE",
        "dips": [
            (0, 3, "Coin A", COINAGE),
            (4, 7, "Coin B", COINAGE),
            (8, 8, "Demo Sounds", "On,Off"),
            (9, 10, "Difficulty", "Hardest,Hard,Easy,Medium"),
            (11, 12, "Time Adj.", "Hardest,Hard,Medium,Normal"),
            (13, 13, "Play Music", "Off,On"),
        ],
        "buttons": ("Gas,Brake,Start,Coin,Pause,Test,Service,Foot SW L,Foot SW R",
                    "A,B,Start,R,L,X,Y,-,-"),
    },

    # Spanish bootleg with the logo art redrawn as "VF". MAME 0.289
    # `hangonvf`: program ROMs match `hangon` byte for byte under bootleg
    # names (the MRA references the parent's files for those); the tiles and
    # three sprite pairs are the bootleg's own.
    "hangonvf": {
        "name": "VF (bootleg of Hang-On)",
        "zipfile": "hangon",
        "alt": "Hang-On",   # alternative: releases/_alternatives/_Hang-On/
        "year": "1985",
        "category": "Racing / Driving",
        "game_id": 0,
        "sound_board": 0,
        "spr_banks": 8,
        "adc_reverse": 0x01,
        "ana_mode": 0,
        "regions": {
            "main": ("w16", [
                ("epr-6918a.ic22", 0x8000, "20b1c2b0"),
                ("epr-6916a.ic8",  0x8000, "7d9db1bf"),
                ("epr-6917a.ic20", 0x8000, "fea12367"),
                ("epr-6915a.ic6",  0x8000, "ac883240"),
            ]),
            "sub": ("w16", [
                ("epr-6920.ic63", 0x8000, "1c95013e"),
                ("epr-6919.ic51", 0x8000, "6ca30d69"),
            ]),
            "z80": ("flat", [
                ("epr-6833.ic73", 0x4000, "3b942f5f"),
            ]),
            "pcm": ("flat", [
                ("epr-6831.ic5", 0x8000, "cfef5481"),
                ("epr-6832.ic6", 0x8000, "4165aea5"),
            ]),
            "sprite": ("w16", [
                ("epr-6820.ic34", 0x8000, "87cbc6de"),
                ("epr-6819.ic27", 0x8000, "469dad07"),
                ("epr-6822.ic35", 0x8000, "e9718de5"),
                ("epr-6821.ic28", 0x8000, "15792969"),
                ("epr-6824.ic36", 0x8000, "701deaa4"),
                ("epr-6823.ic29", 0x8000, "49422691"),
                ("22.6e",         0x8000, "08b007e2"),
                ("16.5e",         0x8000, "f003a000"),
                ("epr-6828.ic38", 0x8000, "8e880c93"),
                ("epr-6827.ic31", 0x8000, "7fa1bfb6"),
                ("20.6h",         0x8000, "33d1aa6e"),
                ("14.5h",         0x8000, "47e63dd1"),
                ("13.4f",         0x8000, "032738ba"),
                ("12.3f",         0x8000, "22fc088e"),
            ]),
            "tile": ("flat", [
                ("2.3j", 0x8000, "255a3a58"),
                ("3.2j", 0x8000, "88b9ffd9"),
                ("4.1j", 0x8000, "18882328"),
            ]),
            "road": ("flat", [
                ("epr-6840.ic108", 0x8000, "581230e3"),
            ]),
            "zoom": ("flat", [
                ("epr-6844.ic123", 0x2000, "e3ec7bd6"),
            ]),
        },
        "dip_default": "FF,FE",
        "dips": [
            (0, 3, "Coin A", COINAGE),
            (4, 7, "Coin B", COINAGE),
            (8, 8, "Demo Sounds", "On,Off"),
            (9, 10, "Difficulty", "Hardest,Hard,Easy,Medium"),
            (11, 12, "Time Adj.", "Hardest,Hard,Medium,Normal"),
            (13, 13, "Play Music", "Off,On"),
        ],
        "buttons": ("Gas,Brake,Start,Coin,Pause,Test,Service",
                    "A,B,Start,R,L,X,Y"),
    },
}
