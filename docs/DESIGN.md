# Sega Space Harrier / Hang-On board for MiSTer — design notes

Draft. This is the cutover plan from the Y Board core (2026-08-31); the
gaps marked TODO get filled before M0 starts, the same way the Y Board's
doc was completed before its M0. The behavioural reference is MAME 0.289
`src/mame/sega/segahang.cpp` and the device families it instantiates.

## 1. What came over and what is new

Carried from the Y Board core (see `docs/references.md` for the manifest):
the MiSTer top and Quartus project, `sys/`, the SDRAM controller and
stream loader, the fx68k wrapper with the shared-RAM-safe bus contract,
the ROM cache, the 315-5248/5249 math chips, the Z80 sound board with
jt51 and the 315-5218 PCM (bank style is a parameter; this board uses the
older 512K banking), the 315-5242 palette, the video timing, the analog
shaper, and the whole verification stack (lint, cocotb, Verilator board
bench, MAME capture/trace/diff tools, MRA/stream tooling, CI and release
workflows). The ADC0804 and its model come from the X Board.

New for this board, in rough order of appearance:
- 315-5011/5012 tilemap generator (two scrolling pages plus a text layer,
  the older variant of the System 16 tilemaps; MAME `segaic16.cpp`
  TILEMAP_HANGON). The X Board's tilemap chip is the later relative.
- segaic16 road generator, HANGON and SHARRIER variants (the X Board's
  road module is the later variant of the same device; adapt it).
- Line-based sprite generators: `sega_hangon_sprite_device` and
  `sega_sharrier_sprite_device` (MAME `sega16sp.cpp`). No framebuffer:
  these render into line buffers like the Y Board's 16B layer, which is
  the closest existing code. Space Harrier's variant adds a zoom lookup.
- YM2203 (jt03) for Hang-On and `enduror1`; an i8255 PPI; the MSM6253 is
  not on this board.
- An MCS-51 core running Space Harrier's dumped 8751 (315-5163A), with a
  bus bridge into the main 68000's address space (contract in CLAUDE.md).
- FD1089B decryption for Enduro Racer (per-key tables from MAME).
- FD1094 for the Super Hang-On conversion sets — deferred; `shangonrb` is
  unencrypted and comes first.

Probably not needed: the DDR3 framebuffer interface (`sh_fb_if.sv`) — the
sprites here are line-based. Carried anyway; M0 decides and trims.

## 2. Hardware reference (from `segahang.cpp`, MAME 0.289)

Two configurations on one board family:

| | Hang-On (`hangon`) | Space Harrier (`sharrier`) / Enduro (`enduror`) |
| --- | --- | --- |
| Main 68000 | 25.1748 MHz / 4 | 10 MHz |
| Sub 68000 | 25.1748 MHz / 4 | 10 MHz |
| Z80 | 8 MHz / 2 | 8 MHz / 2 |
| Sprites | SEGA_HANGON_SPRITES | SEGA_SHARRIER_SPRITES |
| Sound | 1x YM2203 @ 4 MHz | YM2151 + 315-5218 (SOUND_CLOCK/8); `enduror1`: 2x YM2203 + 315-5218 |
| Extra | — | i8751 @ 8 MHz (sharrier); FD1089B main CPU (enduror) |

Common: 320x224 raster, SEGAIC16VID tilemaps (TILEMAP_HANGON),
SEGAIC16_ROAD, 315-5248 multiplier + 315-5249 divider, ADC0804 at
25.1748 MHz/4/6, i8255, 315-5242-style palette. The two CPUs share RAM
(the Y Board arbiter semantics apply). TODO before M0: transcribe the
three memory maps (main, sub, sound) and the shared/road/sprite RAM
sizes from `segahang.cpp` into the placement table, as the Y Board doc
did, and settle the SDRAM map, stream layout and descriptor.

The i8751 contract, the encryption table per set, and the full set list
are in CLAUDE.md's board section; they move here with detail when the
maps are transcribed.

Sets (MAME 0.289): `hangon` (+`hangon1`, `hangon2`), `sharrier`
(+`sharrier1`), `enduror` (+`endurora`, `endurorb`, `enduror1`,
bootlegs `endurobl`, `endurob2`, decrypted `endurord`, `enduror1d`),
`shangonro`, `shangonho` (+bootlegs `shangonrb`, `shangonrb2`).

## 3. Architecture

TODO with the memory maps: SDRAM slots and stream order (romsets.py
SLOT/ORDER), the descriptor fields (game id, sprite variant, sound
variant, banks, encryption), BRAM budget. Expected shape: everything the
CPUs execute from SDRAM through the carried ROM cache; tilemap, road and
sprite ROMs streamed from SDRAM into line buffers; no DDR3.

## 4. Milestones (proposal — refine before starting)

| M | Scope | Pass criterion sketch |
| --- | --- | --- |
| M0 | Trim the scaffold: `sh_pkg`, top to an `sh_core` stub, `romsets.py` with `hangon`, stream/MRA tools, first Quartus fit | lint + tool tests pass; stub fits with slack |
| M1 | Both 68000s, shared RAM (arbiter with the RMW hold), math chips, i8255, ADC0804, interrupts, watchdog, Z80 stub | cocotb exact vs models; PC traces track MAME; IRQs on the same frame |
| M2 | Tilemaps and text layer | model exact on captured VRAM; frames vs MAME |
| M3 | Road (HANGON variant) | model exact on captured road RAM/ROM lookups |
| M4 | Hang-On sprite generator | full frames pixel-exact vs MAME (hangon) |
| M5 | Sound: YM2203 (jt03) + the latch path | envelope correlation vs MAME recording |
| M6 | Hardware bring-up: Hang-On playable, controls, NVRAM, DIPs, timing | gates + the user's hardware checklist |
| M7 | Space Harrier: SHARRIER sprites (zoom PROM), i8751 on an MCS-51 core, YM2151+PCM board | sharrier frames vs MAME; plays on hardware |
| M8 | Enduro Racer: FD1089B, both sound variants | enduror sets vs MAME; plays on hardware |
| M9 | Super Hang-On conversion: `shangonrb` first, FD1094 after | frames vs MAME; plays on hardware |

## 5. Open questions

1. Exact pixel clock and horizontal total: MAME uses `set_refresh_hz(60)`
   with a size, not measured raw timing — same caveat as the Y Board's
   open question 1. Assume the family's 342-ish grid until measured.
2. The i8751's bus arbitration against the main 68000 (cycle stealing?
   wait states?) and whether MAME's 40385 write-suppression hack hides a
   real synchronisation the RTL must honour differently.
3. Which MCS-51 core to vendor (candidates: jtframe's mcs51, other open
   8051s) and its licence fit.
4. jt03 (YM2203) integration: clocking, SSG output mixing levels per MAME.
5. Whether the FD1094 for `shangonro` reuses the X Board's decryptor
   block as-is (same device, different key) — likely yes, defer to M9.
6. The road and tilemap HANGON-variant differences from the X Board's
   later versions — enumerate against `segaic16.cpp` before M2/M3.
7. Sprite ROM interleave and stream loaders needed (`sega16sp` HANGON
   uses 16-bit words; SHARRIER 32-bit with a zoom PROM) — settle with the
   ROM tables in M0.
