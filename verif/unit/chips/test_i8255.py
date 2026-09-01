"""i8255 vs the Python model: random control words, BSR, port traffic and
the mode-1 group A output handshake (/OBF, /ACK, INTE, INTR). Reads are
sampled the clock after the strobe, at the 68000's latch point, per the
parents' read-side-effect rule (this chip has no read side effects, but the
sampling discipline stays uniform). The main PPI's port A is Hang-On's
sound latch, so the handshake path is exactly what the Z80 NMI rides on.
"""
import random, sys, os
import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge, ReadOnly

sys.path.insert(0, os.path.join(os.path.dirname(__file__), "..", ".."))
from models.i8255 import I8255


async def strobe_write(dut, addr, data):
    dut.cs.value = 1; dut.we.value = 1; dut.addr.value = addr; dut.din.value = data
    await RisingEdge(dut.clk)
    dut.cs.value = 0; dut.we.value = 0
    await RisingEdge(dut.clk)


async def strobe_read(dut, addr):
    dut.cs.value = 1; dut.we.value = 0; dut.addr.value = addr
    await RisingEdge(dut.clk)
    dut.cs.value = 0
    await ReadOnly()               # the clock after the strobe = the CPU's latch point
    v = int(dut.dout.value)
    await RisingEdge(dut.clk)
    return v


async def check_outputs(dut, m, tag):
    await ReadOnly()
    assert int(dut.out_a.value) == m.out_a, f"{tag}: out_a {int(dut.out_a.value):02x} != {m.out_a:02x}"
    assert int(dut.out_b.value) == m.out_b, f"{tag}: out_b {int(dut.out_b.value):02x} != {m.out_b:02x}"
    assert int(dut.out_c.value) == m.out_c, f"{tag}: out_c {int(dut.out_c.value):02x} != {m.out_c:02x}"
    assert int(dut.obfa_n.value) == m.obf_n, f"{tag}: obf {int(dut.obfa_n.value)} != {m.obf_n}"
    assert int(dut.intra.value) == m.intr, f"{tag}: intr {int(dut.intra.value)} != {m.intr}"
    await RisingEdge(dut.clk)


@cocotb.test()
async def random_traffic(dut):
    cocotb.start_soon(Clock(dut.clk, 20, unit="ns").start())
    for s in ("cs", "we", "addr", "din"):
        getattr(dut, s).value = 0
    dut.acka_n.value = 1
    dut.in_a.value = 0xFF; dut.in_b.value = 0xFF; dut.in_c.value = 0xFF
    dut.reset.value = 1
    for _ in range(3):
        await RisingEdge(dut.clk)
    dut.reset.value = 0
    await RisingEdge(dut.clk)

    m = I8255()
    rng = random.Random(8255)
    for t in range(2000):
        op = rng.randrange(10)
        if op == 0:
            # mode set: group A mode 0, 1 or 2 (hangon uses 2), random dirs
            cw = 0x80 | (rng.randrange(4) << 5) | (rng.randrange(2) << 4) | \
                 (rng.randrange(2) << 3) | (rng.randrange(2) << 1) | rng.randrange(2)
            m.write(3, cw)
            await strobe_write(dut, 3, cw)
        elif op == 1:
            # BSR
            v = rng.randrange(16)
            m.write(3, v)
            await strobe_write(dut, 3, v)
        elif op in (2, 3, 4):
            a, d = rng.randrange(3), rng.randrange(256)
            m.write(a, d)
            await strobe_write(dut, a, d)
        elif op in (5, 6):
            a = rng.randrange(4)
            got = await strobe_read(dut, a)
            exp = m.read(a)
            assert got == exp, f"t{t}: read({a}) {got:02x} != {exp:02x}"
        elif op == 7:
            # new input pin values
            ia, ib, ic = rng.randrange(256), rng.randrange(256), rng.randrange(256)
            m.in_a, m.in_b, m.in_c = ia, ib, ic
            dut.in_a.value = ia; dut.in_b.value = ib; dut.in_c.value = ic
            await RisingEdge(dut.clk)
        else:
            # /ACK pulse: low for a few clocks, then back high
            m.set_ack(0)
            dut.acka_n.value = 0
            for _ in range(rng.randrange(1, 4)):
                await RisingEdge(dut.clk)
            m.set_ack(1)
            dut.acka_n.value = 1
            await RisingEdge(dut.clk)
            await RisingEdge(dut.clk)
        await check_outputs(dut, m, f"t{t}")


def test_i8255():
    from runner import run
    run("sh_i8255", ["rtl/io/sh_i8255.sv"], "test_i8255")
