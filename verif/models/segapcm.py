"""Sega PCM, ported from MAME 0.289 segapcm.cpp (voice_t::tick). Two boards:
the 315-5218 (the YM2151 board: 16 voices, BANK_512 banking - bank shift 12,
mask 0x70, 64 KB banks) and the discrete-logic PCM board (the YM2203 board:
8 voices in the upper channel slots 8-15, no banking; the lower slots are
plain RAM). One call to tick() produces one stereo sample (the chip runs at
clock/128, the discrete board at clock/64: 62.5 kHz on both boards here).
Loop rule: a voice wraps (or stops) when its page reaches end + 1, as MAME
did through 0.288. 0.289's rewrite compares against `end` itself, which
silences Enduro Racer's engine loops (their loop page equals their end
page); the board plays them, so the older rule stands. The discrete-board
option (8 voices, no banking) is 0.289's model of the YM2203 board, kept
for reference but not used by the core."""


class SegaPCM:
    def __init__(self, rom, bankshift=12, bankmask=0x70, discrete=False):
        self.rom = rom                 # bytes; reads beyond the end return 0xFF
        self.ram = [0xFF] * 0x800
        self.low = [0] * 16
        self.bankshift, self.bankmask = bankshift, bankmask
        self.discrete = discrete
        if discrete:
            self.bankmask = 0

    def read_byte(self, a):
        return self.rom[a] if a < len(self.rom) else 0xFF

    def write(self, offset, data):
        self.ram[offset & 0x7FF] = data & 0xFF

    def read(self, offset):
        return self.ram[offset & 0x7FF]

    def tick(self):
        outl = outr = 0
        for ch in range(16):
            r = 8 * ch
            regs = self.ram
            if self.discrete and ch < 8:
                continue               # not a voice on the discrete board
            if regs[r + 0x86] & 1:
                continue
            offset = (regs[r + 0x86] & self.bankmask) << self.bankshift
            addr = (regs[r + 0x85] << 16) | (regs[r + 0x84] << 8) | self.low[ch]
            loop = (regs[r + 0x05] << 16) | (regs[r + 0x04] << 8)
            end = (regs[r + 6] + 1) & 0xFF   # MAME up to 0.288: the page after `end`. 0.289's rewrite
                                             # compares against `end` itself, which silences Enduro
                                             # Racer's engine loops (loop page == end page); the board
                                             # plays them (M8 hardware test), so the old rule stands
            stopped = False
            if (addr >> 16) == end:
                if regs[r + 0x86] & 2:
                    regs[r + 0x86] |= 1
                    stopped = True
                else:
                    addr = loop
            if not stopped:
                v = self.read_byte(offset + (addr >> 8)) - 0x80
                outl += v * (regs[r + 2] & 0x7F)
                outr += v * (regs[r + 3] & 0x7F)
                addr = (addr + regs[r + 7]) & 0xFFFFFF
            regs[r + 0x84] = (addr >> 8) & 0xFF
            regs[r + 0x85] = (addr >> 16) & 0xFF
            self.low[ch] = 0 if (regs[r + 0x86] & 1) else (addr & 0xFF)
        clamp = lambda x: max(-32768, min(32767, x))
        return clamp(outl), clamp(outr)
