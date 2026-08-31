# Sega Space Harrier / Hang-On core — working notes for Claude

This repo started on 2026-08-31 as a copy of the reusable half of the Y Board
core, `/Volumes/roms/Arcade-SegaYBoard_MiSTer` (rossops/Arcade-SegaYBoard_MiSTer,
commit 1ceb568), which itself grew out of the X Board core
(`/Volumes/roms/Arcade-SegaXBoard_MiSTer`). Read both repos' `docs/DESIGN.md`
and `README.md` before designing anything: they are the worked examples of
every convention below, and their git history shows what each decision cost.

## What is here and what is not
- `docs/references.md` lists every carried-over file. `sh_` used to be `yb_`
  (and `sh_adc0804.sv` used to be the X Board's `xb_adc0804.sv`).
- Nothing board-specific exists yet. M0 trims the scaffold: `sh_pkg.sv`
  rewritten for this board's memory map, stream and descriptor; the emu top
  cut down to an `sh_core` stub on the real video timing; `tools/romsets.py`
  filled with `hangon`; the carried Y-specific tools that were dropped
  (board_check, frame_check) rebuilt as the video milestones need them.
- New work this board needs that neither parent had: the 315-5011/5012
  tilemap generator (the older HANGON variant of the System 16 tilemaps —
  the X Board's is the later variant, start from it), the segaic16 road in
  its HANGON/SHARRIER form (the X Board has the later road; adapt, do not
  rewrite), the Hang-On and Space Harrier line-based sprite generators
  (`sega16sp.cpp`: SEGA_HANGON_SPRITES, SEGA_SHARRIER_SPRITES — the Y
  Board's 16B renderer is the closest shape), a YM2203 (jotego's jt03 is
  the candidate, same licence situation as jt51), an i8255 PPI, an MCS-51
  core for Space Harrier's dumped 8751 (315-5163A), and FD1089B table
  decryption for Enduro Racer. The FD1094 (Super Hang-On conversion) can
  wait: `shangonrb` is the unencrypted bootleg.
- `sys/` is MiSTer-devel's Template, byte for byte. Never edit it; update it
  by copying the template again. Keep `.qsf` deviations from Template.qsf to
  the handful listed in a comment at the top of the file.

## The board (from MAME 0.289 `segahang.cpp`, verified 2026-08-28)
- Two 68000s: 25.174 MHz/4 (6.29 MHz) on Hang-On, 10 MHz on Space Harrier
  and Enduro Racer (`sharrier` config replaces the main CPU). Z80 at
  8 MHz/2. Screen 320x224.
- Three sound boards (corrected 2026-08-30 against the driver): YM2203 at
  4 MHz plus 315-5218 PCM at 8 MHz on `hangon`, `sharrier` and `enduror1`;
  YM2151 at 4 MHz plus PCM at 4 MHz on the YM2151 Enduro sets and the
  Super Hang-On conversions; two YM2203s plus PCM at 4 MHz only on the
  `endurob2` bootleg. The PCM banking is the older 512K style, a
  parameter our `sh_segapcm_5218.sv` already has.
- Inputs through an ADC0804 (25.174 MHz/4/6) — carried from the X Board —
  and an i8255.
- Space Harrier's i8751 (8 MHz, ROM 315-5163A, dumped, in MAME's set): its
  data space is a window onto the main 68000's bus (address = port1 bits
  6,5,4,3 as A20,A18,A17,A16 | its 16-bit address, with A0 inverted);
  port 1 bits 2:0 drive the main CPU's IPL; it gets IRQ0 from vblank; it
  writes 0x1c to 150000 in its vblank handler and reads 170000, both
  ignored by MAME; MAME suppresses its write to 40385 as a sync hack —
  understand that race, do not blind-copy it.
- Encryption: `enduror` FD1089B 317-0013A on the main CPU (table decrypt,
  keys in MAME); `shangonro`/`shangonho` FD1094 317-0038/0039 on the sub.
- Sets: hangon (+hangon1, hangon2 ride-on), sharrier (+sharrier1), enduror
  (+endurora/b, enduror1, bootlegs incl. decrypted endurord/enduror1d),
  shangonro/shangonho (+shangonrb, shangonrb2 bootlegs).

## How the work goes
- The plan is `docs/DESIGN.md`: hardware reference from MAME, memory
  placement, module list, milestones with a pass criterion and a gate
  script each (`verif/board/check_mN.sh`), open questions. Start at M0.
  Update the README status table as milestones close.
- Every custom chip gets a Python golden model ported from MAME, a cocotb
  unit test, and a place in the Verilator board bench that dumps frames to
  diff against MAME captures. Unit benches are not enough for board-level
  sequencing; two X Board and two Y Board bugs only showed at board level.
- Dump timing is per consumer, not one fixed line: dump each RAM at the
  moment the renderer actually reads it (the Y Board's M6 finding; its
  `tb_board.sv` +dumpframe comment is the worked example).
- The SMB share's drive spins down during long simulations. `tools/keepalive.sh`
  writes and deletes `DELETE_ME` on the share every 30 s; `make -C verif/board
  run` starts it for every run, and any other long job on the share (a MAME
  batch, a Quartus build watched from here) starts it too. The share also
  drops sessions outright ("Operation not permitted" on everything): stop,
  tell the user to kick it, retry.
