#!/usr/bin/env python3
"""Generate MiSTer .mra files for every set in tools/romsets.py.

    gen_mra.py [--outdir releases]

The <rom index="0"> part must produce byte-for-byte the stream pack_roms.py
builds (tests/test_stream.py checks that).
"""
import argparse, os, sys

sys.path.insert(0, os.path.dirname(__file__))
from romsets import ROMSETS, SLOT, ORDER, DESC_SIZE
from pack_roms import descriptor, last_region, file_fields, file_size

# Bare name, no "Arcade-": Distribution_MiSTer strips that prefix from the
# packaged .rbf, and the MiSTer loader matches a bare tag against both
# SegaSpaceHarrier_*.rbf and Arcade-SegaSpaceHarrier_*.rbf (X Board issue #3).
RBF = "SegaSpaceHarrier"

# hiscore.v's config header (<rom index="5">): wait 0.34 s after reset, then
# check every 1.3 ms until the game's defaults are in place, and 8 paused
# cycles around each RAM access. The X and Y Board cores use the same values.
HS_HEADER = (
    (0x00FFFFFF).to_bytes(4, "big") +   # START_WAIT
    (0xFFFF).to_bytes(2, "big") +       # CHECK_WAIT
    (4).to_bytes(2, "big") +            # CHECK_HOLD
    (4).to_bytes(2, "big") +            # WRITE_HOLD
    (1).to_bytes(2, "big") +            # WRITE_REPEATCOUNT
    (15).to_bytes(2, "big") +           # WRITE_REPEATWAIT
    bytes([8, 0]))                      # ACCESS_PAUSEPAD, CHANGEMASK
HS_BUFFER = 2048                        # sh_hiscore's score buffer (HS_SCOREWIDTH 11)


def hiscore_config(rs):
    """The <rom index="5"> bytes for a set with a `hiscore` table."""
    out = bytearray(HS_HEADER)
    for addr, length, start, end in rs["hiscore"]:
        if not 0 < length < 0x10000:
            raise SystemExit("hiscore entry length must fit two bytes")
        out += addr.to_bytes(4, "big") + length.to_bytes(2, "big") + bytes([start, end])
    if hiscore_size(rs) > HS_BUFFER:
        raise SystemExit("hiscore table larger than the score buffer")
    return bytes(out)


def hiscore_size(rs):
    """The <nvram index="4"> size: the entries back to back."""
    return sum(e[1] for e in rs["hiscore"])


def hexbytes(b):
    return " ".join(f"{x:02x}" for x in b)


def region_parts(loader, files, slot, fill="00", pad_to_slot=True):
    lines = []
    total = 0
    # a part attribute for the files MAME loads only the head of
    lens = {f[0]: f' length="{f[1]:#x}"' if file_size(f) > f[1] else "" for f in files}
    files = [file_fields(f) for f in files]
    if loader != "flat" and any(rep > 1 for _, _, _, rep in files):
        raise SystemExit("repeat is only supported in flat regions")
    if loader == "flat":
        for n, s, c, rep in files:
            # MAME ROM_RELOAD mirrors: the same file listed again; "-" is a
            # zero-filled gap (pack_roms.read_rom)
            for _ in range(rep):
                lines.append(f'      <part repeat="{s}">{fill}</part>' if n == "-" else f'      <part name="{n}" crc="{c}"{lens[n]}/>')
            total += s * rep
    elif loader == "w16":
        for i in range(0, len(files), 2):
            (e, s, ec, _), (o, _, oc, _) = files[i], files[i + 1]
            if e == "-" and o == "-":
                # a gap pair (endurobl's main region has no ROM below 0x10000)
                lines.append(f'      <part repeat="{2 * s}">{fill}</part>')
                total += 2 * s
                continue
            lines.append('      <interleave output="16">')
            # map digits are byte positions, rightmost = byte 0. The stream word
            # is little-endian and must read back as {even, odd} (68000 order),
            # so the even ROM is byte 1 ("10") and the odd ROM byte 0 ("01").
            lines.append(f'        <part name="{e}" crc="{ec}"{lens[e]} map="10"/>')
            lines.append(f'        <part name="{o}" crc="{oc}"{lens[o]} map="01"/>')
            lines.append('      </interleave>')
            total += 2 * s
    elif loader == "x32":
        for i in range(0, len(files), 4):
            grp = files[i:i + 4]
            lines.append('      <interleave output="32">')
            # MAME REGION32_LE: ROM k is byte k of the little-endian dword
            # (pack_roms.build_region), so ROM k is map digit k from the right
            for k, (n, s, c, _) in enumerate(grp):
                m = ["0"] * 4
                m[3 - k] = "1"
                lines.append(f'        <part name="{n}" crc="{c}"{lens[n]} map="{"".join(m)}"/>')
            lines.append('      </interleave>')
            total += 4 * grp[0][1]
    else:
        raise ValueError(loader)
    pad = slot - total
    if pad < 0:
        raise SystemExit("region exceeds slot")
    if pad and pad_to_slot:
        lines.append(f'      <part repeat="{pad}">{fill}</part>')
    return lines


