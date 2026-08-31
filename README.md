# Sega Space Harrier / Hang-On for MiSTer FPGA

MiSTer core for Sega's Space Harrier / Hang-On arcade hardware: Hang-On,
Space Harrier, Enduro Racer and the Super Hang-On conversion kits. Same
approach as the X Board and Y Board cores it descends from: simulate the
board, verify every custom chip against a Python port of MAME, then check
whole frames against MAME captures before anything goes near the FPGA.

Nothing runs yet — this is the scaffold, carried over from the Y Board
core on 2026-08-31. `docs/DESIGN.md` has the draft plan and the open
questions; `docs/references.md` says where every file came from.

## Status

| Milestone | What it proves | State |
| --- | --- | --- |
| M0 | Skeleton compiles, MRA/stream tools agree with MAME CRCs | not started |