- Simulation runs on the Mac (Verilator 5, Icarus, cocotb in `verif/.venv`,
  Python 3.12; MAME 0.289 at `/opt/homebrew/bin/mame`; MAME source at
  `~/Code/mame`; merged ROM zips in `/Volumes/roms/Arcade/MAME 0.289 ROMs (merged)/`).
- MAME verification tricks that took days to learn: capture with
  `-snapview native` or layout artwork lands in the screenshot (GAMEL
  sets); `screen:snapshot()` alone does not avoid it. Lua `set_value` on
  an ANALOG field is not a hold — MAME's auto-centring pulls it back each
  frame. Too many Lua read/write taps segfault MAME; keep them minimal.
  `mame_trace.py --coin/--starts/--cfgdir` traces past inputs and DIP
  settings (a saved cfg directory sets DIPs from boot). MAME draws its
  frame at frame end from end-of-frame state; a live scan-out legitimately
  differs on mid-frame palette or list writes — `frame_diff --step-ok
  --max-far N` exists for exactly that, and the user's standing rule is:
  accept small explained residuals, chase only with a concrete hypothesis.
- Quartus 17.0.2 Lite runs on a Windows box the user drives: they run
  `build.bat` on this share; it compiles whatever is checked out here, so
  check out the branch you want built. Watch `output_files/` with
  `find -newermt <ISO timestamp>` (this Mac's find is bfs: absolute
  timestamps only, GNU relative forms silently match nothing). Read the
  M10K block row in `fit.rpt`, not the bit count. Quirks that bit before:
  no untyped aggregate localparams, no inference of two-clock byte-enabled
  RAMs (explicit altsyncram, NEW_DATA_NO_NBE_READ), MLAB placement can
  break hold on DDR3 read data (`ram_block_type = "M10K"`), and
  `$readmemh` files must be registered in `files.qip` as `MIF_FILE` with a
  `SEARCH_PATH` — files.qip is `source`d by the qsf, so `$::quartus(qip_path)`
  does not exist there and using it kills every build at the Tcl line.
- Upload with `tools/mister_ssh.sh put|run` (DE10-Nano at 192.168.1.63,
  root; password known to the user). Ship split clone zips
  (`tools/make_clone_zips.py`), not merged ones. For many files, tar with
  `COPYFILE_DISABLE=1`, one `put`, then `tar -xof` on the box (plain -xf
  spews chown errors and returns failure even though every file lands).
- The user tests every build on hardware before its `.rbf` is committed.
  Do not commit, merge or push unless told. One branch per milestone,
  fast-forward merge into `main` on the user's word, then `tools/make_db.py`
  and push. Releases via the "Release" workflow (its notes name the newest
  rbf; the `ls | head -1` bug is already fixed in the carried copy).

## Hard-won RTL rules (each one cost a debugging session)
- Multi-CPU shared RAM: the arbiter must hold the RAM for a CPU from a
  read until that CPU's next bus cycle, so `tas` (a locked RMW cycle) and
  `bclr`/`bset`/`addq` on memory (two plain cycles a few clocks apart)
  are atomic across CPUs. MAME never shows the race because its
  instructions are atomic. Power Drift deadlocked twice without this —
  first a lock byte re-set by a stale `tas` write, then an acknowledge
  overwritten inside a `bclr`. The Y Board's arbiter (`shr_hold` in its
  `yb_core.sv`) is the reference implementation, with the release on the
  holder's next bus start, an RMW write served first, and a timeout.
- Acknowledge writes into ROM space and any decoded read-only region:
  MAME drops them silently, real DTACK logic ignores R/W, and a decode
  that only acks reads stalls the CPU until the watchdog (G-LOC R360
  clears 64 KB of ROM space entering a fight). The bench logs them (ROMWR).
- Read-side-effect registers (ADC shift registers, anything that advances
  on a read): the bus strobe is one clock at the start of the cycle and
  fx68k latches data after DTACK several clocks later — latch the
  outgoing value on the strobe, then advance. Unit tests must sample at
  the CPU's latch point, the clock after the strobe (the Y Board's
  MSM6253 read a centred stick as 0 on hardware with a test that passed).
- fx68k: UDS/LDS come one state after AS on writes; the main CPU's RESET
  instruction resets the others (MAME's reset callback); exact PC traces
  follow the prefetch queue (see the X Board's `tools/mame_trace.py` notes).
  A PC trace jumping to the reset vector means a reset, and the trace has
  no timestamps — a 300-frame stall before it is invisible.
- Watchdog (MB3773 pattern): a game that stops kicking it resets ~5 s
  later; on hardware that reads as "the game resets", in the bench as a
  WATCHDOG log line long after the actual hang. Find the hang, not the reset.

## Conventions
- `releases/` is generated: `tools/gen_mra.py` from `tools/romsets.py`,
  alternatives under `releases/_alternatives/_<Game>/`. CI diffs the tree
  against the generator and runs MiSTer-devel's `mra_rom_check.sh`. Never
  hand-edit an MRA. MRAs use the bare `<rbf>SegaSpaceHarrier</rbf>` tag
  (the X Board shipped a broken `Arcade-` prefixed tag once; issue #3).
- Commit messages, docs and anything customer-facing in plain
  conversational English (the user's Humanizer rules); no bullet-point
  cheerleading, no "delve".
- Verilator: `-Werror-PINMISSING` in the bench; `sh verif/lint.sh` before
  every commit.
- Credit Meathax's System 32 core for `sdram.sv` and the framebuffer
  interface; never describe the user as its author. The core is GPL-3.