def make_mra(key, rs):
    L = []
    L.append('<misterromdescription>')
    L.append(f'  <name>{rs["name"]}</name>')
    L.append(f'  <setname>{key}</setname>')
    L.append(f'  <rbf>{RBF}</rbf>')
    L.append(f'  <mameversion>0289</mameversion>')
    L.append(f'  <year>{rs["year"]}</year>')
    L.append('  <manufacturer>Sega</manufacturer>')
    L.append(f'  <category>{rs.get("category", "Racing / Driving")}</category>')
    zips = rs["zipfile"] + ".zip" if rs["zipfile"] == key else "|".join(
        f"{z}.zip" for z in [key] + rs.get("extra_zips", []) + [rs["zipfile"]])
    L.append(f'  <rom index="0" zip="{zips}" md5="None">')
    L.append(f'    <part>{hexbytes(descriptor(rs))}</part>')
    last = last_region(rs)
    for idx, region in enumerate(ORDER[:last + 1]):
        loader, files = rs["regions"].get(region, ("flat", []))
        L.append(f'    <!-- {region} -->')
        # zero fill everywhere (no ERASEFF regions in segahang); the last
        # region a set populates ships unpadded
        L += region_parts(loader, files, SLOT[region], "00", idx != last)
    L.append('  </rom>')
    # no battery RAM on this board: the only saved file is hiscore.v's table
    # (docs/DESIGN.md M12), restored into the game's work RAM
    if "hiscore" in rs:
        L.append('  <rom index="5">')
        L.append(f'    <part>{hexbytes(hiscore_config(rs))}</part>')
        L.append('  </rom>')
        L.append(f'  <nvram index="4" size="{hiscore_size(rs)}"/>')
    # DIP switches: raw port values (1 = off). Defaults are MAME's.
    L.append(f'  <switches default="{rs["dip_default"]}" base="0">')
    for lo, hi, name, ids in rs["dips"]:
        bits = f"{lo}" if lo == hi else f"{lo},{hi}"
        L.append(f'    <dip bits="{bits}" name="{name}" ids="{ids}"/>')
    L.append('  </switches>')
    names, default = rs["buttons"]
    L.append(f'  <buttons names="{names}" default="{default}"/>')
    L.append('</misterromdescription>')
    return "\n".join(L) + "\n"


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--outdir", default=os.path.join(os.path.dirname(__file__), "..", "releases"))
    a = ap.parse_args()
    os.makedirs(a.outdir, exist_ok=True)
    for key, rs in ROMSETS.items():
        # MiSTer layout: one primary MRA per game in releases/, the other
        # versions under releases/_alternatives/_<game>/
        sub = os.path.join("_alternatives", "_" + rs["alt"]) if "alt" in rs else ""
        os.makedirs(os.path.join(a.outdir, sub), exist_ok=True)
        path = os.path.join(a.outdir, sub, f'{rs["name"]}.mra')
        with open(path, "w") as f:
            f.write(make_mra(key, rs))
        print(path)


if __name__ == "__main__":
    main()
