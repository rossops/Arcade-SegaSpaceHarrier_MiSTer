"""The index-0 stream loader against the pack tool's slot table.

The MRA stream is [descriptor][main][sub][z80][pcm][mainops][sprite][tile]
[road][zoom][mcu][key], each region padded to the slot size in
tools/romsets.py. The loader lands the first six in SDRAM at (stream offset -
OFF_MAIN) and hands the rest to the core as BRAM writes tagged with the stream
offset, which sh_core routes by the OFF_* ranges in sh_pkg. So three things
must agree: the Python slot table, sh_pkg's OFF_* constants and the loader's
arithmetic. Space Harrier's MCU ROM was the first region to ride the tail of
the stream on hardware with no bench having exercised the path (M7).
"""
import os, re, sys
import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge, ReadOnly

ROOT = os.path.join(os.path.dirname(__file__), "..", "..", "..")
sys.path.insert(0, os.path.join(ROOT, "tools"))
from romsets import ROMSETS, SLOT, ORDER, DESC_SIZE
from pack_roms import descriptor

# stream offset of every region from the pack tool's table
START = {}
_o = DESC_SIZE
for _r in ORDER:
    START[_r] = _o
    _o += SLOT[_r]
STREAM_END = _o
SDRAM_REGIONS = ORDER[:6]           # main .. sprite
BRAM_REGIONS = ORDER[6:]            # tile .. key


def pkg_offsets():
    """OFF_* as sh_pkg.sv defines them (evaluated from the source text)."""
    src = open(os.path.join(ROOT, "rtl", "sh_pkg.sv")).read()
    vals = {}
    for m in re.finditer(r"localparam \[26:0\] (OFF_\w+)\s*=\s*([^;]+);", src):
        expr = m.group(2).split("//")[0].replace("27'h", "0x").replace("_", "")
        vals[m.group(1)] = eval(expr, {}, {k.replace("_", ""): v for k, v in vals.items()} | vals)
    return vals


def test_pkg_matches_slot_table():
    off = pkg_offsets()
    names = {"main": "OFF_MAIN", "sub": "OFF_SUB", "z80": "OFF_Z80", "pcm": "OFF_PCM",
             "mainops": "OFF_MAINOPS", "sprite": "OFF_SPR", "tile": "OFF_TILE",
             "road": "OFF_ROAD", "zoom": "OFF_ZOOM", "mcu": "OFF_MCU", "key": "OFF_KEY"}
    for r, n in names.items():
        assert off[n] == START[r], f"{n}={off[n]:#x} but the pack tool puts {r} at {START[r]:#x}"
    assert off["OFF_DESC"] == 0 and off["OFF_END"] == STREAM_END


def words(data):
    return [data[i] | (data[i + 1] << 8) for i in range(0, len(data), 2)]


def desc_fields(v):
    """board_desc_t packed order: game_id, six flags, sound_board, spr_banks, adc_reverse, ana_mode."""
    return {"ana_mode": v & 7, "adc_reverse": (v >> 3) & 0xFF, "spr_banks": (v >> 11) & 0xFF,
            "sound_board": (v >> 19) & 3, "ops_split": (v >> 21) & 1, "fd1094": (v >> 22) & 1,
            "fd1089b": (v >> 23) & 1, "has_mcu": (v >> 24) & 1, "cpu10m": (v >> 25) & 1,
            "sharrier_vid": (v >> 26) & 1, "game_id": (v >> 27) & 0xFF}


