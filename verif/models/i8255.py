"""i8255 PPI, the subset this board uses, matching MAME i8255.cpp where the
two describe the same thing: mode 0 in/out on all ports (a read of an output
port returns its latch, a write to an input port only updates the latch),
BSR on port C, and the strobed OUTPUT handshake on group A — engaged by
mode 1 output (bits 6:5 = 01, A out) or mode 2 (bit 6 set; hangon programs
0xC0 and uses only the output half): /OBF on PC7, /ACK in on PC6, INTE via
BSR of PC6, INTR on PC3. A control-word write clears the latches and the
handshake state. Mode 2's input half and strobed input are not modelled.
"""


class I8255:
    def __init__(self):
        self.reset()

    def reset(self):
        self.latch_a = self.latch_b = self.latch_c = 0
        self.dir_a = self.dir_b = self.dir_cl = self.dir_cu = 1   # 1 = input
        self.mode1_a = False
        self.mode2_a = False
        self.obf_n = 1
        self.inte = 0
        self.intr = 0
        self.in_a = self.in_b = self.in_c = 0xFF
        self._ack_prev = 1

    def set_ack(self, level):
        """Drive the /ACK pin (group A mode-1 output handshake)."""
        if self.mode1_a:
            if level == 0:
                self.obf_n = 1
            if level == 1 and self._ack_prev == 0 and self.inte:
                self.intr = 1
        self._ack_prev = level

    def write(self, addr, data):
        data &= 0xFF
        if addr == 0:
            self.latch_a = data
            if self.mode1_a:
                self.obf_n = 0
                self.intr = 0
        elif addr == 1:
            self.latch_b = data
        elif addr == 2:
            self.latch_c = data
        else:
            if data & 0x80:
                self.mode1_a = (((data >> 5) & 3) == 1 and not (data & 0x10)) or bool(data & 0x40)
                self.mode2_a = bool(data & 0x40)
                self.dir_a = (data >> 4) & 1
                self.dir_cu = (data >> 3) & 1
                self.dir_b = (data >> 1) & 1
                self.dir_cl = data & 1
                self.latch_a = self.latch_b = self.latch_c = 0
                self.obf_n = 1
                self.inte = 0
                self.intr = 0
            else:
                bit = (data >> 1) & 7
                val = data & 1
                if self.mode1_a and bit == 6:
                    self.inte = val
                else:
                    self.latch_c = (self.latch_c & ~(1 << bit)) | (val << bit)

    def read(self, addr):
        if addr == 0:
            if self.mode2_a:
                return 0x00        # empty mode-2 input buffer (MAME's tri)
            return self.in_a if self.dir_a else self.latch_a
        if addr == 1:
            return self.in_b if self.dir_b else self.latch_b
        if addr == 2:
            pins = ((self.in_c if self.dir_cu else self.latch_c) & 0xF0) | \
                   ((self.in_c if self.dir_cl else self.latch_c) & 0x0F)
            if self.mode2_a:
                pins = (pins & 0x07) | (self.obf_n << 7) | (self.inte << 6) | \
                       ((self.latch_c >> 4 & 1) << 4) | (self.intr << 3)
            elif self.mode1_a:
                pins = (pins & 0x37) | (self.obf_n << 7) | (self.inte << 6) | (self.intr << 3)
            return pins
        return 0xFF   # control register reads FF on the 8255A

    @property
    def out_a(self):
        return self.latch_a

    @property
    def out_b(self):
        return self.latch_b

    @property
    def out_c(self):
        if self.mode1_a:
            return (self.obf_n << 7) | 0x40 | (self.latch_c & 0x30) | (self.intr << 3) | (self.latch_c & 7)
        return self.latch_c
