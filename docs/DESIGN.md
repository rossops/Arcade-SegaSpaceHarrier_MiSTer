# Sega Space Harrier / Hang-On board for MiSTer — design notes

Written 2026-08-30 from MAME 0.289 (`src/mame/sega/segahang.cpp`,
`segahang_v.cpp`, `sega16sp.cpp`, `segaic16.cpp`, `segaic16_road.cpp`)
before any board-specific RTL exists. The X Board and Y Board cores'
`docs/DESIGN.md` are the worked examples for everything shared; this
document says what is different and what the plan is. Where MAME guesses,
the guess is an open question at the end.

Three claims that circulated during scaffolding turned out wrong against
the source and are corrected here: Space Harrier's sound board is the same
YM2203 + 315-5218 board as Hang-On's (the YM2151 board belongs to the
Enduro YM2151 sets and the Super Hang-On conversions); `enduror1` has one
YM2203, the two-YM2203 board is the `endurob2` bootleg; and there are no
315-5248/5249 math chips anywhere in this driver — the carried
`sh_math_5248/5249` go in M0's trim.

## 1. What came over and what is new

Carried (see `references.md`): the MiSTer top and Quartus project, `sys/`,
`sdram.sv` and the stream loader, the fx68k wrapper with the shared-RAM-safe
bus contract, the ROM cache, the Z80 sound board with jt51 and
`sh_segapcm_5218` (this board is the older BANK_512 style the module already
has as a parameter), the 315-5242 palette LUTs (this board predates the 5242
but uses the identical resistor DAC — see section 2), the video timing, the
ADC0804 and the analog shaper, and the whole verification stack.

Dropped in M0, confirmed against the driver: `sh_math_5248.sv` and
`sh_math_5249.sv` (no math chips on this board), `sh_fb_if.sv` and the DDR3
path (both sprite generators are line-based). jt51 stays parked until M8.

New for this board:

| Piece | Reference | Notes |
| --- | --- | --- |
| Tilemap generator (315-5011/5012) | `segaic16.cpp` TILEMAP_HANGON | the 16A-style tilemap with 4 pages; the X Board's 16B module is the later relative |
| Road generator | `segaic16_road.cpp` ROAD_HANGON / ROAD_SHARRIER | gate-level port in MAME (flip-flops named after PCB positions); the X Board's road is the later Out Run device, different enough to port fresh from this code |
| Sprite generators | `sega16sp.cpp` SEGA_HANGON / SEGA_SHARRIER | line-based, zoom ROM row-skip; the Y Board's 16B renderer is the closest shape |
| YM2203 | jotego jt03 | same licence situation as jt51 |
| i8255 PPI x2 | MAME `i8255.cpp` | port A of the main PPI runs the mode-1 strobed handshake to the Z80 (/OBF = NMI, ACK from the latch read) — most FPGA 8255s skip mode 1, ours must not |
| MCS-51 core + bus bridge | `segahang.cpp` i8751 handlers | Space Harrier's dumped 8751 (315-5163A) is a third master on the main 68000 bus and the *only* interrupt source for the main CPU on that game |
| FD1089B | MAME `fd1089.cpp`, key 317-0013A | Enduro Racer main CPU; static table decrypt, small RTL block + 8 KB key BRAM |
| FD1094 | X Board's vendored jtcores block | `shangonro`/`shangonho` sub CPU (317-0038/0039); deferred, `shangonrb` is unencrypted |

## 2. Hardware reference

### Clocks and screen

Crystals: 25.1748 MHz (main board), 10 MHz (the `sharrier` CPU replacement),
8 MHz (sound board and i8751). Hang-On and the Super Hang-On conversions run
both 68000s at 25.1748/4 = 6.2937 MHz (MAME raises the conversions to 10 MHz
with a "not sure about these speeds" comment — open question 7); Space
Harrier and Enduro Racer run both at 10 MHz. Z80 at 8/2 = 4 MHz; YM2203 at
4 MHz; YM2151 at 4 MHz; 315-5218 PCM at 8 MHz behind the YM2203 board but
4 MHz behind the other two (section on sound below); i8751 at 8 MHz.

The screen is a measured `set_raw`: 25.1748/4 = 6.2937 MHz pixel clock,
400 total columns x 262 lines, 320x224 visible, 60.05 Hz. That is the X
Board's 400x262 grid at a marginally faster pixel clock, so
`sh_video_timing` keeps its counters and changes only the enable — and the
Y Board's open question 1 is answered by MAME itself for this family.

### Memory maps (MAME; 24-bit, sub CPU masked to 19 bits)

Hang-On main 68000 (`hangon_map`, also the Super Hang-On conversions):

| Range | What |
| --- | --- |
| 000000-03FFFF | program ROM, 256 KB |
| 20C000-20FFFF | work RAM, 16 KB |
| 400000-403FFF | tile RAM, 16 KB |
| 410000-410FFF | text RAM, 4 KB |
| 600000-6007FF | sprite RAM, 2 KB (128 entries) |
| A00000-A00FFF | palette RAM, 4 KB, `hangon_paletteram_w` |
| C00000-C3FFFF | the sub CPU's ROM, read-only window |
| C68000-C68FFF | road RAM, 4 KB, shared |
| C7C000-C7FFFF | sub RAM, 16 KB, shared |
| E00000-E00007 (mirror 1FCFD8) | PPI0, low bytes |
| E01000-E01007 (mirror 1FCFD8) | inputs: SERVICE, COINAGE, DSW, unused |
| E03000-E03007 (mirror 1FCFD8) | PPI1 |
| E03021 (mirror 1FCFDE) | ADC0804 |

Space Harrier / Enduro main 68000 (`sharrier_map`):

| Range | What |
| --- | --- |
| 000000-03FFFF | program ROM, 256 KB (FD1089B on `enduror`) |
| 040000-043FFF | work RAM, 16 KB — the i8751 reads and writes here |
| 100000-107FFF | tile RAM, 32 KB mapped; the tilemap displays only the first 16 KB (4 pages) |
| 108000-108FFF | text RAM, 4 KB |
| 110000-110FFF | palette RAM, 4 KB, `paletteram_w` |
| 124000-127FFF | sub RAM, 16 KB, shared |
| 130000-130FFF | sprite RAM, 4 KB (256 entries) |
| 140000-140007 (mirror FFC8) | PPI0 |
| 140010-140017 (mirror FFC8) | inputs: SERVICE, unused, COINAGE, DSW (order differs from Hang-On) |
| 140020-140027 (mirror FFC8) | PPI1 |
| 140031 (mirror FFCE) | ADC0804 |
| 150000 (mirror FFFE) | write ignored — the MCU writes 0x1C here from its vblank handler |
| 170000 (mirror FFFE) | read ignored — the MCU reads here, MAME says by accident |
| C68000-C68FFF | road RAM, 4 KB, shared |

