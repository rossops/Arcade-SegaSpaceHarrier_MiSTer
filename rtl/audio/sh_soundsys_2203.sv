//============================================================================
//  The YM2203 sound board (hangon, sharrier, enduror1): Z80 (tv80) at
//  4 MHz, YM2203 (jt03) at 4 MHz memory-mapped at D000, 315-5218 PCM at
//  E000 ticking at 8 MHz/128 = 62.5 kHz, ROM 0000-7FFF in zero-wait BRAM
//  (the PCB's private ROM; see the note at the ROM), RAM C000-C7FF
//  (mirror 0800). The only port is 0x40 (mirror 3F): the sound latch read,
//  which answers the main PPI's mode-1 handshake (/ACK empties /OBF, the
//  Z80's NMI). INT comes from the YM2203's timers. The Z80 is tv80 on a
//  clock enable (the T80 is a bench-only option, see below).
//  Mix, from MAME's segahang routes with the ymfm rotation understood
//  (outputs 0-2 = SSG A/B/C, 3 = FM): SSG 0.05 each, FM 0.15, PCM 0.40,
//  as 1/256 gain parameters. The 8-bit SSG channels are scaled by 128
//  into the 16-bit sum.
//============================================================================
import sh_pkg::*;

module sh_soundsys_2203 #(
    parameter [24:0] PCM_BASE = SDR_PCM_BASE,
    parameter        PCM_GAIN = 102,          // 0.40 * 256
    parameter        FM_GAIN  = 38,           // 0.15 * 256
    parameter        SSG_GAIN = 13            // 0.05 * 256
) (
    input             clk,          // clk_sys
    input             reset,
    input             z80_reset_n,  // PPI0 port B bit 5
    input             ce_z80,       // 4 MHz
    input             ce_z80x2,     // 8 MHz (simulation only: tv80 clock toggle)
    input             ce_fm,        // 4 MHz (jt03 cen)
    input             pcm_tick,     // 62.5 kHz (8 MHz / 128)
    input             mute_n,       // PPI0 port C bit 0
    input       [7:0] pcm_bankmask, // 0x70 (BANK_512) on every set

    input       [7:0] snd_latch,
    input             snd_nmi,
    output            snd_read,     // pulse: Z80 read of port 0x40 (/ACK)

    // loader: 16-bit stream words of the Z80 ROM (OFF_Z80-relative bytes)
    input             zbrm_wr,
    input      [14:0] zbrm_addr,
    input      [15:0] zbrm_din,

    // SDRAM
    output            pcm_req,   output [24:1] pcm_addr,  input [15:0] pcm_dout,  input pcm_ack,

    output signed [15:0] audio_l,
    output signed [15:0] audio_r,
    output            pcm_tick_lost, // debug: PCM engine missed a tick (SDRAM too slow)
    output            z80_fetch_ram  // debug: opcode fetch outside the ROM (the program crashed)
);

wire [15:0] z_addr;
wire  [7:0] z_dout;
reg   [7:0] z_din;
wire        z_mreq_n, z_iorq_n, z_rd_n, z_wr_n, z_m1_n;
wire        ym_irq_n;
wire        z_wait_n;
wire [15:0] z80_dbg;     // Z80 state (NMI latch, NMI/INT cycle, prefix, M-cycle, T-state...), bench logs only
// The Z80 and jt03 reset asynchronously ("always @(posedge clk, posedge
// rst)" / "negedge reset_n"), unlike every other block here, which samples
// reset at the clock. The core's reset is a combinational OR that includes
// the PLL's asynchronous lock output, so it is registered before it
// reaches them: a register cannot glitch. (It was not the M6 sound crash -
// that was the T80 itself, see the file header - but it is the rule for
// every asynchronous-reset boundary from here on.)
reg         z_rst_n = 1'b0;
always @(posedge clk) z_rst_n <= ~reset & z80_reset_n;

wire        z_nmi_n;     // /NMI to the Z80: /OBF as a level, plus the edge insurance below


