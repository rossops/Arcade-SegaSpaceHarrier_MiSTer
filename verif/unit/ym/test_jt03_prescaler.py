"""jt03 (YM2203) under each prescaler. Hang-On's driver leaves the chip at
the reset default (register 2D: FM /6, SSG /4); Enduro Racer's writes 2F
(FM /2, SSG /1) at boot, and on the board bench its FM and SSG then stay
silent for 30 s while the Z80 writes the same registers MAME's does. A
single FM note and a single SSG tone must come out under both settings."""
import os, sys
import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge, ClockCycles

CEN_DIV = 12   # 4 MHz enable from the ~50 MHz clock, close enough


async def cen_gen(dut):
    n = 0
    while True:
        await RisingEdge(dut.clk)
        n += 1
        dut.cen.value = 1 if n % CEN_DIV == 0 else 0


async def write(dut, addr, val):
    # a1 (addr) then data, each held for one cen period like a Z80 would
    for a, d in ((0, addr), (1, val)):
        dut.addr.value = a; dut.din.value = d; dut.cs_n.value = 0; dut.wr_n.value = 0
        await ClockCycles(dut.clk, 2)
        dut.cs_n.value = 1; dut.wr_n.value = 1
        await ClockCycles(dut.clk, CEN_DIV * 4)


async def measure(dut, cycles):
    fm_e = ssg_e = 0
    fm_max = ssg_max = 0
    for _ in range(cycles):
        await RisingEdge(dut.clk)
        fm = dut.fm_snd.value.to_signed() if hasattr(dut.fm_snd.value, "to_signed") else int(dut.fm_snd.value)
        fm = fm - 65536 if fm > 32767 else fm
        a = int(dut.psg_A.value)
        fm_e += fm * fm; ssg_e += a * a
        fm_max = max(fm_max, abs(fm)); ssg_max = max(ssg_max, a)
    return fm_max, ssg_max


async def run_case(dut, presc_reg):
    dut.rst.value = 1; dut.cs_n.value = 1; dut.wr_n.value = 1; dut.addr.value = 0; dut.din.value = 0
    await ClockCycles(dut.clk, 100)
    dut.rst.value = 0
    await ClockCycles(dut.clk, 100)
    await write(dut, presc_reg, 0)          # the prescaler select is the address write itself
    await write(dut, 0x27, 0x00)
    # SSG: channel A tone, period 0x100, mixer tone A on, volume 15
    await write(dut, 0x00, 0x00); await write(dut, 0x01, 0x01)
    await write(dut, 0x07, 0x3E); await write(dut, 0x08, 0x0F)
    # FM channel 1: algorithm 7 (four carriers), TL 0, AR 31, no decay, F-number for ~440 Hz
    await write(dut, 0xB0, 0x07)
    for op in (0x30, 0x34, 0x38, 0x3C):
        await write(dut, op, 0x01)          # DT/MUL = 1
        await write(dut, op + 0x10, 0x00)   # TL 0
        await write(dut, op + 0x20, 0x1F)   # AR 31
        await write(dut, op + 0x30, 0x00)   # D1R 0
        await write(dut, op + 0x40, 0x00)   # D2R 0
        await write(dut, op + 0x50, 0x0F)   # D1L 0, RR 15
    await write(dut, 0xA4, 0x22); await write(dut, 0xA0, 0x69)   # block 4, fnum 0x269
    await write(dut, 0x28, 0xF0)            # key on all four operators of channel 1
    fm_max, ssg_max = await measure(dut, 400000)   # ~8 ms
    return fm_max, ssg_max


@cocotb.test()
async def prescaler_paths(dut):
    cocotb.start_soon(Clock(dut.clk, 20, unit="ns").start())
    cocotb.start_soon(cen_gen(dut))
    dut.IOA_in.value = 0xFF; dut.IOB_in.value = 0xFF
    res = {}
    for name, reg in (("2D (/6, Hang-On)", 0x2D), ("2F (/2, Enduro)", 0x2F)):
        res[name] = await run_case(dut, reg)
        dut._log.info(f"{name}: FM peak {res[name][0]}, SSG A peak {res[name][1]}")
    for name, (fm, ssg) in res.items():
        assert fm > 1000, f"{name}: FM silent (peak {fm})"
        assert ssg > 8, f"{name}: SSG silent (peak {ssg})"


def test_jt03_prescaler():
    sys.path.insert(0, os.path.join(os.path.dirname(__file__), ".."))
    from runner import run
    import glob
    root = os.path.join(os.path.dirname(__file__), "..", "..", "..")
    srcs = sorted(os.path.relpath(p, root) for p in glob.glob(os.path.join(root, "rtl/audio/jt03/*.v")))
    os.environ.setdefault("SIM", "verilator")
    run("jt03", srcs, "test_jt03_prescaler")
