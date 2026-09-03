//============================================================================
//  Sega 315-5218 PCM (SegaPCM), MAME segapcm.cpp. The Y Board configures
//  BANK_12M | BANK_MASKF8: bank shift 13 and bank mask 0xF8 (register 0x86
//  bits 7:3 in 64 KB units, the whole 2 MB region); the X Board was shift
//  12 with mask 0x70. 16 channels, register RAM at 8*ch:
//    0x02 vol L, 0x03 vol R, 0x04/0x05 loop (bits 15:8 / 23:16), 0x06 end
//    (compared with addr[23:16] + 1), 0x07 delta, 0x84/0x85 current address
//    (bits 15:8 / 23:16), 0x86 flags: bit0 stop, bit1 no loop, 7:3 bank.
//  Every 128 chip clocks (31.25 kHz) each active channel advances by delta
//  (8.8 fixed point in addr[15:0]), fetches ROM byte offset + addr[23:8],
//  and adds (byte - 0x80) * vol to the left/right sums. The sums are in
//  MAME's 1/32768 units, i.e. directly 16-bit samples.
//  ROM bytes come from SDRAM port p6 (16-bit words, byte selected by A0);
//  the stream pads the PCM slot with 0xFF like MAME's ERASEFF region.
//============================================================================
import sh_pkg::*;

module sh_segapcm_5218 #(
    parameter [24:0] PCM_BASE  = SDR_PCM_BASE,
    parameter        BANKSHIFT = 12            // MAME m_bankshift (BANK_512: every segahang set)
) (
    input             clk,          // clk_sys
    input             reset,
    input             tick,         // one pulse per 128 chip clocks (31.25 kHz)
    input       [7:0] bankmask,     // 0x70 (BANK_512, bank bits 6:4) on every set here

    // Z80 register access (F000-F0FF)
    input             cs,
    input             we,
    input       [7:0] addr,
    input       [7:0] din,
    output      [7:0] dout,

    // SDRAM p6
    output reg        rom_req,
    output reg [24:1] rom_addr,
    input      [15:0] rom_dout,
    input             rom_ack,

    output reg signed [15:0] out_l,
    output reg signed [15:0] out_r,
    output reg        tick_lost     // pulse: a tick arrived while the engine was still busy
);

reg  [7:0] regs [0:255];
reg [7:0] low [0:15];               // MAME m_low: addr[7:0] per channel
integer i;

// Z80 side: registered read
reg [7:0] rd_q;
assign dout = rd_q;

// engine
typedef enum logic [2:0] { E_IDLE, E_LOAD, E_CHECK, E_FETCH, E_WAIT, E_ACC, E_NEXT, E_DONE } es_t;
es_t es;
reg  [3:0] ch;
reg [23:0] a;
reg [23:0] loop;
reg  [7:0] endb, delta, volr, voll, flags;
reg  [7:0] bank;
reg        rom_odd;
reg signed [19:0] sum_l, sum_r;

// The engine spreads one channel over tens of clocks (E_LOAD reads the
// registers, E_ACC writes the advanced address back after the SDRAM
// fetch). MAME runs the stream up to every register write before applying
// it, so a driver restarting a playing voice always ends with its new
// address in 0x84/0x85. Here a Z80 write landing inside the channel's
// window would be clobbered by the stale write-back - the voice then plays
// from old+delta instead of the new start, and a looped voice does so
// until the driver reloads it (Hang-On's engine note distorted mid-race,
// the service menu's sound test reproduced it by switching samples
// quickly). So: a Z80 write to 0x84/0x85/0x86 of the channel in flight
// marks that byte dirty and the engine skips its own write to it; the
// sample already accumulated from the old address stands, as MAME's does.
wire hit84 = cs && we && addr == {1'b1, ch, 3'd4};
wire hit85 = cs && we && addr == {1'b1, ch, 3'd5};
wire hit86 = cs && we && addr == {1'b1, ch, 3'd6};
reg  d84, d85, d86;