Sub 68000 (both configurations, `global_mask 0x7ffff`): ROM 000000-03FFFF
(256 KB), road RAM 068000-068FFF, sub RAM 07C000-07FFFF. The shared
regions are sub RAM and road RAM only; the Y Board arbiter semantics (hold
from a read to the holder's next bus cycle) apply to both. Writes into the
main CPU's window onto the sub ROM must be acknowledged and dropped.

Z80, three variants:
- YM2203 board (`hangon`, `sharrier`, `enduror1`): ROM 0000-7FFF, RAM
  C000-C7FF (mirror 0800), YM2203 D000-D001 (mirror 0FFE), 315-5218
  E000-E0FF (mirror 0F00); port 40 (mirror 3F) reads the sound latch.
- YM2151 board (`enduror`, the Super Hang-On conversions): ROM 0000-7FFF,
  315-5218 F000-F0FF (mirror 0700), RAM F800-FFFF; ports 00-01 YM2151
  (mirror 3E), port 40 the latch.
- 2x YM2203 board (`endurob2` bootleg only): the 2151 memory map with
  ports 00-01 = YM2203 #1, C0-C1 = YM2203 #2, 40 the latch.

i8751 (Space Harrier only): 4 KB internal ROM; its external data space
(64 KB window) is bridged onto the main 68000 bus at address
`{P1.6, P1.5, P1.4, P1.3} -> {A20, A18, A17, A16}` | its 16-bit address
with A0 inverted (byte lanes swapped). P1 bits 2:0, inverted, drive the
main CPU's IPL directly. IRQ0 comes from vblank. MAME suppresses its
write to 40385 as a sync hack (open question 2).

### Interrupts, control bits, I/O

Main 68000: IRQ4 at vblank (hold until acknowledge), autovectored —
except Space Harrier, where MAME removes the vblank interrupt and the
i8751 is the only IPL source. The schematics say IRQ2 fires every 16
scanlines; MAME keeps that code disabled and no game is known to need it
(open question 1). No watchdog and no battery RAM anywhere in the driver.

Sub 68000: level 4 driven as a level (not a pulse) from PPI1 port A bit 6,
reset held by bit 5. Bits 3:2 of the same port select the ADC channel.

PPI0 (main, the E00000/140000 one):
- Port A out: sound latch data (mode 1 strobed; /OBF on PC7 is the Z80's
  NMI, active low; the Z80's port-40 read drives ACK on PC6 and clears it).
- Port B out: bit 7 flip screen (tilemaps and sprites), bit 6 SHADE0
  (1 = hilight, 0 = shadow, Hang-On's external effect select), bit 5 Z80
  /RESET, bit 4 display enable, bits 3:2 lamps, bits 1:0 coin counters.
- Port C out: bits 7:4/3 the port-A handshake lines, bit 2 column-scroll
  enable, bit 1 row-scroll enable (both active low into the tilemap),
  bit 0 mute (1 = audio on).

PPI1: port A out as above; port C in returns the ADC0804's /INTR on bit 6.
The ADC0804 runs at 25.1748/4/6 with the single analog input muxed four
ways by the PPI1 select bits — the carried `sh_adc0804` model fits as is.

Inputs: four byte-wide ports on the mirror-decoded input range; SERVICE
holds coins, service, test, start and the game buttons (Space Harrier's
three buttons on bits 7:5, Enduro's start on bit 6, Hang-On ride-on's foot
switches on bits 7:6). COINAGE is SW A, DSW is SW B, both active low.

### Tilemaps (315-5011/5012; `segaic16.cpp` TILEMAP_HANGON)

The 16A-style device with 4 pages of 64x32 tiles (System 16A proper has
8): tile RAM is 4 consecutive pages, text RAM the fifth block. Tiles are
8x8x3 planar (three consecutive 8 KB-per-plane ROMs; region 96 KB = 8192
tiles). Tile word: bit 13 bank select folded into the code
(`code = (data >> 1) & 0x1000 | data & 0xFFF`), colour `(data >> 5) & 0x7F`,
priority bit 12. Text word: code 7:0, colour 10:8, priority bit 11.

Text RAM registers (word offsets): E9C/E9E background/foreground page
selects (E8C/E8E when flipped; four 3-bit page numbers, swapped along X at
draw time, masked to pages 0-3), F24/F26 y scroll, F30-F7D per-16-pixel
column scroll, F80-FED per-8-line row scroll, FF8/FFA x scroll. Row and
column scroll are enabled by the PPI0 port C bits, not by text RAM bits as
on 16B. Effective x scroll is `(0xC8 - xscroll) & 0x3FF`; the text layer
sits at scrolldx -192. Scrolling reaches only the top-left page's worth;
games swap pages and reset the scroll to go further.

### Road (`segaic16_road.cpp`, ROAD_HANGON / ROAD_SHARRIER)

Init parameters from `segahang_v.cpp`: pixel colour base 0x038, background
colour base 0x7C0, xoffs 0. One road, drawn from live shared road RAM (no
double buffer, no control register — unlike Out Run's). Road RAM tables
(word offsets): 000-0FF per-scanline control — bits 11:10 PLYCONT (0 =
this line's road is drawn in the background pass, else the foreground
pass), bit 9 stripe enable (Hang-On) / ROM disable (Space Harrier), bit 8
counting-direction control, bits 7:0 the index; 100-1FF horizontal
position; 200-2FF colour word 0 (two 6-bit background colours); 300-3FF
colour word 1 (per-pixel-value colour bits and the force-to-0 bit 7).

The ROM is 32 KB, two bitplanes (plane 1 at +0x4000), 64 bytes per line,
line = index. MAME's draw loop is a literal netlist port — counters 9M/9N/
9P, flip-flops 9J, shift register 8S, pixels from x = -24 — and the RTL
should port exactly that loop; it is already per-scanline. The only
HANGON/SHARRIER differences are the bit-9 semantics above.

### Sprites (`sega16sp.cpp`)

Both variants: 8 words per entry, list walk stops at `bottom > 0xF0`,
entry skipped when `top >= bottom`; per row `addr += pitch`, and the 8 KB
zoom ROM (`zaddr = (vzoom & 0x38) << 5`, incremented per row; mask
`1 << (vzoom & 7)`) adds pitch a second time on set bits — shrink-only
vertical zoom. Horizontal: 8-bit accumulator, a source pixel is emitted
while `(xacc & 0xFF) + hzoom < 0x100`. Pens 0 and 15 transparent, pen 15
in the last position of a word ends the row. The row address is 16 bits
of which 15 address ROM; bit 15 is the flip flag, and address overflow
into it mid-row flips the fetch direction — games use this deliberately,
port it exactly. MAME writes the working address back into word 7; the
RTL renders from a private copy like the Y Board's 16B renderer, and x
position 0xBD is screen x 0 (MAME origin 189, -1).

Hang-On entry: w0 bottom-1/top-1 (15:8/7:0); w1 bank 15:12, x 8:0; w2
signed 16-bit pitch; w3 flip bit 15, offset 14:0; w4 colour 13:8, vzoom
7:2, priority 1:0, and hzoom = vzoom * 2. ROM in 16-bit words (4 pens),
banks of 64 KB — 8 banks on every Hang-On set, 14 on the conversions.
Output pixel: priority 11:10, colour 9:4, pen 3:0.

Space Harrier entry: w0 as above; w1 bank 14:12, x 8:0; w2 shadow-disable
bit 15, priority bit 14, colour 13:8, signed 7-bit pitch 6:0; w3 flip bit
15, offset 14:0; w4 hzoom 13:8 (x2), vzoom 5:0. ROM in 32-bit words
(8 pens), banks of 128 KB — 8 banks on every set. Output pixel:
shadow-disable 11, priority 10, colour 9:4, pen 3:0.

### Palette and mixing (`segaic16.cpp`, `segahang_v.cpp`)

The palette DAC is the same 5-bit resistor network the 315-5242 formalised
(weights 3.9K/2K/1K/0.5K/0.25K plus the 470-ohm effect resistor), so the
carried `sh_palette_5242` LUTs are reused. Entry format
`sBGR BBBB GGGG RRRR` with the LSBs in 14:12. The banks differ per game:
Hang-On ignores bit 15 and exposes 2048 x 3 banks (normal / shadow /
hilight) with PPI0's SHADE0 bit picking the effect bank; Space Harrier and
Enduro use 2048 x 2 with bit 15 choosing whether the second bank holds the
hilight or the shadow version, as on the later boards.

Mixing order per pixel (from `screen_update`): road background pass
(PLYCONT = 0 lines), tilemap background at two priorities, tilemap
foreground at two, road foreground pass, text (inflated priority), then
sprites compared against the accumulated priority mask. Hang-On sprite
rule: sprite priority = pixel bits 11:10, drawn when
`1 << priority > tilemap mark`; colour bits 9:4 all ones triggers
shadow/hilight (add one or two banks per SHADE0), otherwise palette
`0x400 | pix[9:0]`. Space Harrier rule: priority = `{pix[10], 1}`; shadow
when bit 11 is clear and the pen is 0xA (add one bank); otherwise
`0x400 | pix[9:0]`. Display off (PPI0 port B bit 4) = black.

### Sound boards

| Board | Games | Chips | PCM clock |
| --- | --- | --- | --- |
| YM2203 | `hangon`, `sharrier`, `enduror1` (+`enduror1d`, `endurobl`) | Z80 4 MHz, YM2203 4 MHz, 315-5218 | 8 MHz |
| YM2151 | `enduror`/`endurora`/`endurorb` (+`endurord`), `shangonro`/`shangonho`/`shangonrb`/`shangonrb2` | Z80 4 MHz, YM2151 4 MHz, 315-5218 | 4 MHz |
| 2x YM2203 | `endurob2` bootleg | Z80 4 MHz, two YM2203 4 MHz, 315-5218 | 4 MHz |

All three use BANK_512 PCM banking (bank bits 6:4, shift 12) — the
configuration `sh_segapcm_5218` already hard-codes. MAME's mix: YM2203
FM/SSG routes at 0.05/0.05/0.05/0.15, PCM 0.40; YM2151 0.30, PCM 0.70
(which output index of MAME's YM2203 is FM is open question 4). The latch
is PPI0 port A with the mode-1 handshake; NMI is the /OBF level.

### Encryption and the MCU

- `enduror`, `endurora`, `endurorb`: FD1089B 317-0013A on the main CPU.
  Static per-address table decrypt, separate opcode and data mappings,
  8 KB key in the set. Small combinational RTL block between cache and
  CPU, fetch-type aware (FC), plus the key BRAM. MAME 0.289 also ships
  `endurord`/`enduror1d` decrypted bootlegs, useful as a bring-up ladder.
- `endurobl`/`endurob2`: bootlegs with the decrypted opcodes in separate
  ROM halves; MAME assembles a 192 KB opcode image at init and fetches
  opcodes from it. `pack_roms.py` pre-assembles that image as an extra
  stream region and the CPU bus fetches opcodes from the alternate slot.
- `shangonro`/`shangonho`: FD1094 317-0038/0039 on the *sub* CPU. The X
  Board's vendored jtcores block moves over unchanged; deferred to M9,
  `shangonrb` is unencrypted.
- `sharrier`/`sharrier1`: i8751 315-5163A/5163, dumped, in MAME's sets.
  See the map section; arbitration granularity is open question 2.

### Sets and ROM sizes (MAME 0.289)

`hangon` (+`hangon1`, `hangon2` ride-on, `hangonvf` bootleg), `sharrier`
(+`sharrier1`), `enduror` (+`endurora`, `endurorb`, `enduror1`, bootlegs
`endurobl`, `endurob2`, decrypted `endurord`, `enduror1d`), `shangonro`,
`shangonho` (+bootlegs `shangonrb`, `shangonrb2`). Super Hang-On here
means the Hang-On-conversion sets only; the mainline `shangon` runs on
Out Run hardware and is out of scope for this core.

| Region | hangon | shangon* | sharrier | enduror |
| --- | --- | --- | --- | --- |
| main (LOAD16_BYTE) | 128 KB in a 256 KB region | 96 KB | 256 KB | 192 KB |
| sub (LOAD16_BYTE) | 64 KB | 64 KB | 128 KB | 128 KB |
| tiles (3 planes, flat) | 96 KB | 96 KB | 96 KB | 96 KB |
| sprites | 448 KB, 16-bit words | 896 KB, 16-bit | 1 MB, LOAD32_BYTE | 1 MB, LOAD32_BYTE |
| road | 32 KB | 32 KB | 32 KB | 32 KB |
| Z80 | 16 KB | 32 KB | 32 KB | 32 KB |
| PCM | 64 KB | 128 KB | 64 KB | 128 KB |
| zoom PROM | 8 KB | 8 KB | 8 KB | 8 KB |
| extra | — | FD1094 key 8 KB | MCU 4 KB | FD1089B key 8 KB |

## 3. Architecture

### Clocks

One PLL: `clk_sys` = 50.3496 MHz (2x the 25.1748 MHz PCB master, so the
pixel /8, the Hang-On CPU /8 and the ADC /48 enables are exact),
`clk_ram` = 100.6992 MHz, SDRAM clock at 180 degrees. The 10 MHz CPUs, the
4 MHz sound section and the 8 MHz PCM tick and i8751 come from
accumulator (fractional) enables out of `clk_sys`, the X Board's modulo
trick generalised; the jitter is tens of nanoseconds against multi-clock
bus cycles. Open question 5 tracks whether any of these need to be exact.

### Memory placement

SDRAM, all slots sized to the largest set (~1.75 MB total), CPU ROMs
behind the carried caches:

| Offset | Slot | Contents |
| --- | --- | --- |
| 0x000000 | 256 KB | main ROM |
| 0x040000 | 256 KB | sub ROM (also the main CPU's C00000 window) |
| 0x080000 | 64 KB | Z80 ROM |
| 0x090000 | 128 KB | PCM |
| 0x0B0000 | 256 KB | main opcodes (FD1089B/bootleg sets only; else a mirror of main) |
| 0x0F0000 | 1 MB | sprite ROM |

Ports: main cache, sub cache (dual-decoded for the window), Z80 cache,
PCM, sprite line fetch. Fewer clients than either parent; the X Board
priority scheme carries over.

BRAM, following the X Board's choice to keep tile and road ROMs out of
SDRAM: tile ROM 96 KB, road ROM 32 KB, zoom PROM 8 KB, MCU ROM 4 KB,
FD1089B key 8 KB (all loader-filled), work RAM 16 KB, sub RAM 16 KB, road
RAM 4 KB, tile RAM 32 KB, text RAM 4 KB, sprite RAM 4 KB plus the
renderer's private copy, palette 4 KB, Z80 RAM 2 KB, caches and line
buffers. About 240 KB before the framework's ~40 blocks — comfortable
against the 553-block ceiling both parents pressed up against. If a fit
ever needs blocks back, the tile ROM's SDRAM cache is the known lever.

Shared RAM: two 68000s (three masters on Space Harrier, with the MCU
bridge) on sub RAM and road RAM. The Y Board arbiter is the reference:
hold from a read until the holder's next bus cycle, RMW write served
first, timeout. The MCU bridge joins as the lowest-priority master into
the whole main map (open question 2 for what the real board does to the
68000 meanwhile).

### Modules

| File | Role |
| --- | --- |
| `rtl/sh_pkg.sv` | rewrite: constants, SDRAM map, stream layout, `board_desc_t` |
| `rtl/sh_core.sv` | board top: two `sh_m68k_bus` + caches, shared-RAM arbiter, PPI wiring, IRQs, MCU bridge |
| `rtl/io/sh_i8255.sv` | the PPI, mode 0 plus the mode-1 port-A output handshake |
| `rtl/video/sh_tilemap_5012.sv` | 4-page tile + text line renderer (315-5011/5012) |
| `rtl/video/sh_road.sv` | the netlist-port road, HANGON/SHARRIER variant bit |
| `rtl/video/sh_sprite.sv` | line-based sprite engine, HANGON/SHARRIER field decode variants, zoom ROM |
| `rtl/video/sh_mixer.sv` | layer order, priority compare, both shadow rules, palette banks |
| `rtl/cpu/mcs51/` + `rtl/cpu/sh_mcu_bridge.sv` | vendored 8051 core (open question 3) and the main-bus window |
| `rtl/cpu/sh_fd1089b.sv` | table decrypt between cache and main CPU (M8) |
| `rtl/audio/jt03/` | vendored YM2203 (M5) |
| `verif/models/tilemap_hangon.py`, `road_hangon.py`, `sprite_hangon.py`, `sprite_sharrier.py`, `mixer_hangon.py`, `i8255.py`, `fd1089.py` | golden models, ported line for line from MAME |

### ROM stream and descriptor

`tools/pack_roms.py` and `tools/gen_mra.py` share `tools/romsets.py`. The
index-0 stream is the 64-byte descriptor, the SDRAM regions in slot order
(a straight copy, as on both parents), then the BRAM regions:

| Region | Slot | Loader | Stream offset (after the descriptor) |
| --- | --- | --- | --- |
| `main` | 256 KB | `w16` | 0x000000 |
| `sub` | 256 KB | `w16` | 0x040000 |
| `z80` | 64 KB | `flat` | 0x080000 |
| `pcm` | 128 KB | `flat`, FF fill | 0x090000 |
| `mainops` | 256 KB | `w16` / generated | 0x0B0000 |
| `sprite` | 1 MB | `w16` or `x32` per set | 0x0F0000 |
| `tile` | 96 KB | `flat` | 0x1F0000 |
| `road` | 32 KB | `flat` | 0x208000 |
| `zoom` | 8 KB | `flat` | 0x210000 |
| `mcu` | 4 KB | `flat` | 0x212000 |
| `key` | 8 KB | `flat` | 0x213000 |

`w16` and `flat` exist; `x32` (LOAD32_BYTE groups of four,
`<interleave output="32">`) carries over from the X Board's sprite loader.
The trailing region ships unpadded per the Y Board M0 rule; sets without
an MCU or key simply end earlier. Streams run 1.9-2.1 MB.

The descriptor (`board_desc_t`, `descriptor()`):

| Byte | Field | Values |
| --- | --- | --- |
| 0 | game id | 0 hangon, 1 sharrier, 2 enduror, 3 shangon-conversion, then per-need |
| 1 | flags | bit 0 sharrier map+video (map, sprites, road, mixer, 2-bank palette), bit 1 CPUs at 10 MHz, bit 2 i8751 present, bit 3 FD1089B, bit 4 FD1094 (M9), bit 5 fetch opcodes from `mainops` |
| 2 | sound board | 0 YM2203 (PCM at 8 MHz), 1 YM2151, 2 2x YM2203 |
| 3 | sprite banks | hangon 8, shangon* 14, sharrier/enduror 8 |
| 4 | ADC reverse mask | hangon/shangon* 0x01, sharrier 0x03, enduror 0x08 |
| 5 | analog mode | see Controls |
| 6-63 | reserved | 0 |

### Controls

One ADC0804 behind a 4-way mux (PPI1 bits 3:2). Modes:

| Mode | Games | Channels |
| --- | --- | --- |
| 0 | hangon, shangon* | steering 0x20-0xE0 reversed on 0, gas on 1, brake on 2 (ride-on hardware: gas tops at 0xA5, brake 0xD2 per the driver header) |
| 1 | sharrier | stick X on 0 and Y on 1, both 0x20-0xE0 reversed |
| 2 | enduror | gas on 0, brake on 1, bank (stick Y, rest 0x20) on 2, steering full-range reversed on 3 |

`sh_ana_shape` and the X Board's range mapping carry over; wheels and
sticks follow the parents' feel decisions when M6 tunes them. Buttons and
DIPs come from MAME's port definitions per set; the SERVICE-port oddities
(Enduro's start on bit 6, Space Harrier's three buttons, the ride-on foot
switches) live in the MRA button lists.

OSD stick options: Stick (D-Pad, Analog, Analog+D-Pad), the response
curve and range from the parents, and since M7 "Stick re-centering"
(default On). On is the arcade stick: it springs back to centre and the
game positions the player from the deflection, so letting go re-centres
the Harrier. Off makes the stick a held position: a d-pad direction walks
it 8 counts a frame and stops where it is released, an analog deflection
past the dead zone sets it and letting go leaves it there (the user's
request after the first playable Space Harrier build, 2026-09-05).

### Verification tooling

Everything carries over: `mame_capture.py`/`frame_diff.py`,
`mame_trace.py`/`trace_compare.py` (two CPUs here; the i8751 is verified
through its effects on the main map, not a third trace), `wav_compare.py`.
`board_check.py`/`frame_check.py` were dropped in the scaffold copy and
get rebuilt for M2 in the Y Board's final shape, including per-consumer
dump timing (`+dumpframe` dumps each RAM at the moment its renderer reads
it; the road renders from live RAM, so its dump point is the line being
drawn). Golden data in `verif/golden/<set>/`; each milestone gates on
`verif/board/check_mN.sh`.

## 4. Milestones

One branch per milestone; gate script passes before the next starts; sim
on the Mac, Quartus on the Windows box, hardware by the user.

| M | Scope | Pass criterion |
| --- | --- | --- |
| M0 | Trim: `sh_pkg` from section 3, emu top to an `sh_core` stub on the 6.2937 MHz timing, delete math/fb_if, `romsets.py` with `hangon`, `x32` loader, descriptor, MRA, `check_m0.sh` | lint + `tools/tests` green with the hangon zip; stub fits with slack; M10K baseline recorded |
| M1 | Two 68000s + caches, shared sub/road RAM with the RMW-hold arbiter (interface shaped for the i8751 as a third master from the start), both PPIs (mode 1 latch handshake), ADC0804, inputs, IRQ4, display enable, Z80 stub. Side study, before any MCU RTL exists: disassemble the 315-5163A ROM and trace it under MAME to settle the 40385 handshake and the IPL protocol (open question 2) | cocotb: i8255 and ADC exact vs models, sampled at the CPU latch point; both PC traces track MAME (hangon, 120 frames, parent thresholds); IRQ4 on the same frame/line; a written-up 8751 contract in this doc |
| M2 | Tilemaps and text (315-5011/5012), palette, `board_check`/`frame_check` rebuilt | model exact on captured VRAM; RTL exact per layer on the same dumps; board tile/text frame exact from the RTL's own dumps |
| M3 | Road, HANGON variant | model exact on captured road RAM for attract frames; board frame exact with road + tiles |
| M4 | Hang-On sprites + mixer + 3-bank palette effects | full frames pixel-exact vs MAME (hangon) at three capture frames, `--step-ok` residual rules |
| M5 | Sound: jt03 + 315-5218 at 8 MHz + the mode-2 latch path, mute, Z80 reset | PCM cocotb exact; attract envelope correlation >= 0.9 vs MAME recording (planned 0.95; passed at 0.94 — the per-second residual is spread evenly through the music with no structured outlier, so it reads as SSG/FM fine-structure phase, not a chaseable bug; see M5 findings) |
| M6 | Hardware bring-up: Hang-On playable, controls, DIPs, OSD, timing closure (no NVRAM on this board), `hangon1/2/vf` clones | STA clean; 30 min attract; user's hardware checklist |
| M7 | Space Harrier: sharrier map + 10 MHz enables, SHARRIER sprites (x32 fetch), road/mixer/palette variants, MCS-51 + bridge — a full main-bus master per the 8751 contract in docs/notes, and the game's only main-CPU interrupt source | sharrier boots through the MCU in the bench; frames vs MAME; plays on hardware |
| M7b (optional) | Space Harrier gamepad feel: the d-pad as MAME drives an analog port from keys (keydelta 4 a frame toward the edge, the same rate back to centre when released) instead of the instant full deflection; possibly a rate option and the same for Hang-On's steering | plays comfortably on a gamepad (the user's call); the frame-900 gate unchanged since the attract mode ignores the stick |
| M8 | Enduro Racer: FD1089B, YM2151 board (jt51 + PCM at 4 MHz), `enduror1` on the 2203 board, bootleg opcode slot, `endurob2` 2x2203 | enduror + enduror1 frames and sound vs MAME; decrypted sets as cross-checks; plays on hardware |
| M9 | Super Hang-On conversions: `shangonrb` (hangon map at 10 MHz + 2151 board), then FD1094 for `shangonro`/`shangonho` | frames vs MAME; plays on hardware |
| M10 (optional) | Board reference for porters and emulator devs: recover the real PAL/PLS equations from the dumped fuse maps (315-5118/5119/5120, 315-5103, 315-5121) with MAME's jedutil and check them against our decode — worth pulling earlier if they answer an open question; then a curated hardware write-up with block diagrams (buses, arbitration, clocks, resets, per-line renderer timing), the sound byte-stream protocol, and the i8751 contract, every claim labelled primary-source or verified-reconstruction. No pinouts or analog values we cannot verify; cite the service manual for those | equations match or correct the RTL's decode; the doc stands alone for someone porting the core without this repo |
| M11 (optional, after M8) | Enduro Racer 60 fps mode: an opt-in OSD CPU-speed for both 68000s. Measured in MAME (2026-09-01, endurord attract demo): the game is vblank-synced but overruns frames under load, updating sprites and road on an irregular 1-2 frame cadence — a CPU-bound 60 fps engine, not a locked 30, so no ROM patch is needed, just headroom. The X Board's parked "CPU overclock" design carries over: bigger increments in the existing fractional clock-enable accumulators, both CPUs together, everything else (frame timing, sound, ADC, renderers, watchdog) at hardware rate. First step is re-measuring during real gameplay, where load is highest, in case anything is tied to a half-rate counter after all | sim: the update-cadence probe shows every-frame updates at the chosen speed in scenes that dropped frames at 10 MHz, with the sound handshake and watchdog undisturbed; hardware: the user's feel test on the DE10, default speed stays the PCB's 10 MHz |

M0 findings (2026-08-31). The gate is green end to end: lint, emu
elaboration, the timing smoke test (262 lines, one vbl_irq line at 224),
the three carried chip tests retuned where the board differs (the
315-5218 test now runs BANK_512 — shift 12, mask 0x70 — and the new
0x090000 PCM base), the board bench building and running the gradient
stub, and the stream tools byte-identical between packer and MRA against
the real hangon.zip (stream 2.07 MB). The first Quartus fit: the
fractional-VCO PLL delivered exactly 50.3496 / 100.6992 MHz (fit.rpt
shows the requested frequencies verbatim), every STA category positive
(worst emu setup slack 2.629 ns on clk_ram, worst hold 0.248 ns), and
the M10K baseline is 69 of 553 blocks / 7,386 ALMs — the framework plus
SDRAM, loader and the stub, before any board RTL. One bench bug worth
remembering: the PPM writer lost pixel (0,0) of every frame because the
file opened on a nonblocking flag in the same clock the pixel arrived;
the parents' core pipeline latency had always hidden it.

M1 findings (hangon, 120 frames). Both CPUs track MAME's executed-PC
trace at 99.87% (main, 58 resyncs) and 99.85% (sub, 60) on the first
full run — far inside the parents' thresholds, this board having no
three-way shared-RAM traffic. The main CPU's vblank IRQ4 (held until
acknowledge) enters its handler exactly 100 times in both runs, the
same frames; the sub's IRQ4 is a level the main holds through PPI1
port A bit 6 from line 224 to 231 each frame, and its handler re-enters
within that window a DTACK-latency-dependent number of times (MAME 249
entries, RTL 243 over the run) — the Y Board's sub X shape, and the
gate gives it a tolerance. The mode-1 PPI handshake works against a
Z80 stand-in that pulses /ACK ~2 us after /OBF falls; the real Z80
replaces it in M5. Two facts worth keeping: MAME's PORT_REVERSE on
this board is always 0x100 - value (every reversed channel has
min+max = 0x100), which is one count off the carried module's
255 - value and is fixed in `sh_adc0804` and its model; and the
sh_m68k_bus wrapper now takes its two fx68k phase enables directly,
since this board needs /8 (Hang-On) and a fractional 10 MHz
(accumulator, 26032/65536 per clk_sys) rather than the parents' /4.
The i8751 side study is in docs/notes/i8751_315-5163a.md (see open
question 2): the bridge must be a full main-bus master, IRQ4 once per
vblank is the whole IPL story, and the 40385 suppression is a MAME
reset-ordering patch the RTL should not copy.

M2 findings (hangon). The Python model (verif/models/tilemap_hangon.py,
a per-pixel port of tilemap_16a_draw_layer) matched MAME's screenshots
on every tile-opaque pixel of six captures on the first run — including
f900's 17,558-pixel scores screen and the scrolling f1500 — the only
sub-100% capture being in-game f2400 (87.6%), whose diff map is exactly
the bike and roadside sprites covering background tiles. The RTL
renderer (built on the X Board's line-renderer shape) is pixel-exact
against the model on all six captures and on a synthetic run with row
and column scroll asserted; no hangon capture ever enables those (PPI
port C bits 2:1 stay high even in-game), so the synthetic run is their
only coverage. Two bugs found on the way, both worth remembering: the
scroll-register capture read the text RAM one cycle early — everything
landed one register late (xscroll got the page-select word) — and four
captures still passed because their fg/bg layers are entirely
transparent (title and scores screens are text-only); only scroll-heavy
captures exposed it. And the board bench rendered a solid palette-
entry-0 screen because nothing loaded the tile ROM BRAM — the bench
bypasses the ioctl loader, so pack_roms now emits per-plane tilerom
hexes and the bench passes +tilerom. Hang-On's title logo turns out to
be sprites, not tiles, which is why the tile layers are so sparse
before M4. The board path (CPU writes -> RAMs -> renderer -> mixer ->
palette) is pixel-exact against the model rendered from the RTL's own
+dumpframe dumps at frame 120. MAME's Lua cannot engage hangon's
service mode (field found, set_value ineffective — the X Board had the
same limitation), so test-mode screens wait for hardware.

M3 findings (hangon). The road model — a per-pixel port of MAME's
netlist emulation, HANGON semantics — composed with the tile chain
turned model_check into a FULL-frame comparison: f900 matches MAME's
screenshot on all 71,680 pixels, f60 at 99.78%, and every other
capture's deficit is exactly its sprites (f300's 76% is the title
screen behind the big HANG-ON logo sprite; its diff map spells the
logo). The RTL renderer is pixel-exact against the model, PLYCONT
included, on all six captures, and the board path with the road in the
mixer is pixel-exact from its own dumps at frames 120 and 1500. The
same RAM-cadence bug bit a third time before the gate caught it: phase
B consumed ROM bytes one clock after the address registered, stale at
every 8-pixel group boundary and invisible inside a group — the fix
primes each pixel's fetch from the next-state values at the previous
phase B, and the module comment now names the two-cycle cadence
outright. The title screen's proper black backdrop comes from the
road's background pass (the M2 palette-entry-0 base was a stand-in).
The SHARRIER variant bit is implemented and untested until M7's
captures; the road renders from live shared road RAM with no
buffering, so the per-consumer dump question stays quiet only because
the attract writes road RAM during vblank (open question 9 stands).

M4 findings (hangon). The sprite model closed the loop the milestone
plan promised: with every layer composed, all six captures match MAME's
screenshots on all 71,680 pixels — the first full-frame exactness with
nothing excluded. One model bug found: set_local_origin(189, -1) means
sprite rows land one screen line DOWN (screen y = row + 1); the first
guess of -1 showed up as one-pen-off colours on the slanted logo art,
and the palette index MAME actually displayed pinpointed it. The RTL
renderer keeps MAME's row-base accumulator in word 7 of a private copy
of sprite RAM, taken once per frame at line 260 (after the game's
vblank list writes) with word 7 initialised from word 3, then walks
the list per line, one source nibble per clock, ROM words from SDRAM
p2 cached a 128-bit burst at a time. It is pixel-exact against the
model on all six captures and the board is pixel-exact from its own
dumps (sprite RAM dumped at the copy moment, per-consumer timing) at
frames 120, 300 and 2400. Two RTL bugs found in review before any
simulation (the colpri assembly and the header-read cadence) and one
by Icarus that Verilator's x-assign had hidden: the renderer ran
before the first list copy existed and X-poisoned its FSM — rendering
now waits for the first copy. The shadow pen goes through the
palette's new eff_force input (Hang-On's three-bank layout: SHADE0
picks shadow or hilight globally, MAME's ~portB & 0x40 arithmetic
selecting hilight when the bit is low). The Y Board's zoom-clamp open
question does not apply here: this zoom ROM is shrink-only row-skip.

M5 findings (hangon). The sound board took four real fixes and one
long lesson in trusting instrumentation. The fixes first. The main
PPI runs in i8255 mode 2 — the game programs control word 0xC0 and
uses the bidirectional mode's output half as the sound latch; our
first model only engaged the handshake for mode-1 output and the Z80
never saw an NMI. Mode 2's read side matters as much as its write
side: the input half is unwired on this board, so IBF must read as 0
and a port A read returns an empty buffer, not the output latch —
with the pins version the main CPU saw a phantom response and its
sound sequencer walked off. Second, the vendored jt12 cleared the
YM2203 timer flags wrong twice, and MAME's ymfm was the faithful one
both times: the reg 0x27 flag-reset bits are one-shot commands, not
levels, and the clear lands when the chip processes the write at the
end of the 32-cycle busy window, not at the bus edge — Hang-On's
driver reads the flag as still set through the busy window. Both are
documented local patches in rtl/audio/jt03/, joined later by a third:
jt03 instantiates its SSG with COMP=1, a 29 dB compressed volume
table meant for FPGA mixing convenience, where the measured AY curve
(and ymfm) spans about 44 dB at 3 dB per step. Hang-On's music rides
the SSG at volumes 3 to 10 and fades through them every phrase;
COMP=0 is the faithful table, worth having on its own merits — but
measured against the gate it moved the envelope correlation by 0.001.
The number that was actually stuck at 0.88 was the bench's fault, not
the core's: the audio dump's 16-bit sample-rate accumulator truncated
48 kHz to 47.63 kHz, a 0.78% time warp that no single alignment lag
could undo — chasing it as a mix-balance problem went nowhere (a
least-squares refit of the three component gains against MAME's
envelope topped out below the pass line, which is what finally said
the shape, not the balance, was wrong). A 32-bit accumulator later,
the same core passed at 0.940 with sample-level correlation up from
0.25 to 0.77. Last, the simulation
now zero-fills every game-visible RAM: the sound driver tests C01F
before ever writing it, gating the whole song-activation path. MAME
zero-fills its RAM regions and the FPGA's M10K blocks power up
cleared, so the only environment that disagreed was Verilator's
x-assign fast handing back 0xFF — a divergence with no counterpart
on either reference, which cost a day. The policy is now standing:
any RAM the game can read before writing gets a sim-only zero init.

The lesson. With all three fixes in, the RTL still played the attract
theme forever while MAME's recording went silent from 6.8 s to 16.8 s,
and the YM register trace captured from MAME agreed with the RTL, not
with MAME's own wav. The resolution: the Lua read/write taps used for
that trace had flipped MAME's own sound driver into the same
looping behaviour — the CLAUDE.md warning about taps, in a new form.
A recapture with a single write tap reproduced the real wav exactly
and showed the truth: the attract theme is a one-shot; the driver
ends it itself at frame 410 (volumes to zero) and replays it
autonomously at frame 1011. No mute is involved — the main CPU
writes the PPI's port C exactly once, 0x07 at boot. The remaining
divergence is a race inside the sound program: command 0x96 starts
the music (priority 7, engine state at C040) and a coin's 0x84
starts the coin sound (priority 4, state at C120), and the two meet
in the driver's SSG channel arbitration with interrupts enabled. On
the clean-MAME side of the race the lower-priority coin sound is
rejected and the theme ends on schedule; on the other side — where
both the tapped MAME and our cycle-timed board land — the coin
sound steals SSG A and B mid-tick and the theme never finds its
ending. Clean MAME's outcome is robust to the coin's frame (tested
45/90/200), so the gate scenario simply avoids the race: no coin,
which also matches the M4 video goldens and exercises the
end-of-song path the old coin scenario never reached. Whether real
silicon lands with MAME or with us only a PCB can say; open
question 11 keeps it.

M6 findings (hangon + clones). Not the quiet milestone it first
looked like. The user had already played Hang-On on the DE10 before
M6 started and the build's timing was clean (worst setup slack
+0.375 ns, all TNS zero, 17,770 ALMs at 42%) — and then the
hardware checklist earned its keep: half a minute or more into a
race, inconsistently, the music died and new effects went wrong,
video and controls untouched, everything recovering at race restart
or game over. That recovery timing named the victim — those are the
moments the game pulses the Z80's reset through port B bit 5. The
main CPU's latch writer (0x3E76 in the Rev A program) explained the
rest: it sends eight bytes a frame with a fixed ~33 microsecond
delay between them, checks /OBF once without waiting, counts a miss
in its own drop counter at 20C460 and blindly overwrites. An
overwritten byte raises no new /OBF edge, so the Z80 misses an NMI —
and the NMI handler is an eight-slot rotating coroutine, so one
missed byte shifts every later byte one slot for good. On the PCB
this never happens: the Z80 runs from private zero-wait ROM and
always makes the budget. Our Z80 ran through a 1 KB cache over
SDRAM, the one component able to stall it unboundedly, and the only
one of these boards where that matters — the parents' sound latches
are not a hard-real-time stream. Forty-five seconds of simulated
racing (coin, start, half throttle) produced zero dropped bytes, so
the logic is sound at nominal timing and the failure lives in the
physical margin of the cache path (its fill logic placed in MLABs,
the same read-marginality class that bit the Y Board's DDR3 data).
The fix removes the class instead of arguing with it: the full
32 KB Z80 window now lives in stream-loaded BRAM, zero-wait like
the real board, the cache and its wait states deleted and SDRAM p5
freed. The M5 audio gate repeats its 0.942 exactly on the new path.
One self-inflicted casualty along the way is worth recording: a
Makefile edit that redirected output through a leftover symlink
truncated the golden z80.hex to nothing, and the resulting
silent-audio gate failure briefly looked like the fix was broken —
check the artifact, not the exit code, and never write through a
path a previous run may have left as a symlink.

The BRAM fix then shipped broken, and the way it broke is the more
useful lesson. On the DE10 the rebuilt core was silent from boot,
and the service menu's sound test froze the controls on some
entries. The freeze was the tell: unlike the in-game writer, the
test menu waits for the Z80 to take each latch byte, and a Z80 that
never answers parks the main CPU on /OBF forever. So the Z80 was
dead from power-up, and the reason was one line in sh_core: the
loader forwards the whole 64 KB Z80 stream slot (32 KB of ROM plus
zero padding) into a BRAM addressed by 15 bits, so the padding
wrapped and wrote zeros over the ROM it had just loaded. No
simulation could have caught it, because none of them runs the
ioctl loader — the bench fills that BRAM with $readmemh and ties
the loader's write port off. That is the blind spot to remember:
anything that only exists on the hardware side of the loader
(stream slot sizes, wrap arithmetic, side-channel writes) has no
gate. M7 puts the i8751's ROM through the same path, so a loader
unit test that plays a synthetic stream into sh_rom_loader and
checks what lands where is due before then. (Done in M7:
verif/unit/loader/test_rom_loader.py plays the first and last word of
every slot, checks the SDRAM address and the BRAM strobe for each, the
Z80 dual write, that nothing past OFF_END is taken, the descriptor
fields for two sets loaded back to back, and that sh_pkg's OFF_*
constants equal the pack tool's slot table.)

With the ROM loading properly the sound came back, and the next
race brought a third failure with a very different signature: not
silence but distortion, part way through a race, and reproducible
on demand in the service menu by switching quickly between sound
test entries 11 to 15. The shape of that reproducer — restarting
sounds on top of sounds still playing, with the latch protocol
otherwise behaving — pointed at the PCM chip's voice restart. Our
315-5218 engine spreads each channel over tens of clocks: it reads
the current address at E_LOAD, waits for SDRAM, and writes address
plus delta back at E_ACC. A Z80 write of a new start address landing
inside that window was overwritten by the stale write-back, and the
voice went on playing from old-plus-delta — noise from somewhere
else in the sample ROM, and for a looped voice like the engine note,
noise until the driver reloaded it. MAME never has this race because
segapcm's write handler runs the stream up to "now" before applying
the byte, so the write always stands. The engine now tracks a dirty
bit per write-back register (0x84, 0x85 and the end-of-sample stop
bit in 0x86) for the channel in flight and skips its own write when
the Z80 got there first, and the Z80 write sits last in the always
block so a same-clock collision goes its way as the comment always
claimed. The existing unit test only ever reprogrammed channels
between ticks, which is why this survived M5; the new
write_during_engine test lands writes in every engine state of a
busy channel and failed on the first tick against the old RTL.

Three hardware-only sound failures in a row earned a proper audit of
what the bench does and does not model, because "the gates pass"
had stopped meaning "the board works". The list, so nobody has to
rediscover it:

- The Z80 itself. The FPGA runs the VHDL T80s with a clock enable;
  every simulation up to this point ran tv80, a different core on a
  derived 4 MHz clock, because Verilator does not read VHDL. The
  T80s samples read data one enable period (about 12 clocks) after
  it raises RD, where tv80 gives a device half a T-state more; it
  edge-detects NMI on every clock and holds it; it asserts WR in T2.
  None of that had been simulated. GHDL 6's synthesizer converts the
  T80 to Verilog (verif/board/t80/gen.sh, one width-mismatch patch
  Quartus tolerates and GHDL refuses), and the bench now runs the
  converted T80s by default, tv80 staying as the fast option
  (Z80=tv80). Every device on the Z80 bus answers a read in one
  clock and takes a one-clock write strobe, so the tighter T80s
  window is met everywhere; the point is that this is now checked
  by running the real core, not by reading. And the first run with
  it moved the M5 attract gate from 0.942 to 0.972 envelope
  correlation against MAME (sample correlation 0.775 to 0.951): the
  hardware's Z80 is the more faithful one, tv80 was the outlier.
- The ioctl loader. The bench fills the BRAMs with $readmemh and
  ties the loader off, so stream slot arithmetic is untested (the
  wrap bug above). Still open; a loader unit test is due before M7.
- SDRAM. The model serves its ports round-robin at a fixed 12 clocks
  each; the real controller is fixed-priority (main CPU, sub CPU,
  then the PCM port) with real row and refresh timing, so the PCM
  engine's fetch latency on the board is both longer and burstier
  than anything the bench produces. The engine drops a tick silently
  if one arrives while it is still fetching, which on the board would
  read as a slow, flat pitch on every sample.
- Physical margin: MLAB placement, hold on multi-cycle paths, the
  class that ate the SDRAM cache. No simulation sees it; only the
  fitter reports and the board do.
- The MiSTer side of the audio path (the emu top's AUDIO_L/R, the
  framework's resampler) is outside the bench, which taps the mixer
  directly.

Because the last two items cannot be simulated, the board now
reports what it sees: two sticky flags in sh_core, cleared by reset,
drive the DE10's LEDs. The disk LED lights the first time the main
CPU overwrites a latch byte the Z80 has not taken (the exact event
the 68000 counts at 20C460 and the bench logs as SNDOVR); the user
LED lights the first time the PCM engine misses a tick (PCMLOST in
the bench). One glance at the board during a crash then says which
mechanism it was, or that it was neither.

The first hardware run with the LEDs answered the mechanism question:
the disk LED lit when the sound broke, so the 68000 did overwrite a
byte the Z80 had not taken. That is the coroutine shift, still there
with the zero-wait ROM. And the bench with the real T80 cannot make
it happen. The numbers, measured in the bench during a race (the
SNDTIME lines, worst case per 100 frames):

| | value |
| --- | --- |
| 68000 latch writer, shortest gap between bytes | 53.4 us (21-iteration dbra, cache-resident) |
| Z80, worst write-to-read latency | 16.1 us |
| PCM SDRAM latency 12 vs 48 ram clocks | no change to either |
| overwrites in 15 s of racing | 0 |

The 68000 has one writer of the latch (0x3E76, called once per frame
at the end of the vblank handler with interrupts masked), the Z80's
NMI handler is three instructions to the port read, the driver never
executes HALT, and MAME drives the NMI from /OBF as a level exactly
as we do. So a missed byte on the board means the Z80 was held off
the latch for more than 53 us, three times its worst measured
latency, and nothing in the RTL can do that except a Z80 reset (port
B bit 5) or the core's pause, which stops both CPUs alike. The
on-screen overlay (OSD "Sound debug overlay": overwrite count and a
/OBF-stuck flag) exists to split the two remaining stories: one late
byte and a shifted coroutine, or a Z80 reset that lands with a byte
pending, after which /OBF stays low, no NMI edge ever comes, and the
sound program is deaf until something re-initialises the PPI.

The overlay grew until it could show the T80's own state machine (a
DBG port added to the vendored core: NMI latch, NMI/INT cycle,
prefix, M-cycle, T-state, HALT, bus-ack, IFF1), sampled at the first
overwrite and again one millisecond into the blind window, plus
counts of opcode fetches, NMI vector fetches and latch acks while
blind. The second race with it gave the answer. Fifty-three
microseconds after the byte was written, with /NMI held low the whole
time, the Z80 was executing the YM2203 busy-wait at 0x09C6 with its
NMI latch clear: the edge had been lost. A millisecond later it was
running its own power-on initialisation from address 0, in the LDIR
that clears the work RAM, and the reset counter, which samples the
port B reset bit every clock, still said one reset since boot. Two
and a half milliseconds after that an NMI was accepted and the port
read, though /NMI had never risen in between. No software path does
any of those three things, and the bench with the converted T80,
swept across 406 phases of that loop, takes the NMI every time.

The first reading of that was a runt pulse on the T80's asynchronous
reset - the core's reset line is a combinational OR that includes the
PLL's lock output, and the T80 and jt12 were the only blocks fed it
raw. It was wrong. The reset was registered (it stays registered: an
asynchronous reset into vendored cores is a hardware-only failure
class no simulation can show, so registered resets at every such
boundary are the rule now), a catcher flop with an asynchronous set
was put on the raw line, and the next crash came with the catcher
dark. Recorded here because it is the kind of confident diagnosis
this file exists to warn about.

What followed was a bisection by builds, one variable at a time,
each with the on-screen overlay reading the board back:

| build | change | result |
| --- | --- | --- |
| netlist | Quartus given the GHDL-generated Verilog of the T80 instead of the VHDL, so board and bench share one netlist | same crash, same signature |
| insurance | /NMI re-issued after 32 us without a vector fetch | byte no longer lost; sound still derailed, gently; then a crash with the Z80 in RAM |
| stage timeouts | per-stage latency capture inside the T80 | NMI cycle started, no vector fetch, then an INT acknowledge at 0x0037 - the address only reachable by falling through the JP at the end of the init code |
| timing report | worst paths into the T80 by name | +4.06 ns setup on the program-counter update, +0.44 ns hold; nothing marginal |
| tv80 | the bench's Verilog Z80 on the same clock enable | no crash |

So the T80, as this board runs it, occasionally fails to load its
program counter at the end of an M-cycle - the NMI vector, a plain
JP - while the identical netlist executes 90 s of the real protocol
in Verilator without a fault, every timing corner is clean with
margin, both tools read the netlist without a latch or a multiple
driver, no memory is in an MLAB, and every input to the core is a
register. Why is not explained, and this file does not pretend it
is. What is established is that tv80, on the same enable, in the
same environment, does not do it, so tv80 is the Z80 of this core
and the T80 stays only as the bench's cross-check (make ... Z80=t80,
the netlist in verif/board/t80). The edge insurance stays: it never
fires on a Z80 that behaves, and the bench logs it if one ever does.
The on-screen overlay and the LED flags were debug scaffolding and
came out again once the answer was in; the sticky flags behind them
(latch overwrite, PCM tick lost, Z80 fetch outside ROM) remain as
bench log lines.

Lessons for the file, in the order they were paid for: check the
artifact, not the exit code; when the RTL is provably identical in
both worlds, stop reading it and instrument the board; put the
instrument's meaning in the sticky flags, not in running balances a
transient can cancel; and a bisection by builds beats a theory by
reading, however good the theory sounds.

What was missing before the crash showed up was everything around
the game. The three clone sets went
into romsets.py the Y Board way, full explicit entries: hangon1 (the
pre-Rev-A program, four main ROMs), hangon2 (the ride-on, its own
main and sub programs plus the rider's foot switches on SERVICE bits
7:6 — wired unconditionally in sh_core since every other set leaves
them IPT_UNKNOWN, and two extra buttons on the MRA list), and
hangonvf (the Spanish bootleg with the logo art redrawn — its
program ROMs match the parent byte for byte under bootleg names, so
the MRA references the parent's files and only the redrawn tiles and
three sprite pairs come from the bootleg's own). One trap: MAME
names the ride-on's zoom PROM epr-6844.ic119 for its board socket,
but the zips only carry the parent's identical epr-6844.ic123 — the
set list has to use the name a zip actually contains, not the name
the board silkscreen would give it. Each clone passed the full-frame
board check against its own MAME capture at frame 300, first try —
the core needed nothing beyond the foot-switch wire, which is what a
scaffold three boards deep is for. The 30-minute attract soak and
the control-feel checklist stay on the user's bench.

M7 plan (sharrier, sharrier1). Started 2026-09-03 on branch m7-sharrier,
straight after the M6 release. What the milestone has to deliver and
in what order:

1. Sets and goldens: `sharrier` and `sharrier1` in romsets.py (done, the
   tool tests check every CRC against the zips), MRAs generated, golden
   hexes packed, MAME attract captures at frames 900/1500/2400 (frame
   300 is still the black boot screen: the MCU's ROM checksum takes a
   while).
2. The MCS-51: jotego's jt8051 (jtcores, GPL-3, 2026, verified there
   against Bionic Commando's 8751), vendored under rtl/cpu/jt8051 with
   its two generated microcode includes; `jtframe ucode` produced them
   from ucode/8051.yaml and the command is recorded next to the files.
   It runs on the core's 8 MHz enable (twelve pulses per machine cycle,
   with the idle clock between pulses the core insists on), 4 KB
   internal ROM in BRAM from the stream's MCU slot, 128 bytes of
   internal RAM, INT0 from vblank.
3. The bridge (rtl/cpu/sh_mcu_bridge.sv): the 8751's MOVX bus is a full
   master on the main 68000 bus per the contract in docs/notes. Window
   from P1 bits 6,5,4,3 onto A20,A18,A17,A16 with A19 forced low, the
   16-bit MOVX address with A0 inverted, one byte per access. It takes
   the bus the way a second master takes a 68000's: hold the 68000 (the
   wrapper's halt line, fx68k's HALT, which stops the CPU at the end of
   its current bus cycle), run the byte access through the same decode
   the 68000 uses, release. The MCU paces itself with settle delays and
   double reads, so the extra latency is nothing to it. P1 bits 2:0,
   inverted, are the 68000's IPL: the only level the program ever drives
   is 4, once per vblank, and it is latched and cleared on the 68000's
   interrupt acknowledge, not on the MCU's release. The main CPU's own
   vblank interrupt is disabled on sets with an MCU (MAME does the
   same); the MCU is its only interrupt source.
4. The sharrier main decode, descriptor-selected next to the hangon one:
   work RAM at 040000, tile RAM 32 KB at 100000 (the tilemap reads the
   first 16 KB), text at 108000, palette at 110000, sub RAM at 124000,
   sprite RAM 4 KB at 130000, PPI0/inputs/PPI1/ADC at 140000 in the
   sharrier order, road RAM at C68000, the two MCU no-op windows.
5. Video: SEGA_SHARRIER_SPRITES (32-bit fetch, eight pixels a word,
   128 KB banks, 6-bit colour, 6-bit zooms through the same zoom ROM)
   as a variant of the line renderer; the road's SHARRIER bit is
   already in; the palette's two-bank (normal/shadow) arrangement.
6. Gate, check_m7.sh: the bench boots sharrier through the MCU (the
   checksum passes, IRQ 4 arrives, the game runs), frames 900/1500/2400
   match MAME layer by layer, and a tap logs any MCU zero-write to 40385
   after the 68000's first heartbeat. Then hardware.

M7 findings so far (2026-09-03, in progress). The MCU came up on the
first run that had its microcode: jt8051's generated files are three,
not two - the includes and a `.uc` image the core `$readmemb`s - and
the bench's first boot with the image missing sat silent for 53
frames, so that file is now vendored, symlinked into the bench's out
directory and registered for Quartus the way this project registers
every `$readmem` file. With it, the 315-5163A program does exactly
what the disassembly said: the internal self-check, the 0x2D-byte
block write into the palette window, the two zero writes to 40385 at
frame 17 (long before the 68000's first heartbeat, so no race), then
the main-ROM checksum. That loop samples two bytes of every eight and
double-reads each with a delay call between, about 112 machine
cycles per iteration over 32K iterations, and our MCU finished it at
frame 523; MAME's screen is still black at 450 and running by 600,
so the two agree. The first IRQ 4 reached the 68000 the same frame
and it began streaming sound-latch bytes at once.

Two frames later the board deadlocked, and the bench's master-state
line named it: the 68000 sat in a cycle at 1245A8 (sub RAM, through
the shared-RAM arbiter) with no acknowledge while the MCU waited for
the bus. fx68k samples HALT on its phase-1 enable and only then stops
starting cycles, so my grant, taken on a momentary idle, could land in
the same clock as a new 68000 cycle: the mux put the MCU's address
under the CPU's start pulse, the arbiter served the MCU with the
CPU's request, and the CPU waited forever. The grant now waits two
CPU clocks after the hold before it trusts an idle bus, and the bench
flags a start under a grant as a collision.

Two tooling holes closed on the way: mame_capture.py never told its
Lua script which map a set uses, so every Space Harrier dump had come
from Hang-On's addresses (the PPI read back as FF/FF, the tell); and
model_check.py and board_check.py learned the sharrier sprite model,
the 32-bit ROM assembly and the two-bank mixing rule. With correct
captures the golden models reproduce MAME's frames 900, 1500 and 2400
on every pixel, so they are the reference the RTL is held to next.

With the grant fixed the game runs: IRQ 4 every frame from 523 on,
the MCU idling in its vblank wait between frames, the 68000 feeding
the sound board. At frame 900 the RTL's layers compose to its own
frame on every pixel, and MAME's frame 900 is our frame 905 exactly -
71,680 of 71,680 - the five frames being where the two MCUs' checksums
end. Space Harrier is pixel-exact through an MCU-driven boot on the
first comparison; the gate (check_m7.sh) demands that equality within
a twelve-frame window, no bus collision, and no MCU write to 40385
once the game is running.

First hardware run (2026-09-03, the build before the jt8051 multicycle
constraint): the game boots through the MCU, music and effects play,
so the MCU ROM survives the loader path and the bridge works on
silicon. Two input faults showed. The stick was pinned to one corner;
the MCU is the only thing that reads the ADC in this game (its
per-frame loop at 089A selects each channel through PPI1 port A,
starts a conversion at 140031, waits about 100 us without checking
the interrupt, and stores the six results at 040492 for the 68000),
so that path is where to look, and the bench's scripted stick is the
test. Separately, the top wired pause, test, service and coin to
Hang-On's joystick bits; Space Harrier's list has three fire buttons
first, so Coin paused the core and Pause entered the test menu. The
top now picks the four bits by the descriptor's sharrier_vid.

The corner was the MCU's fallback mode, and the heartbeat race behind
it is real on our side. Bench measurements: the 68000 clears 040385 at
boot, then writes 0x5A there once at frame 10, line 93 (about 170 ms
after reset) and never again; the MCU's reset routine zeroes the same
byte twice at frame 17 (283 ms), after its internal ROM checksum and a
delay loop, and a hand count of the 8751's cycle times gives the same
280 ms, so jt8051 is not slow. From the MCU's main loop start (frame
523) its watcher reads zero, decrements its 30-frame counter and at
about frame 553 sets internal bit 22.0. In that mode the per-frame
routine replaces the six ADC bytes at 040492 with a fixed table (03 01
00 07 00 07 at 0492 with the address bit 0 inversion, so 040492 = 01
and 040493 = 03, the test menu's exact readings) and the 68000 clamps
01 to full right and 03 to full down. The earlier bench stick test at
frame 530 was inside the grace window, which is how a clean trace lied.
The bridge now drops the MCU's writes to 040385, which MAME does too;
the disassembly shows those two zeros are the only such writes. The
gate checks that the MCU never enters the fallback and that a stick
deflected after frame 900 reaches 040492/3 as 0x35 and 0xCB.

Long compares after the fix: sharrier1 matches MAME's frame 900 on
every pixel at the same +5 offset. Space Harrier at 1500 and 2400
composes from its own RAMs on every pixel but matches MAME on 79 and
78 percent, at offsets +6 and +7. Side by side the frames are the same
scene, the same background and sprites drawn the same way, a few
frames apart in the demo's animation: the alignment drifts one frame
per about 450. The MCU makes 71 bus accesses a frame (MCUTOT), each
holding the 68000 for about 25 clocks, some 42 us a frame that MAME's
68000 never loses, and the game drops a frame now and then as a
result. The real board's 8751 stalls its 68000 too, so this is the
residual the standing rule accepts: explained, not chased. The gate
compares at 900, before the drift moves the demo.

The game writes to ROM address 000032 every 30 frames or so (ROMWR in
the bench). MAME drops the write, the bus acknowledges it, nothing
changes; it stays in the log as the usual reminder.

Optional follow-on (M7b, the user's request after the first playable
build): the game is still hard on a gamepad. MAME does something we do
not: its analog ports driven from digital keys move by PORT_KEYDELTA
(4 on the 0x20-0xE0 range, so 24 frames centre to edge) each frame the
key is held and return to centre at the same rate when released
(centerdelta defaults to keydelta), so a keyboard player gets a slewed
stick rather than our instant jump to full deflection. The held-stick
OSD option added in M7 walks at 8 counts a frame and never returns;
the MAME-style slew would be the third behaviour, and probably the
right default for D-Pad mode. Hang-On's wheel already slews toward the
stick at 6 counts a frame (the Y Board's Power Drift finding).

Open: how the real board orders the two writers. Both CPUs run the
same code at the same clocks, so either the board's reset circuit
releases the 8751 well before the 68000, or something in the 68000's
first 170 ms is slower on the real bus than ours. Not knowable from
here without a board.

## 5. Open questions (MAME is the default answer until hardware says otherwise)

1. IRQ2 every 16 scanlines is in the schematics but disabled in MAME and
   no game visibly needs it. Leave it out; if a game polls for an
   interrupt that never comes, this is the first suspect.
2. Largely resolved by the M1-side disassembly of the 315-5163A
   (docs/notes/i8751_315-5163a.md, full listing alongside). The contract:
   the bridge is a full main-bus master — the MCU reads the main ROM (a
   boot checksum that must pass or it stops interrupting), lives in work
   RAM, and block-writes tile RAM, palette, sub RAM and the I/O windows —
   so M7's bridge goes through the main decode, not just the shared-RAM
   arbiter slot. It raises exactly IRQ4, once per vblank, by pulsing
   P1.2 low; latch it and clear on the 68000's IACK. The 40385 write
   MAME suppresses is two zeroing writes during MCU reset init only; in
   steady state the MCU merely polls 40385 as a heartbeat the 68000
   sets. Do not special-case it in RTL: treat it as plain work RAM, get
   the reset ordering right, and keep a bench tap that logs any MCU
   zero-write there after the first heartbeat. The MCU paces its bus
   accesses with delays and double-reads and never busy-waits, so
   arbitration latency is tolerated. Still open: whether the real bridge
   steals 68000 cycles or waits for a grant (invisible to the firmware).
3. Which MCS-51 core to vendor (jtframe's mcs51 vs other open cores) and
   its licence fit with the GPL-3 core.
4. Resolved in M5: MAME's YM2203 outputs 0-2 are SSG A/B/C and 3 is
   FM, so the segahang routes are SSG 0.05 each and FM 0.15; the mix
   in sh_soundsys_2203.sv carries them as 1/256 gain parameters with
   the 8-bit SSG channels scaled by 128, and the envelope comparison
   against MAME's recording confirmed the balance.
5. Fractional enables for the 10 MHz CPUs and 8 MHz PCM tick: precedent
   (X Board 4 MHz sound) says the jitter is harmless; watch the sharrier
   PC-trace gate for cycle-count drift beyond the parents' thresholds.
6. `shangonro`/`shangupb` CPU speed: MAME's 10 MHz carries a "not sure
   about these speeds, but at 6 MHz the road is not updated fast enough"
   comment. Take 10 MHz; a conversion of a 6.29 MHz board to 10 MHz parts
   is plausible but unverified.
7. Whether the FD1094 block reuses the X Board's decryptor as-is on the
   sub CPU (same device, different key) — likely yes, defer to M9.
8. Sharrier's 32 KB tile RAM window against the 4-page tilemap: MAME maps
   twice the displayable RAM. Confirm from captures in M2 that the upper
   half is never page-selected, and decide whether to back it with RAM
   (cheap) or mirror.
9. Road dump timing: the road renders from live shared RAM with no
   buffer, so a mid-frame write legitimately splits a frame. The
   per-consumer dump rule covers the bench; on real hardware this is
   what the games expect.
10. PCM sample rate: MAME clocks the 315-5218 at 8 MHz on the YM2203
   board and 4 MHz on the other two, ticking at clock/128 (62.5 /
   31.25 kHz). system16.com lists 31.25 / 15.625 kHz — the same 2:1
   ratio between the boards but half the absolute rate, i.e. a
   clock/256 assumption. Follow MAME (the X Board's 4 MHz / 128 tick
   matched its recordings); if M5's envelope comparison shows a
   factor-of-two pitch error against MAME's own recording something
   is wrong locally, and only a real PCB can rule between the two
   published rates.
11. The coin-during-attract channel race (M5 findings). The sound
   program's arbitration between the attract theme (0x96, priority 7)
   and the coin sound (0x84, priority 4) is decided by where the YM
   timer interrupt lands inside the command processing. MAME
   deterministically rejects the coin sound and the theme ends on
   schedule; our board — and MAME itself once Lua taps perturb its
   scheduling — lets the coin sound steal SSG A/B, after which the
   theme loops forever. If a real Hang-On board coins during the
   attract music and the music afterwards never stops, we were right
   all along; until someone tries it, MAME's side of the race is the
   reference and a hardware test on the DE10 (coin during attract,
   wait 20 s) is the cheap probe for which side our FPGA lands on.
