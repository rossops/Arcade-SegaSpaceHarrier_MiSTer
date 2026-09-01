# Sega Space Harrier / Hang-On for MiSTer FPGA

MiSTer core for Sega's Space Harrier / Hang-On arcade hardware: Hang-On,
Space Harrier, Enduro Racer and the Super Hang-On conversion kits. Same
approach as the X Board and Y Board cores it descends from: simulate the
board, verify every custom chip against a Python port of MAME, then check
whole frames against MAME captures before anything goes near the FPGA.

Hang-On's video is complete — full frames match MAME's screenshots on
every pixel, confirmed on a DE10-Nano — and the sound board plays: the
attract sequence's audio envelope correlates 0.94 against MAME's own
recording, with the video still pixel-exact while it runs. `docs/DESIGN.md` has the plan, the per-milestone findings and
the open questions; `docs/references.md` says where every file came from.

## Status

| Milestone | What it proves | State |
| --- | --- | --- |
| M0 | Skeleton compiles, MRA/stream tools agree with MAME CRCs | done (2026-08-31) |
| M1 | Two 68000s, shared RAM, PPIs, ADC, interrupts track MAME | done (2026-08-31) |
| M2 | Tilemaps and text layer pixel-exact | done (2026-08-31) |
| M3 | Road generator pixel-exact | done (2026-08-31) |
| M4 | Hang-On sprites and mixer: full frames vs MAME | done (2026-08-31) |
| M5 | YM2203 + PCM sound vs MAME recordings | done (2026-08-31) |
| M6 | Hang-On playable on hardware | not started |
| M7 | Space Harrier (sharrier video, i8751) | not started |
| M8 | Enduro Racer (FD1089B, YM2151 board) | not started |
| M9 | Super Hang-On conversions | not started |
| M10 | Board reference doc + recovered PAL equations (optional) | not started |

## Core vs MAME

MAME 0.289 is this core's behavioural reference: every renderer has a
Python golden model ported line for line from it, and the gates compare
frames and traces against it directly. But MAME is an emulator with its
own conveniences, and a cycle-concurrent board sometimes has to model
what MAME can skip. This section is the running scorecard — where we
match MAME exactly, where we deliberately go past it toward the real
hardware, and where chasing a bug taught us which of the two was right.
It gets updated as milestones close; docs/DESIGN.md has the full detail
behind each entry.

### Matching MAME exactly

- Video timing is MAME's measured `set_raw`: 400x262 at 25.1748 MHz/4,
  320x224 visible. Unusually for this board family, MAME's numbers here
  are real measurements, not placeholders.
- All four video layers (tilemaps, text, road, sprites), the mixer's
  priority rules and the three-bank shadow/hilight palette reproduce
  MAME's screenshots pixel for pixel on every capture.
- The main CPU's vblank interrupt is held until acknowledge, exactly
  MAME's `irq4_line_hold`.
- Analog reversal follows MAME's PORT_REVERSE arithmetic: `0x100 - value`
  on every reversed channel (the carried module said `255 - value`, one
  count off centre; we fixed it to match).
- The 315-5218 PCM ticks at clock/128 per MAME. system16.com publishes
  half these rates; the ratio between the two sound boards agrees, the
  absolute rate is an open question only real hardware can settle.

### Deliberately different — closer to the hardware

- Shared-RAM arbitration holds the RAM for a CPU from a read until its
  next bus cycle, so `tas` and the two-cycle `bclr`/`bset`/`addq` on
  memory are atomic across CPUs. MAME never needs this because its
  instructions are atomic; the real bus has the race, and the Y Board's
  Power Drift deadlocked twice to prove it.
- Writes into ROM space are acknowledged and dropped. MAME drops them
  silently; a decode that only acks reads stalls a real 68000 until the
  watchdog. Real DTACK logic doesn't look at R/W.
