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
| M5 | Sound: jt03 + 315-5218 at 8 MHz + the mode-1 latch path, mute, Z80 reset | PCM cocotb exact; attract envelope correlation >= 0.95 vs MAME recording |
| M6 | Hardware bring-up: Hang-On playable, controls, DIPs, OSD, timing closure (no NVRAM on this board), `hangon1/2/vf` clones | STA clean; 30 min attract; user's hardware checklist |
| M7 | Space Harrier: sharrier map + 10 MHz enables, SHARRIER sprites (x32 fetch), road/mixer/palette variants, MCS-51 + bridge — a full main-bus master per the 8751 contract in docs/notes, and the game's only main-CPU interrupt source | sharrier boots through the MCU in the bench; frames vs MAME; plays on hardware |
| M8 | Enduro Racer: FD1089B, YM2151 board (jt51 + PCM at 4 MHz), `enduror1` on the 2203 board, bootleg opcode slot, `endurob2` 2x2203 | enduror + enduror1 frames and sound vs MAME; decrypted sets as cross-checks; plays on hardware |
| M9 | Super Hang-On conversions: `shangonrb` (hangon map at 10 MHz + 2151 board), then FD1094 for `shangonro`/`shangonho` | frames vs MAME; plays on hardware |

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
4. jt03 integration: MAME routes the YM2203's four outputs at
   0.05/0.05/0.05/0.15 — confirm which index is FM vs SSG in `ymopn`
   before wiring the mix, and match jt03's SSG level to it.
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