`ifdef SH_Z80_T80
// The vendored T80 (as the GHDL-converted netlist verif/board/t80/T80s_ghdl.v),
// kept for the bench's cross-check only (make ... Z80=t80). On the DE10 this
// core lost sound-latch NMIs mid-race - the M6 findings tell the whole
// story - while tv80, below, never did; the same netlist is clean in
// simulation and in every timing corner, so the cause is unexplained and
// the core is simply not used on hardware.
T80s z80 (
    .RESET_n (z_rst_n),
    .CLK     (clk),
    .CEN     (ce_z80),
    .WAIT_n  (z_wait_n),
    .INT_n   (ym_irq_n),
    .NMI_n   (z_nmi_n),
    .BUSRQ_n (1'b1),
    .M1_n    (z_m1_n), .MREQ_n(z_mreq_n), .IORQ_n(z_iorq_n), .RD_n(z_rd_n), .WR_n(z_wr_n),
    .RFSH_n  (), .HALT_n(), .BUSAK_n(),
    .OUT0    (1'b0),
    .A       (z_addr), .DI(z_din), .DO(z_dout),
    .REG     (), .DIRSet(1'b0), .DIR(230'd0), .ISet_out(),  // save-state ports, unused
    .DBG     (z80_dbg)
);
wire _unused_ce8 = ce_z80x2;
`else
// tv80 (Verilog) on the 4 MHz clock enable: tv80_core has always had one,
// only its bus wrapper lacked it (verif/board/tv80/tv80s_cen.v). The
// board bench runs this same core, so the simulated and the synthesised
// sound board share their CPU bit for bit.
tv80s_cen z80 (
    .reset_n(z_rst_n), .clk(clk), .cen(ce_z80),
    .wait_n(z_wait_n), .int_n(ym_irq_n), .nmi_n(z_nmi_n), .busrq_n(1'b1),
    .m1_n(z_m1_n), .mreq_n(z_mreq_n), .iorq_n(z_iorq_n), .rd_n(z_rd_n), .wr_n(z_wr_n),
    .rfsh_n(), .halt_n(), .busak_n(),
    .A(z_addr), .di(z_din), .dout(z_dout), .dbg(z80_dbg)   // z80_dbg: state view for the bench's logs
);
wire _unused_ce8 = ce_z80x2;
`endif

wire mem_rd = ~z_mreq_n & ~z_rd_n;
wire mem_wr = ~z_mreq_n & ~z_wr_n;
wire io_rd  = ~z_iorq_n & ~z_rd_n & z_m1_n;
wire sel_rom = ~z_addr[15];                          // 0000-7FFF
wire sel_ram = (z_addr[15:12] == 4'hC);              // C000-C7FF (mirror 0800)
wire sel_ym  = (z_addr[15:12] == 4'hD);              // D000-D001 (mirror 0FFE)
wire sel_pcm = (z_addr[15:12] == 4'hE);              // E000-E0FF (mirror 0F00)

// NMI edge insurance. The 8255's /OBF drives /NMI as a level; the Z80 must
// latch its falling edge. On the DE10 the T80 was seen, three times out of
// three, with /NMI low, its NMI latch clear and the byte unread, while the
// same netlist never drops an edge in simulation (M6 findings). Whatever
// the physical cause, the protocol tolerates a late read (the 68000 waits
// 53 us between bytes) but not a lost one. So if /OBF has been low for
// 32 us - twice the Z80's worst measured latency - and the Z80 has not
// fetched its NMI vector since the byte arrived, /NMI is pulsed high for
// four clocks to hand the core a fresh edge. A Z80 that behaves never sees
// it (retrig_cnt counts, for the bench).
reg  [10:0] nmi_low_t;
reg         nmi_seen, retrig;
reg   [2:0] retrig_t;
reg   [4:0] retrig_cnt;
wire        nmi_vector = ~z_m1_n & mem_rd & (z_addr == 16'h0066);
always @(posedge clk) begin
    if (reset) begin nmi_low_t <= 11'd0; nmi_seen <= 1'b0; retrig <= 1'b0; retrig_t <= 3'd0; retrig_cnt <= 5'd0; end
    else begin
        if (!snd_nmi) begin nmi_low_t <= 11'd0; nmi_seen <= 1'b0; end          // /OBF high: nothing pending
        else begin
            if (nmi_vector) nmi_seen <= 1'b1;
            if (nmi_low_t != 11'd1611) nmi_low_t <= nmi_low_t + 11'd1;         // 32 us at 50.35 MHz
        end
        if (retrig) begin
            retrig_t <= retrig_t + 3'd1;
            if (retrig_t == 3'd3) begin retrig <= 1'b0; nmi_low_t <= 11'd0; end
        end
        else if (snd_nmi && !nmi_seen && nmi_low_t == 11'd1611) begin
            retrig <= 1'b1; retrig_t <= 3'd0;
            if (retrig_cnt != 5'd31) retrig_cnt <= retrig_cnt + 5'd1;
`ifdef SIMULATION
            $display("NMIRETRIG: /NMI re-issued after 32 us without a vector fetch (z80 pc %04x)", z_addr);
`endif
        end
    end
end
assign z_nmi_n = ~snd_nmi | retrig;
assign z80_fetch_ram = ~z_m1_n & mem_rd & z_addr[15];

// ---- ROM: the whole 32 KB window in BRAM, loaded from the stream. The
// PCB's Z80 has private zero-wait ROM; the SDRAM cache this replaces
// stalled the Z80 on in-game miss storms, and one stall longer than the
// main CPU's ~33 us per-byte latch pacing (it checks /OBF once, counts a
// drop at 20C460 and blindly overwrites) loses a latch byte: no new /OBF
// edge, no NMI, and the 8-slot NMI coroutine shifts by one for good -
// music dead, effects garbage, until the game next resets the Z80. The
// BRAM restores the hardware's timing and removes the whole stall class.
reg [15:0] zrom [0:16383];
always @(posedge clk) if (zbrm_wr) zrom[zbrm_addr[14:1]] <= zbrm_din;
`ifdef SIMULATION
initial if ($test$plusargs("z80rom")) $readmemh("z80rom.hex", zrom);
`endif
reg [15:0] rom_word;
always @(posedge clk) rom_word <= zrom[z_addr[14:1]];
assign z_wait_n = 1'b1;

// ---- work RAM 2 KB. The sim zero-fills it: the game tests bytes it
// never wrote (C01F gates the whole song-activation path), MAME zero-
// fills its RAM regions, and the FPGA M10K powers up zero; only the
// simulator's x-assign disagreed, which cost a day of sound debugging.
reg [7:0] ram [0:2047];
`ifdef SIMULATION
integer ri;
initial for (ri = 0; ri < 2048; ri = ri + 1) ram[ri] = 8'd0;
`endif
reg [7:0] ram_q;
always @(posedge clk) begin
    if (mem_wr && sel_ram) ram[z_addr[10:0]] <= z_dout;
    ram_q <= ram[z_addr[10:0]];
end

// ---- PCM
wire [7:0] pcm_q;
wire signed [15:0] pcm_l, pcm_r;
reg pcm_cs_d;
wire pcm_access = (mem_rd | mem_wr) && sel_pcm;
always @(posedge clk) pcm_cs_d <= pcm_access;
sh_segapcm_5218 #(.PCM_BASE(PCM_BASE)) pcm (
    .clk(clk), .reset(reset), .tick(pcm_tick), .bankmask(pcm_bankmask),
    .cs(pcm_access && !pcm_cs_d), .we(mem_wr), .addr(z_addr[7:0]), .din(z_dout), .dout(pcm_q),
    .rom_req(pcm_req), .rom_addr(pcm_addr), .rom_dout(pcm_dout), .rom_ack(pcm_ack),
    .out_l(pcm_l), .out_r(pcm_r), .tick_lost(pcm_tick_lost)
);

// ---- YM2203 (jt03), memory-mapped at D000/D001
wire ym_access = (mem_rd | mem_wr) && sel_ym;
reg  ym_cs_d;
always @(posedge clk) ym_cs_d <= ym_access;
wire [7:0] ym_dout;
wire signed [15:0] fm_snd;
wire [7:0] psg_a, psg_b, psg_c;
jt03 ym (
    .rst(~z_rst_n), .clk(clk), .cen(ce_fm),
    .din(z_dout), .addr(z_addr[0]),
    .cs_n(~(ym_access && !ym_cs_d)), .wr_n(z_wr_n),
    .dout(ym_dout), .irq_n(ym_irq_n),
    .IOA_in(8'hFF), .IOB_in(8'hFF), .IOA_out(), .IOB_out(), .IOA_oe(), .IOB_oe(),
    .psg_A(psg_a), .psg_B(psg_b), .psg_C(psg_c),
    .fm_snd(fm_snd), .psg_snd(), .snd(), .snd_sample(),
    .debug_view()
);

// ---- sound latch on port 0x40 (mirror 3F)
wire latch_cs = io_rd && (z_addr[7:6] == 2'b01);
reg latch_cs_d;
always @(posedge clk) latch_cs_d <= latch_cs;
assign snd_read = latch_cs && !latch_cs_d;

// ---- read mux
always @* begin
    z_din = 8'hFF;
    if (~z_iorq_n) begin
        if (z_addr[7:6] == 2'b01) z_din = snd_latch;
    end
    else if (sel_rom) z_din = z_addr[0] ? rom_word[15:8] : rom_word[7:0];
    else if (sel_ym)  z_din = ym_dout;
    else if (sel_pcm) z_din = pcm_q;
    else if (sel_ram) z_din = ram_q;
end

// ---- mix (MAME's routes): PCM 0.40, FM 0.15, SSG channels 0.05 each,
// the 8-bit SSG channels scaled by 128 toward 16 bits
wire        [9:0] ssg_sum = {2'd0, psg_a} + {2'd0, psg_b} + {2'd0, psg_c};
wire signed [23:0] ssg_part = 24'({ssg_sum, 7'd0}) * 24'(SSG_GAIN);
wire signed [23:0] mix_l = pcm_l * 24'(PCM_GAIN) + fm_snd * 24'(FM_GAIN) + ssg_part;
wire signed [23:0] mix_r = pcm_r * 24'(PCM_GAIN) + fm_snd * 24'(FM_GAIN) + ssg_part;
assign audio_l = mute_n ? mix_l[23:8] : 16'sd0;
assign audio_r = mute_n ? mix_r[23:8] : 16'sd0;
endmodule