- The renderers work the way the chips do, not the way MAME draws: the
  sprite generator is line-based with a private copy of the list (the
  chip's word-7 scratch write-back never reaches the CPU), the road
  renders each line from live shared RAM, and the tilemap reads its
  scroll registers fresh per line. MAME draws whole frames at frame end
  from end-of-frame state. On static frames the two are identical; a
  mid-frame write legitimately splits a frame here, as it would on the
  PCB.
- Planned for M7: MAME suppresses the Space Harrier i8751's write to
  40385 as a sync hack. Our disassembly of the MCU ROM showed that write
  is two zeroes during the MCU's own reset init, and the byte is a
  heartbeat the 68000 sets and the MCU polls. The bridge will treat it
  as plain work RAM and get the reset ordering right instead.
- MAME re-synchronises its scheduler on every access to the main PPI
  (`sync_ppi_w`) to keep the sound handshake ordered. A cycle-concurrent
  design needs no such hack; the handshake is just wires.

### Where a bug taught us who was right

- The main PPI runs in i8255 mode 2, not the mode-1-style handshake
  MAME's driver comments suggest — the game programs control word 0xC0
  and uses the bidirectional mode's output half. Two of our bugs came
  from assuming mode 2 was absent; MAME's i8255 device had it right all
  along. The mode-2 status byte matters too: the input half is unwired
  on this board, so IBF must read 0, and reading port A returns an empty
  buffer, not the output latch.
- The YM2203 timer flags cleared wrong twice in our vendored jt12, and
  MAME's ymfm was the faithful one both times. jt12 latched the flag
  reset bits of register 0x27 as levels (a driver that parks a reset bit
  high pins the flag forever); and the clear belongs at the end of the
  write's 32-cycle busy window — when the chip processes the write — not
  at the bus edge. Hang-On's sound driver counts on reading the flag as
  still set through the busy window; it was written against real
  silicon, and ymfm models that. Both fixes are documented local patches
  in `rtl/audio/jt03/`.
- The SSG's volume curve too: jt03 ships its AY core with a 29 dB
  compressed volume table (an FPGA mixing convenience), where the
  measured chip curve ymfm models spans about 44 dB. Hang-On fades its
  music through the quiet volumes every phrase, where the compression
  audibly flattens the fades; a third local patch in `rtl/audio/jt03/`
  restores the faithful table. Honest scorecard note: what actually
  blocked the M5 envelope gate was our own bench truncating its 48 kHz
  sample clock by 0.78%, a time warp we chased as a mix-balance
  problem for a while.
- The sub CPU's interrupt is a level the main holds through the PPI for
  about seven lines, and its handler legitimately re-enters within that
  window. The re-entry count differs from MAME's because our bus cycles
  carry DTACK latency MAME doesn't model — same shape the Y Board saw.
  Harmless, and the M1 gate gives it a tolerance instead of hiding it.
- Uninitialised RAM: MAME zero-fills its RAM regions and the FPGA's
  M10K blocks power up cleared, and Hang-On's sound driver counts on
  it — it reads a byte it never wrote to decide whether to activate
  the song engine. The one environment that disagreed was our own
  simulator (x-assign giving 0xFF), which held M5 up for a day. Every
  game-visible RAM now zero-inits in simulation to match both MAME
  and the silicon.
- Instrumented MAME is not MAME. The Lua read/write taps we used to
  trace the YM2203 flipped MAME's own sound driver onto the wrong
  side of an internal channel race, and the trace then "confirmed"
  our bug was correct behaviour. A single minimal tap reproduced
  MAME's real output exactly. Trace with as few taps as possible and
  always check the instrumented run still matches the clean run's
  audio or video before trusting it.
- The coin-during-attract race is genuinely undecided. Hang-On's
  sound program arbitrates the attract theme (priority 7) against the
  coin sound (priority 4) with interrupts enabled, and the outcome
  depends on where the YM timer interrupt lands. MAME lands on the
  side where the coin sound is rejected and the theme ends on
  schedule; our cycle-timed board (and MAME itself, once taps perturb
  its scheduler) lands where the coin sound steals two SSG channels
  and the theme loops forever. Only a real PCB can say which side the
  hardware takes; the M5 gate tests the attract sequence without a
  coin, where the two agree exactly (DESIGN.md open question 11).