// register RAM: the Z80 write is last in the block so it wins a same-clock
// collision with the engine; the dirty flags cover the earlier clocks
always @(posedge clk) begin
    if (reset) begin
        for (i = 0; i < 256; i = i + 1) regs[i] <= 8'hFF;
        for (i = 0; i < 16; i = i + 1) low[i] <= 8'd0;
        es <= E_IDLE; rom_req <= 1'b0; out_l <= 0; out_r <= 0; ch <= 0;
        sum_l <= 0; sum_r <= 0; d84 <= 1'b0; d85 <= 1'b0; d86 <= 1'b0;
        tick_lost <= 1'b0;
    end
    else begin
        rom_req <= 1'b0;
        rd_q <= regs[addr];
        tick_lost <= tick && es != E_IDLE;
        // dirty: set from E_LOAD's own clock through E_ACC, cleared between channels
        if (es == E_LOAD) begin d84 <= hit84; d85 <= hit85; d86 <= hit86; end
        else if (es == E_CHECK || es == E_FETCH || es == E_WAIT || es == E_ACC) begin
            d84 <= d84 | hit84; d85 <= d85 | hit85; d86 <= d86 | hit86;
        end
        else begin d84 <= 1'b0; d85 <= 1'b0; d86 <= 1'b0; end
`ifdef SIMULATION
        if (tick && es != E_IDLE) $display("PCMTICK dropped: engine still busy (ch %0d state %0d)", ch, es);
`endif

        case (es)
        E_IDLE: if (tick) begin ch <= 4'd0; sum_l <= 0; sum_r <= 0; es <= E_LOAD; end
        E_LOAD: begin
            flags <= regs[{1'b1, ch, 3'd6}];
            bank  <= regs[{1'b1, ch, 3'd6}] & bankmask;
            a     <= {regs[{1'b1, ch, 3'd5}], regs[{1'b1, ch, 3'd4}], low[ch]};
            loop  <= {regs[{1'b0, ch, 3'd5}], regs[{1'b0, ch, 3'd4}], 8'd0};
            endb  <= regs[{1'b0, ch, 3'd6}] + 8'd1;
            delta <= regs[{1'b0, ch, 3'd7}];
            voll  <= regs[{1'b0, ch, 3'd2}] & 8'h7F;
            volr  <= regs[{1'b0, ch, 3'd3}] & 8'h7F;
            es <= E_CHECK;
        end
        E_CHECK: begin
            if (flags[0]) es <= E_NEXT;                       // inactive
            else if (a[23:16] == endb) begin
                if (flags[1]) begin                           // no loop: stop
                    if (!(d86 | hit86)) regs[{1'b1, ch, 3'd6}][0] <= 1'b1;
                    low[ch] <= 8'd0;
                    es <= E_NEXT;
                end
                else begin a <= loop; es <= E_FETCH; end
            end
            else es <= E_FETCH;
        end
        E_FETCH: begin
            // byte address: ((flags & bankmask) << BANKSHIFT) + addr[23:8]
            logic [24:0] ba;
            ba = PCM_BASE + (25'(bank) << BANKSHIFT) + {9'd0, a[23:8]};
            rom_addr <= ba[24:1];
            rom_odd  <= ba[0];
            rom_req  <= 1'b1;
            es <= E_WAIT;
        end
        E_WAIT: if (rom_ack) es <= E_ACC;
        E_ACC: begin
            logic signed [8:0] v;
            logic [23:0] na;
            v = $signed({1'b0, rom_odd ? rom_dout[15:8] : rom_dout[7:0]}) - 9'sd128;
            sum_l <= sum_l + v * $signed({1'b0, voll});
            sum_r <= sum_r + v * $signed({1'b0, volr});
            na = a + {16'd0, delta};
            if (!(d84 | hit84)) regs[{1'b1, ch, 3'd4}] <= na[15:8];
            if (!(d85 | hit85)) regs[{1'b1, ch, 3'd5}] <= na[23:16];
            low[ch] <= na[7:0];
`ifdef SIMULATION
            if (d84 | hit84 | d85 | hit85) $display("PCMRACE ch %0d: Z80 rewrote the address mid-engine, write-back skipped", ch);
`endif
            es <= E_NEXT;
        end
        E_NEXT: begin
            if (ch == 4'd15) es <= E_DONE;
            else begin ch <= ch + 4'd1; es <= E_LOAD; end
        end
        E_DONE: begin
            // (16'sh8000: Quartus flags -16'sd32768 as a constant overflow)
            out_l <= (sum_l > 20'sd32767) ? 16'sd32767 : (sum_l < -20'sd32768) ? 16'sh8000 : sum_l[15:0];
            out_r <= (sum_r > 20'sd32767) ? 16'sd32767 : (sum_r < -20'sd32768) ? 16'sh8000 : sum_r[15:0];
            es <= E_IDLE;
        end
        default: es <= E_IDLE;
        endcase

        if (cs && we) regs[addr] <= din;
    end
end
endmodule
