# Hardware and IP references

## Behavioural references
- MAME (behavioural reference, GPL-2.0+/BSD-3): local checkout `~/Code/mame`.
  Files to port from: `src/mame/sega/segahang.cpp` (driver, maps, i8751
  hookup, configs), `sega16sp.cpp` (`sega_hangon_sprite_device`,
  `sega_sharrier_sprite_device`), `segaic16.cpp` (TILEMAP_HANGON tilemaps,
  palette), `segaic16_road.cpp` (HANGON/SHARRIER road), `segaic16_m.cpp`
  (5248/5249), `src/devices/sound/segapcm.cpp`, `src/devices/sound/ym2203`
  family, `src/devices/machine/i8255.cpp`, `src/devices/machine/adc0804.cpp`,
  `src/mame/sega/fd1089.cpp`, and the MCS-51 core under
  `src/devices/cpu/mcs51/` for the 8751. Installed binary for captures:
  `/opt/homebrew/bin/mame` (0.289).
- ROM sets: MAME 0.289 merged zips in `/Volumes/roms/Arcade/MAME 0.289 ROMs (merged)/`.

## Carried over from the Y Board core
Copied from `rossops/Arcade-SegaYBoard_MiSTer` at commit `1ceb568`
(2026-08-31) with the `yb_` prefix renamed to `sh_`. Same licence (GPL-3).
These were verified on that core (and most on the X Board before it)
against MAME and on a DE10-Nano:

| Path | What it is |
| --- | --- |
| `rtl/cpu/sh_m68k_bus.sv` | fx68k wrapper: unified bus, DTACK, IPL, VPA autovector |
| `rtl/cpu/sh_rom_cache.sv` | direct-mapped 68000/Z80 ROM cache over SDRAM |
| `rtl/audio/sh_soundsys.sv`, `sh_segapcm_5218.sv` | Z80 sound board, YM2151 glue, 315-5218 PCM (bank style is a parameter; this board uses the 512K banking) |
| `rtl/mem/sdram.sv`, `sh_rom_loader.sv`, `sh_dpram.sv` | SDRAM controller (ports p0..p7), ioctl stream loader, two-clock byte-enabled RAM |
| `rtl/video/sh_video_timing.sv` | video timing with the 2x output grid (retune for this board in M0) |
| `rtl/video/sh_palette_5242.sv`, `sh_pal_lut.svh` | 315-5242 palette and resistor-ladder LUTs |
| `rtl/io/sh_ana_shape.sv` | analog response curves (OSD Linear/Soft/Softer) |
| `rtl/sh_pkg.sv` | shared package, to be rewritten in M0 for this board's map, stream and descriptor |
| `Arcade-SegaSpaceHarrier.sv`, `.qsf`, `.sdc`, `.qpf`, `files.qip`, `build.bat`, `clean.bat` | MiSTer emu wrapper and Quartus project (to be trimmed to the `sh_core` ports in M0; files.qip is `source`d by the qsf — no `qip_path` there, `$readmemh` data goes in as `MIF_FILE` + `SEARCH_PATH`) |
| `verif/` | lint scripts, board bench (to be trimmed to `sh_core` in M0), SDRAM/DDR3 models, golden models and cocotb tests for the chips above, tv80 |
| `tools/` | MRA generator and packer, downloader db, MAME capture/trace/presses/wav tools, frame_diff with `--step-ok`, clone-zip builder, keepalive, MiSTer ssh helper, Quartus build-id and STA scripts |
| `.github/workflows/` | CI (MRA regeneration diff, mra_rom_check, tool tests) and the Release workflow (notes name the newest rbf) |

Dropped at the cutover (Y Board specific, to be rebuilt when needed):
the 315-5305/5306/5196/5312 video chain, the 315-5296 and MSM6253 and
their models/tests, `board_check.py`, `frame_check.py`, `synth_ylist.py`,
the Power Drift shifter overlay. Dropped in M0 (not on this board, see
docs/DESIGN.md): the 315-5248/5249 math chips and their models/tests,
`sh_fb_if.sv` and the bench's DDR3 model (both sprite generators here are
line-based). Added in M0: `rtl/pll.v`/`pll.qip`, the Y Board's PLL retuned
to 50.3496/100.6992 MHz with the fractional VCO multiplier. Added in M1:
`rtl/io/sh_i8255.sv` and its model/test. Added in M2: `rtl/video/
sh_tilemap_5012.sv` and `sh_tilerom.sv` (the 315-5011/5012 chain, built
on the X Board's `xb_tilemap_5197` shape), `verif/models/tilemap_hangon.py`,
the rebuilt `tools/mame_capture.*`, `model_check.py` and `board_check.py`,
and `verif/unit/tilemap/`. Added in M3: `rtl/video/sh_road.sv` and
`sh_roadrom.sv` (the segaic16 road, HANGON/SHARRIER variant, from MAME's
netlist emulation), `verif/models/road_hangon.py` and `verif/unit/road/`. Added in M4:
`rtl/video/sh_sprite.sv` and `sh_zoomrom.sv` (SEGA_HANGON_SPRITES as a
line renderer), `verif/models/sprite_hangon.py` and `verif/unit/sprite/`.

## Carried over from the X Board core
| Path | What it is |
| --- | --- |
| `rtl/io/sh_adc0804.sv` (was `xb_adc0804.sv`) | ADC0804, this board's analog converter |
| `verif/models/adc0804.py`, `verif/unit/chips/test_adc0804.py` | its golden model and test |

## Vendored IP (pinned, unchanged)
| Path | Upstream | Commit | Licence |
| --- | --- | --- | --- |
| `sys/` | MiSTer-devel/Template_MiSTer (stock, never edited) | as in the Y Board core | GPL-3 / mixed, see files |
| `rtl/cpu/fx68k/` | https://github.com/ijor/fx68k | `0602ee4627b10f301298f2673d826cdd6baa9327` | GPL-3 |
| `rtl/audio/jt51/` | https://github.com/jotego/jt51 (`hdl/`) | `985a573dcfc1ff135553a39f7eae21d18ba57cbe` | GPL-3 |
| `rtl/audio/T80/` | Wallner/MikeJ/Sorgelig, via Meathax's System 32 core | as vendored | BSD-style |
| `verif/board/tv80/` | tv80 (Guy Hutchison, opencores), simulation-only Z80 | as vendored | MIT-style |

To be vendored when their milestones arrive: jt03 (YM2203, jotego, GPL-3)
for M5; an MCS-51 core for M7; the FD1094 pieces (jtcores `cores/s16`, via
the X Board core) for M9.

`sdram.sv` and `sh_fb_if.sv` descend from Meathax's Sega System 32 core
(https://github.com/meathax/s32, GPL-3) by way of the X and Y Board cores.