async def send(dut, addr, word):
    """One ioctl word, then wait for the loader to take it and any SDRAM write to be acked."""
    dut.ioctl_addr.value = addr
    dut.ioctl_dout.value = word
    dut.ioctl_wr.value = 1
    await RisingEdge(dut.clk)
    dut.ioctl_wr.value = 0
    sdr = None
    brm = None
    for _ in range(6):
        await ReadOnly()
        if int(dut.sdr_wr_req.value) and sdr is None:
            sdr = (int(dut.sdr_wr_addr.value), int(dut.sdr_wr_din.value), int(dut.sdr_wr_be.value))
            assert int(dut.ioctl_wait.value) == 1, f"{addr:#x}: no wait while the SDRAM write is pending"
        if int(dut.brm_wr.value):
            assert brm is None, f"{addr:#x}: two BRAM strobes"
            brm = (int(dut.brm_addr.value), int(dut.brm_din.value))
        await RisingEdge(dut.clk)
        if sdr is not None and int(dut.sdr_wr_req.value):
            dut.sdr_wr_ack.value = 1
            await RisingEdge(dut.clk)
            dut.sdr_wr_ack.value = 0
    return sdr, brm


async def load(dut, setname):
    rs = ROMSETS[setname]
    dut.ioctl_download.value = 1
    for i, w in enumerate(words(descriptor(rs))):
        sdr, brm = await send(dut, 2 * i, w)
        assert sdr is None and brm is None, "the descriptor is not memory"
    # the first and last word of every slot, with data that names the region
    for idx, r in enumerate(ORDER):
        for k, a in enumerate((START[r], START[r] + SLOT[r] - 2)):
            w = 0xA000 | (idx << 8) | k
            sdr, brm = await send(dut, a, w)
            if r in SDRAM_REGIONS:
                assert sdr == ((a - DESC_SIZE) >> 1, w, 3), f"{r} at {a:#x}: SDRAM write {sdr}"
                if r == "z80":
                    assert brm == (a, w), f"z80 at {a:#x}: expected the BRAM copy too, got {brm}"
                else:
                    assert brm is None, f"{r} at {a:#x}: unexpected BRAM strobe {brm}"
            else:
                assert sdr is None, f"{r} at {a:#x}: unexpected SDRAM write {sdr}"
                assert brm == (a, w), f"{r} at {a:#x}: BRAM strobe {brm}"
    # a word past the end of the stream goes nowhere
    sdr, brm = await send(dut, STREAM_END, 0xDEAD)
    assert sdr is None and brm is None, "a write past OFF_END was accepted"
    dut.ioctl_download.value = 0
    for _ in range(4): await RisingEdge(dut.clk)
    await ReadOnly()
    assert int(dut.rom_loaded.value) == 1, "rom_loaded never rose after the download"
    got = desc_fields(int(dut.board_desc.value))
    exp = {"game_id": rs["game_id"], "sharrier_vid": rs.get("sharrier", 0), "cpu10m": rs.get("cpu10m", 0),
           "has_mcu": rs.get("mcu", 0), "fd1089b": rs.get("fd1089b", 0), "fd1094": rs.get("fd1094", 0),
           "ops_split": rs.get("ops_split", 0), "sound_board": rs["sound_board"],
           "spr_banks": rs["spr_banks"], "adc_reverse": rs["adc_reverse"], "ana_mode": rs["ana_mode"] & 7}
    assert got == exp, f"{setname} descriptor: got {got}, expected {exp}"
    await RisingEdge(dut.clk)


@cocotb.test()
async def stream_slots(dut):
    cocotb.start_soon(Clock(dut.clk, 20, unit="ns").start())
    for s in ("mem_ready", "ioctl_download", "ioctl_index", "ioctl_wr", "ioctl_addr", "ioctl_dout", "sdr_wr_ack"):
        getattr(dut, s).value = 0
    dut.rst.value = 1
    for _ in range(3): await RisingEdge(dut.clk)
    dut.rst.value = 0
    dut.mem_ready.value = 1
    await RisingEdge(dut.clk)
    await load(dut, "sharrier")
    # a second set through the same loader (the MiSTer reloads without a reset)
    await load(dut, "hangon")


def test_rom_loader():
    sys.path.insert(0, os.path.join(os.path.dirname(__file__), ".."))
    from runner import run
    run("sh_rom_loader", ["rtl/sh_pkg.sv", "rtl/mem/sh_rom_loader.sv"], "test_rom_loader")
