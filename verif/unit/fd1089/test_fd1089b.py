"""sh_fd1089b against the Python port of MAME's FD1089B (verif/models/fd1089.py),
which itself matches MAME's decrypted Enduro Racer set word for word (bar the
bootleg's own two-word patch). The block is combinational: random words, key
bytes and fetch types first, then the real 317-0013A key across the first
64 KB of Enduro Racer's ROM with both fetch types."""
import os, random, sys, zipfile
import cocotb
from cocotb.triggers import Timer

ROOT = os.path.join(os.path.dirname(__file__), "..", "..", "..")
sys.path.insert(0, os.path.join(ROOT, "verif", "models"))
from fd1089 import decrypt_one, key_index

ZIP = "/Volumes/roms/Arcade/MAME 0.289 ROMs (merged)/enduror.zip"


async def check(dut, din, key, opcode, exp, what):
    dut.din.value = din; dut.key.value = key; dut.opcode.value = opcode
    await Timer(1, unit="ns")
    got = int(dut.dout.value)
    assert got == exp, f"{what}: din {din:04x} key {key:02x} op {opcode}: got {got:04x} expected {exp:04x}"


@cocotb.test()
async def random_words(dut):
    rng = random.Random(1089)
    for i in range(20000):
        din = rng.randrange(0x10000); key = rng.randrange(256); op = rng.randrange(2)
        # a fake single-entry key so decrypt_one sees this byte at any index
        exp = decrypt_one(0, din, [key] * 0x2000, op)
        await check(dut, din, key, op, exp, f"random {i}")


@cocotb.test()
async def enduro_racer_rom(dut):
    if not os.path.exists(ZIP):
        dut._log.warning("no enduror.zip; skipping the real-key pass")
        return
    zf = zipfile.ZipFile(ZIP)
    key = zf.read("317-0013a.key")
    ev, od = zf.read("epr-7640a.ic97"), zf.read("epr-7636a.ic84")
    for i in range(0, 0x8000, 1):
        a = 2 * i
        din = (ev[i] << 8) | od[i]
        for op in (1, 0):
            k = key[key_index(a) + (0 if op else 0x1000)]
            await check(dut, din, k, op, decrypt_one(a, din, key, op), f"rom {a:06x}")


def test_fd1089b():
    sys.path.insert(0, os.path.join(os.path.dirname(__file__), ".."))
    from runner import run
    run("sh_fd1089b", ["rtl/cpu/sh_fd1089b.sv"], "test_fd1089b")
