"""315-5218 replay: the RTL engine and the Python model (MAME's loop) run from
Enduro Racer's real channel state - the core's own register dump at frame
1000 of the attract mode, six engine loops and a one-shot voice - with the
real PCM ROM, and must agree tick for tick. The random test covers the
register semantics; this covers the real programming the game uses."""
import os, sys, zipfile
import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge, ReadOnly, ClockCycles

sys.path.insert(0, os.path.join(os.path.dirname(__file__), "..", ".."))
from models.segapcm import SegaPCM

ROOT = os.path.join(os.path.dirname(__file__), "..", "..", "..")
ZIP = "/Volumes/roms/Arcade/MAME 0.289 ROMs (merged)/enduror.zip"
DUMP = os.path.join(ROOT, "verif", "board", "out", "m8_e1_pcm.log")


def real_rom():
    zf = zipfile.ZipFile(ZIP)
    by = {f"{i.CRC & 0xffffffff:08x}": i.filename for i in zf.infolist()}
    return zf.read(by["bc0c4d12"]) + zf.read(by["627b3c8c"])


def dump_regs(frame, path=None):
    for line in open(path or DUMP):
        if f"PCMREGS f={frame} " in line:
            i = line.index(f"PCMREGS f={frame} ") + len(f"PCMREGS f={frame} ")
            return [int(x, 16) for x in line[i:].split()[:256]]
    raise FileNotFoundError(f"no PCMREGS f={frame} in {path or DUMP}")


def real_rom_2151():
    """the YM2151 board's 128 KB image: epr-7681 at 0, a 32 KB gap, epr-7680 at 0x10000"""
    zf = zipfile.ZipFile(ZIP)
    by = {f"{i.CRC & 0xffffffff:08x}": i.filename for i in zf.infolist()}
    return zf.read(by["bc0c4d12"]) + bytes(0x8000) + zf.read(by["627b3c8c"])


async def serve_rom(dut, rom):
    dut.rom_ack.value = 0
    prev = 0
    while True:
        await RisingEdge(dut.clk)
        req = int(dut.rom_req.value)
        if req and not prev:
            a = int(dut.rom_addr.value) * 2 - 0x090000
            lo = rom[a] if 0 <= a < len(rom) else 0xFF
            hi = rom[a + 1] if 0 <= a + 1 < len(rom) else 0xFF
            await ClockCycles(dut.clk, 6)
            dut.rom_dout.value = lo | (hi << 8)
            dut.rom_ack.value = 1
            await RisingEdge(dut.clk)
            dut.rom_ack.value = 0
        prev = req


async def z80_write(dut, addr, data):
    dut.cs.value = 1; dut.we.value = 1; dut.addr.value = addr; dut.din.value = data
    await RisingEdge(dut.clk)
    dut.cs.value = 0; dut.we.value = 0
    await RisingEdge(dut.clk)


@cocotb.test()
async def enduro_frame_1000(dut):
    if not (os.path.exists(ZIP) and os.path.exists(DUMP)):
        dut._log.warning("no ROM zip or register dump; skipping")
        return
    rom = real_rom(); regs = dump_regs(1000)
    cocotb.start_soon(Clock(dut.clk, 20, unit="ns").start())
    for s in ("tick", "cs", "we", "addr", "din", "rom_ack", "rom_dout"): getattr(dut, s).value = 0
    dut.bankmask.value = 0x70
    dut.discrete.value = 0       # the core runs the 315-5218 model on both boards
    dut.reset.value = 1
    for _ in range(3): await RisingEdge(dut.clk)
    dut.reset.value = 0
    await RisingEdge(dut.clk)
    cocotb.start_soon(serve_rom(dut, rom))
    m = SegaPCM(rom)
    for off, val in enumerate(regs):
        m.write(off, val)
        await z80_write(dut, off, val)
    peak = 0
    for t in range(4000):
        exp = m.tick()
        dut.tick.value = 1
        await RisingEdge(dut.clk)
        dut.tick.value = 0
        for _ in range(600):
            await RisingEdge(dut.clk)
            if int(dut.es.value) == 0: break
        await ReadOnly()
        got = (int(dut.out_l.value.to_signed()), int(dut.out_r.value.to_signed()))
        assert got == exp, f"tick {t}: got {got} expected {exp}"
        peak = max(peak, abs(got[0]))
        await RisingEdge(dut.clk)
    dut._log.info(f"4000 ticks equal; output peak {peak}")
    assert peak > 0, "the replayed state produced silence"


REF2151 = os.path.join(ROOT, "verif", "board", "out", "ref_e_1400.txt")


@cocotb.test()
async def enduro_2151_bank1(dut):
    """the YM2151 board at frame 1000 of the attract: a one-shot in bank 1 at full
    volume (the loud rev) over four engine loops; the bank bits and the gap in
    the 128 KB image are what this checks"""
    if not (os.path.exists(ZIP) and os.path.exists(REF2151)):
        dut._log.warning("no ROM zip or reference dump; skipping")
        return
    rom = real_rom_2151(); regs = dump_regs(1000, REF2151)
    cocotb.start_soon(Clock(dut.clk, 20, unit="ns").start())
    for s in ("tick", "cs", "we", "addr", "din", "rom_ack", "rom_dout"): getattr(dut, s).value = 0
    dut.bankmask.value = 0x70
    dut.discrete.value = 0
    dut.reset.value = 1
    for _ in range(3): await RisingEdge(dut.clk)
    dut.reset.value = 0
    await RisingEdge(dut.clk)
    cocotb.start_soon(serve_rom(dut, rom))
    m = SegaPCM(rom)
    for off, val in enumerate(regs):
        m.write(off, val)
        await z80_write(dut, off, val)
    peak = 0
    for t in range(3000):
        exp = m.tick()
        dut.tick.value = 1
        await RisingEdge(dut.clk)
        dut.tick.value = 0
        for _ in range(600):
            await RisingEdge(dut.clk)
            if int(dut.es.value) == 0: break
        await ReadOnly()
        got = (int(dut.out_l.value.to_signed()), int(dut.out_r.value.to_signed()))
        assert got == exp, f"tick {t}: got {got} expected {exp}"
        peak = max(peak, abs(got[0]))
        await RisingEdge(dut.clk)
    dut._log.info(f"3000 ticks equal; output peak {peak}")
    assert peak > 2000, "the bank-1 one-shot at full volume should dominate"


def test_segapcm_replay():
    sys.path.insert(0, os.path.join(os.path.dirname(__file__), ".."))
    from runner import run
    run("sh_segapcm_5218", ["rtl/sh_pkg.sv", "rtl/audio/sh_segapcm_5218.sv"], "test_segapcm_replay")
