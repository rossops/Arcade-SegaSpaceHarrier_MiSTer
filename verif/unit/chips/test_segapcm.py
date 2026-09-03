"""315-5218: per-tick output must equal MAME's model (Python port) with a
random ROM and random channel programming including loop/end/stop
semantics and bank bits (segahang is BANK_512 on every set: bits 6:4,
mask 0x70, shift 12; banks beyond the 64 KB test ROM read 0xFF in model
and RTL alike)."""
import random, sys, os
import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge, ReadOnly, ClockCycles

sys.path.insert(0, os.path.join(os.path.dirname(__file__), "..", ".."))
from models.segapcm import SegaPCM

ROM = bytes(random.Random(5218).randrange(256) for _ in range(0x10000)) + bytes()  # 64 KB test ROM


async def serve_rom(dut):
    """SDRAM p6 stand-in: word reads from ROM (0xFF beyond), 6-cycle latency."""
    dut.rom_ack.value = 0
    prev = 0
    while True:
        await RisingEdge(dut.clk)
        req = int(dut.rom_req.value)
        if req and not prev:
            a = int(dut.rom_addr.value) * 2 - 0x090000     # SDR_PCM_BASE
            lo = ROM[a] if 0 <= a < len(ROM) else 0xFF
            hi = ROM[a + 1] if 0 <= a + 1 < len(ROM) else 0xFF
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
async def random_channels(dut):
    cocotb.start_soon(Clock(dut.clk, 20, unit="ns").start())
    for s in ("tick", "cs", "we", "addr", "din", "rom_ack", "rom_dout"): getattr(dut, s).value = 0
    dut.bankmask.value = 0x70
    dut.reset.value = 1
    for _ in range(3): await RisingEdge(dut.clk)
    dut.reset.value = 0
    await RisingEdge(dut.clk)
    cocotb.start_soon(serve_rom(dut))
    m = SegaPCM(ROM)
    rng = random.Random(1)
    for t in range(600):
        # reprogram a few channels between ticks (only when the engine idles)
        for _ in range(rng.randrange(3)):
            ch = rng.randrange(16)
            prog = {
                0x02: rng.randrange(128), 0x03: rng.randrange(128),
                0x04: rng.randrange(256), 0x05: rng.randrange(1),          # loop within the 64 KB ROM
                0x06: rng.randrange(1, 4), 0x07: rng.choice([0x40, 0x80, 0x100 - 1, rng.randrange(256)]),
                0x84: rng.randrange(256), 0x85: rng.randrange(1),
                0x86: rng.choice([0x00, 0x02, 0x00, 0x10, 0x30, 0x70, 0x01]),
            }
            for off, val in prog.items():
                m.write(8 * ch + off, val)
                await z80_write(dut, 8 * ch + off, val)
        exp = m.tick()
        dut.tick.value = 1
        await RisingEdge(dut.clk)
        dut.tick.value = 0
        # engine: up to 16 channels x ~12 cycles
        for _ in range(400):
            await RisingEdge(dut.clk)
            if int(dut.es.value) == 0: break
        await ReadOnly()
        got = (int(dut.out_l.value.to_signed()), int(dut.out_r.value.to_signed()))
        assert got == exp, f"tick {t}: got {got} expected {exp}"
        await RisingEdge(dut.clk)
        # register state must match too (address write-back, stop flags)
        for ch in range(16):
            for off in (0x84, 0x85, 0x86):
                dut.cs.value = 1; dut.we.value = 0; dut.addr.value = 8 * ch + off
                await RisingEdge(dut.clk); await ReadOnly()
                await RisingEdge(dut.clk); await ReadOnly()
                v = int(dut.dout.value)
                assert v == m.read(8 * ch + off), f"tick {t}: ch{ch} reg {off:02x} = {v:02x} model {m.read(8*ch+off):02x}"
                await RisingEdge(dut.clk)
        dut.cs.value = 0


E_LOAD, E_CHECK, E_FETCH, E_WAIT, E_ACC = 1, 2, 3, 4, 5


