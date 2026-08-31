"""The MRA the host expands and the packer's stream must be byte-identical,
and every region must match MAME's ROM CRCs. Both feed the same descriptor and
SDRAM slots, so a drift here would silently misplace ROMs on hardware."""
import os, sys, zipfile, zlib
import pytest

HERE = os.path.dirname(__file__)
sys.path.insert(0, os.path.join(HERE, ".."))
import romsets, pack_roms, gen_mra

ZIPDIR = "/Volumes/roms/Arcade/MAME 0.289 ROMs (merged)"


def expand_mra(text, zf):
    """Minimal MRA expander for the subset gen_mra emits."""
    import re
    out = bytearray()
    lines = text.splitlines()
    i = 0
    def rom(name):
        c = [n for n in zf.namelist() if n.split("/")[-1] == name]
        return zf.read(c[0])
    while i < len(lines):
        s = lines[i].strip()
        m = re.match(r'<part repeat="(\d+)">([0-9A-Fa-f]{2})</part>', s)
        if m:
            out += bytes([int(m.group(2), 16)]) * int(m.group(1))
        elif s.startswith("<part>") and s.endswith("</part>"):
            out += bytes.fromhex(s[6:-7].replace(" ", ""))
        elif s.startswith('<part name="') and s.endswith('/>') and "map=" not in s:
            out += rom(re.search(r'name="([^"]+)"', s).group(1))
        elif s.startswith('<interleave output="'):
            width = int(re.search(r'output="(\d+)"', s).group(1)) // 8
            parts = []
            i += 1
            while "</interleave>" not in lines[i]:
                m = re.search(r'name="([^"]+)".* map="([01]+)"', lines[i])
                parts.append((rom(m.group(1)), m.group(2)))
                i += 1
            n = len(parts[0][0])
            for j in range(n):
                word = bytearray(width)
                for data, mp in parts:
                    # map is MSB-first over the output word; MiSTer emits LE
                    for k, ch in enumerate(reversed(mp)):
                        if ch == "1":
                            word[k] = data[j]
                out += word
        i += 1
    return bytes(out)


@pytest.mark.parametrize("key", list(romsets.ROMSETS))
def test_mra_matches_packer(key):
    rs = romsets.ROMSETS[key]
    zp = os.path.join(ZIPDIR, rs["zipfile"] + ".zip")
    if not os.path.exists(zp):
        pytest.skip("ROM zip not available")
    try:
        stream, regions = pack_roms.build_stream(key, zp)
    except SystemExit as e:
        # a clone whose files this ROM collection lacks: the MRA is still
        # generated from MAME's CRCs and CI's mra_rom_check covers it
        pytest.skip(f"{e} in the local {rs['zipfile']}.zip")
    last = pack_roms.last_region(rs)
    # every region padded to its slot except the last one
    expected = romsets.DESC_SIZE + sum(romsets.SLOT[r] for r in romsets.ORDER[:last]) + len(regions[romsets.ORDER[last]])
    assert len(stream) == expected
    with zipfile.ZipFile(zp) as zf:
        mra = expand_mra(gen_mra.make_mra(key, rs), zf)
    assert len(mra) == len(stream)
    assert mra == stream


@pytest.mark.parametrize("key", list(romsets.ROMSETS))
def test_region_crcs(key):
    rs = romsets.ROMSETS[key]
    zp = os.path.join(ZIPDIR, rs["zipfile"] + ".zip")
    if not os.path.exists(zp):
        pytest.skip("ROM zip not available")
    with zipfile.ZipFile(zp) as zf:
        for region, (loader, files) in rs["regions"].items():
            for f in files:
                n, s, c, _ = pack_roms.file_fields(f)
                try:
                    pack_roms.read_rom(zf, n, s, c)   # raises on mismatch
                except SystemExit as e:
                    if "missing ROM" in str(e):
                        pytest.skip(f"{e} in the local {rs['zipfile']}.zip")
                    raise


def test_w16_word_order():
    # even ROM byte goes to the high byte of the SDRAM word (68000 big-endian)
    out = pack_roms.build_region("w16", [bytes([0x12]), bytes([0x34])])
    assert out == bytes([0x34, 0x12])
    assert int.from_bytes(out, "little") == 0x1234


def test_x32_word_order():
    # MAME REGION32_LE (the sharrier sprite ROMs): ROM k is byte k of the
    # little-endian dword; the two SDRAM words hold (b0,b1) then (b2,b3),
    # so the renderer reads the dword back as MAME does.
    out = pack_roms.build_region("x32", [bytes([k + 1]) for k in range(4)])
    assert out == bytes([1, 2, 3, 4])
    assert int.from_bytes(out, "little") == 0x04030201


def test_empty_middle_region_pads_to_slot():
    # hangon has no mainops image; the region between pcm and sprite must
    # still occupy its whole slot so the sprite ROM lands at its offset
    rs = romsets.ROMSETS["hangon"]
    assert "mainops" not in rs["regions"]
    last = pack_roms.last_region(rs)
    assert romsets.ORDER[last] == "zoom"   # no mcu/key either; stream ends there
    parts = gen_mra.region_parts("flat", [], romsets.SLOT["mainops"], "00")
    assert parts == [f'      <part repeat="{romsets.SLOT["mainops"]}">00</part>']
