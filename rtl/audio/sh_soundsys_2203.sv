//============================================================================
//  The YM2203 sound board (hangon, sharrier, enduror1): Z80 (T80s) at
//  4 MHz, YM2203 (jt03) at 4 MHz memory-mapped at D000, 315-5218 PCM at
//  E000 ticking at 8 MHz/128 = 62.5 kHz, ROM 0000-7FFF, RAM C000-C7FF
//  (mirror 0800). The only port is 0x40 (mirror 3F): the sound latch read,
//  which answers the main PPI's mode-1 handshake (/ACK empties /OBF, the
//  Z80's NMI). INT comes from the YM2203's timers.
//  Mix, from MAME's segahang routes with the ymfm rotation understood
//  (outputs 0-2 = SSG A/B/C, 3 = FM): SSG 0.05 each, FM 0.15, PCM 0.40,
//  as 1/256 gain parameters. The 8-bit SSG channels are scaled by 128
//  into the 16-bit sum. Simulation builds use tv80 behind SH_Z80_TV80.
//============================================================================
import sh_pkg::*;

module sh_soundsys_2203 #(
    parameter [24:0] ROM_BASE = SDR_Z80_BASE,
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

    // SDRAM
    output            zrom_req,  output [24:3] zrom_addr, input [63:0] zrom_dout, input zrom_ack,
    output            pcm_req,   output [24:1] pcm_addr,  input [15:0] pcm_dout,  input pcm_ack,

    output signed [15:0] audio_l,
    output signed [15:0] audio_r
);

wire [15:0] z_addr;
wire  [7:0] z_dout;
reg   [7:0] z_din;
wire        z_mreq_n, z_iorq_n, z_rd_n, z_wr_n, z_m1_n;
wire        ym_irq_n;
wire        z_wait_n;
wire        z_rst_n = ~reset & z80_reset_n;

`ifdef SH_Z80_TV80
// tv80 has no clock enable: derive a 4 MHz clock from the 8 MHz enable
reg zclk;
always @(posedge clk) if (reset) zclk <= 1'b0; else if (ce_z80x2) zclk <= ~zclk;
tv80s z80 (
    .reset_n(z_rst_n), .clk(zclk),
    .wait_n(z_wait_n), .int_n(ym_irq_n), .nmi_n(~snd_nmi), .busrq_n(1'b1),
    .m1_n(z_m1_n), .mreq_n(z_mreq_n), .iorq_n(z_iorq_n), .rd_n(z_rd_n), .wr_n(z_wr_n),
    .rfsh_n(), .halt_n(), .busak_n(),
    .A(z_addr), .di(z_din), .dout(z_dout)
);
`else
T80s z80 (
    .RESET_n (z_rst_n),
    .CLK     (clk),
    .CEN     (ce_z80),
    .WAIT_n  (z_wait_n),
    .INT_n   (ym_irq_n),
    .NMI_n   (~snd_nmi),
    .BUSRQ_n (1'b1),
    .M1_n    (z_m1_n), .MREQ_n(z_mreq_n), .IORQ_n(z_iorq_n), .RD_n(z_rd_n), .WR_n(z_wr_n),
    .RFSH_n  (), .HALT_n(), .BUSAK_n(),
    .OUT0    (1'b0),
    .A       (z_addr), .DI(z_din), .DO(z_dout)
);
`endif

wire mem_rd = ~z_mreq_n & ~z_rd_n;
wire mem_wr = ~z_mreq_n & ~z_wr_n;
wire io_rd  = ~z_iorq_n & ~z_rd_n & z_m1_n;
wire sel_rom = ~z_addr[15];                          // 0000-7FFF
wire sel_ram = (z_addr[15:12] == 4'hC);              // C000-C7FF (mirror 0800)
wire sel_ym  = (z_addr[15:12] == 4'hD);              // D000-D001 (mirror 0FFE)
wire sel_pcm = (z_addr[15:12] == 4'hE);              // E000-E0FF (mirror 0F00)

// ---- ROM: 1 KB cache over SDRAM p5 (4-word bursts); the Z80 waits on a miss
wire [15:0] rom_word;
wire        rom_hit;
wire [14:3] zc_addr;
sh_rom_cache #(.AW(14), .LINES(128)) zcache (
    .clk(clk), .reset(reset), .invalidate(reset),
    .cpu_req(mem_rd && sel_rom), .cpu_addr(z_addr[14:1]),
    .cpu_data(rom_word), .cpu_ack(rom_hit),
    .rom_req(zrom_req), .rom_addr(zc_addr), .rom_data(zrom_dout), .rom_ack(zrom_ack)
);
assign zrom_addr = ROM_BASE[24:3] + {10'd0, zc_addr};
assign z_wait_n  = !(mem_rd && sel_rom && !rom_hit);

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
    .out_l(pcm_l), .out_r(pcm_r)
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