async def write_in_state(dut, ch, state, addr, data):
    """Land one Z80 register write while the engine is in `state` on
    channel `ch` (the write is sampled by the clock edge that leaves it)."""
    from cocotb.triggers import Timer
    while True:
        await RisingEdge(dut.clk)
        await ReadOnly()
        if int(dut.ch.value) == ch and int(dut.es.value) == state:
            break
    await Timer(1, unit="ns")
    dut.cs.value = 1; dut.we.value = 1; dut.addr.value = addr; dut.din.value = data
    await RisingEdge(dut.clk)
    await Timer(1, unit="ns")
    dut.cs.value = 0; dut.we.value = 0


async def read_reg(dut, addr):
    dut.cs.value = 1; dut.we.value = 0; dut.addr.value = addr
    await RisingEdge(dut.clk); await ReadOnly()
    await RisingEdge(dut.clk); await ReadOnly()
    v = int(dut.dout.value)
    await RisingEdge(dut.clk)
    dut.cs.value = 0
    return v


@cocotb.test()
async def write_during_engine(dut):
    """Why: the sound driver restarts voices while they play (engine note,
    rapid sound-test switching). MAME runs the stream up to the write
    before applying it, so the Z80's new address always stands and that
    tick's sample still comes from the old one. The engine here spreads a
    channel over tens of clocks (SDRAM wait); a write landing inside that
    window must not be clobbered by the stale address write-back, and a
    flags write must not be clobbered by the end-of-sample stop bit."""
    cocotb.start_soon(Clock(dut.clk, 20, unit="ns").start())
    for s in ("tick", "cs", "we", "addr", "din", "rom_ack", "rom_dout"): getattr(dut, s).value = 0
    dut.bankmask.value = 0x70
    dut.reset.value = 1
    for _ in range(3): await RisingEdge(dut.clk)
    dut.reset.value = 0
    await RisingEdge(dut.clk)
    cocotb.start_soon(serve_rom(dut))
    m = SegaPCM(ROM)
    rng = random.Random(2)
    # four looping voices so the engine is busy on the way to channel 3
    for ch in range(4):
        for off, val in {0x02: 0x40, 0x03: 0x40, 0x04: 0x00, 0x05: 0x00, 0x06: 0x00,
                         0x07: 0x80, 0x84: 0x10 * (ch + 1), 0x85: 0x00, 0x86: 0x00}.items():
            m.write(8 * ch + off, val); await z80_write(dut, 8 * ch + off, val)

    async def one_tick(t, writes):
        exp = m.tick()
        dut.tick.value = 1
        await RisingEdge(dut.clk)
        dut.tick.value = 0
        # the first write waits for its engine state; any further write
        # follows it two clocks later (waiting again could miss the state)
        for n, (st, addr, data) in enumerate(writes):
            if n == 0: await write_in_state(dut, 3, st, addr, data)
            else: await z80_write(dut, addr, data)
            m.write(addr, data)                  # MAME: update, then write
        for _ in range(400):
            await RisingEdge(dut.clk)
            if int(dut.es.value) == 0: break
        await ReadOnly()
        got = (int(dut.out_l.value.to_signed()), int(dut.out_r.value.to_signed()))
        assert got == exp, f"tick {t}: got {got} expected {exp}"
        await RisingEdge(dut.clk)
        for off in (0x84, 0x85, 0x86):
            v = await read_reg(dut, 0x18 + off)
            assert v == m.read(0x18 + off), \
                f"tick {t}: ch3 reg {off:02x} = {v:02x} model {m.read(0x18+off):02x} after writes {writes}"

    # address restarts landing in every engine state of channel 3
    for t in range(150):
        st = rng.choice([E_LOAD, E_CHECK, E_FETCH, E_WAIT, E_ACC])
        w = [(st, 0x9C, rng.randrange(256))]
        if rng.randrange(2): w.append((None, 0x9D, 0))
        await one_tick(t, w)
    # a one-shot voice hitting its end: the driver restarts it in the same
    # tick the engine wants to set the stop bit
    for off, val in {0x86: 0x02, 0x84: 0xFF, 0x85: 0x00, 0x07: 0x80}.items():
        m.write(0x18 + off, val); await z80_write(dut, 0x18 + off, val)
    for t in range(150, 160):
        st = rng.choice([E_LOAD, E_CHECK])
        await one_tick(t, [(st, 0x9E, 0x02)])


def test_segapcm():
    from runner import run
    run("sh_segapcm_5218", ["rtl/sh_pkg.sv", "rtl/audio/sh_segapcm_5218.sv"], "test_segapcm")
