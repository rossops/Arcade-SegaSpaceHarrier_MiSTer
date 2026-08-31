# Sega Space Harrier / Hang-On for MiSTer FPGA

MiSTer core for Sega's Space Harrier / Hang-On arcade hardware: Hang-On,
Space Harrier, Enduro Racer and the Super Hang-On conversion kits. Same
approach as the X Board and Y Board cores it descends from: simulate the
board, verify every custom chip against a Python port of MAME, then check
whole frames against MAME captures before anything goes near the FPGA.

No game runs yet — the scaffold (carried from the Y Board core) is
trimmed to this board and the first stub bitstream fits with clean
timing. `docs/DESIGN.md` has the plan and the open questions;
`docs/references.md` says where every file came from.

## Status

| Milestone | What it proves | State |
| --- | --- | --- |
| M0 | Skeleton compiles, MRA/stream tools agree with MAME CRCs | done (2026-08-31) |
| M1 | Two 68000s, shared RAM, PPIs, ADC, interrupts track MAME | done (2026-08-31) |
| M2 | Tilemaps and text layer pixel-exact | done (2026-08-31) |
| M3 | Road generator pixel-exact | done (2026-08-31) |
| M4 | Hang-On sprites and mixer: full frames vs MAME | done (2026-08-31) |
| M5 | YM2203 + PCM sound vs MAME recordings | not started |
| M6 | Hang-On playable on hardware | not started |
| M7 | Space Harrier (sharrier video, i8751) | not started |
| M8 | Enduro Racer (FD1089B, YM2151 board) | not started |
| M9 | Super Hang-On conversions | not started |
