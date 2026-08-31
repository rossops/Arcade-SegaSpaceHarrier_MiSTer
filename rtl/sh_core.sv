//============================================================================
//  Sega Space Harrier / Hang-On — board top
//  M1: the two 68000s (fx68k) with ROM caches on the hangon memory map,
//  every CPU-visible RAM, the shared sub/road RAM behind a hold-through-RMW
//  arbiter (with a third requester slot reserved for the i8751 bridge, M7),
//  both i8255 PPIs (port A of the main one is the sound latch, mode-1
//  strobed output, /OBF = Z80 NMI), the ADC0804 behind the PPI mux, the
//  vblank interrupt (held until acknowledge, MAME irq4_line_hold) and a
//  Z80 stand-in that consumes the latch. Video is still the M0 gradient,
//  gated by the display enable; tilemaps arrive in M2, road M3, sprites
//  and mixer M4, the real sound board M5.
//============================================================================
import sh_pkg::*;

module sh_core (
    input             clk_sys,      // 50.3496 MHz
    input             clk_ram,      // 100.6992 MHz
    input             reset,
    input             pause,

    input board_desc_t board_desc,

    // SDRAM read ports (sdram.sv): p0 main ROM, p1 sub ROM, p3 the main
    // CPU's window onto the sub ROM at C00000; p2 sprites (M4), p5 Z80 and
    // p6 PCM (M5)
    output            p0_req, output [24:3] p0_addr, input  [63:0] p0_dout, input p0_ack,
    output            p1_req, output [24:3] p1_addr, input  [63:0] p1_dout, input p1_ack,
    output            p2_req, output [24:4] p2_addr, input [127:0] p2_dout, input p2_ack,
    output            p3_req, output [24:3] p3_addr, input  [63:0] p3_dout, input p3_ack,
    output            p5_req, output [24:3] p5_addr, input  [63:0] p5_dout, input p5_ack,
    output            p6_req, output [24:1] p6_addr, input  [15:0] p6_dout, input p6_ack,

    // BRAM ROM load path (tile, road, zoom, MCU, key); consumed from M2 on
    input             brm_wr,
    input      [26:0] brm_addr,
    input      [15:0] brm_din,

    // inputs (active high; bit layout = the MRA J1 order, see the emu top)
    input      [15:0] p1_buttons,
    input signed [7:0] stick_x,
    input signed [7:0] stick_y,
    input       [7:0] throttle,
    input       [1:0] stick_mode,   // 0 analog, 1 d-pad, 2 both
    input       [1:0] ana_curve,
    input       [1:0] ana_range,
    input       [7:0] dsw_a, dsw_b,
    input             service, test,
    input             coin1, coin2,

    // video (320x224 inside the 400x262 grid)
    output      [7:0] r, g, b,
    output            ce_vid, hs, vs, hb, vb,

    output signed [15:0] audio_l, audio_r,

    // executed-instruction traces for the board bench (one per 68000)
    output     [23:1] trace_main_addr, output trace_main_start, output [2:0] trace_main_fc,
    output     [23:1] trace_sub_addr,  output trace_sub_start,  output [2:0] trace_sub_fc
);

// idle until their milestones
assign p2_req = 1'b0;  assign p2_addr = '0;
assign p5_req = 1'b0;  assign p5_addr = '0;
assign p6_req = 1'b0;  assign p6_addr = '0;
assign audio_l = '0;
assign audio_r = '0;

// ---------------------------------------------------------------- clocks
// Hang-On runs both 68000s at clk_sys/8 = 6.2937 MHz (exact). The other
// sets run them at 10 MHz, made by a phase accumulator emitting alternating
// fx68k phases at a 20 MHz average event rate (open question 5: the jitter
// is under half a clk_sys period). ADC clock 25.1748/4/6 = clk_sys/48.
reg  [2:0] ph8;
reg [15:0] acc10;
reg        ph10, en1_f, en2_f;
// 26032 / 65536 * 50.3496 MHz = 19.99994 MHz event rate
wire [16:0] acc10_sum = {1'b0, acc10} + 17'd26032;
always @(posedge clk_sys) begin
    en1_f <= 1'b0; en2_f <= 1'b0;
    if (reset) begin ph8 <= 3'd0; acc10 <= 16'd0; ph10 <= 1'b0; end
    else begin
        ph8   <= ph8 + 3'd1;
        acc10 <= acc10_sum[15:0];
        if (acc10_sum[16]) begin
            ph10 <= ~ph10;
            if (!pause) begin
                if (!ph10) en1_f <= 1'b1;
                else       en2_f <= 1'b1;
            end
        end
    end
end
wire en1_8 = !pause && (ph8 == 3'd0);
wire en2_8 = !pause && (ph8 == 3'd4);
wire cpu10m = board_desc.cpu10m;
wire enphi1 = cpu10m ? en1_f : en1_8;
wire enphi2 = cpu10m ? en2_f : en2_8;

reg [5:0] adc_div;
reg       ce_adc;
always @(posedge clk_sys) begin
    ce_adc <= 1'b0;
    if (reset) adc_div <= 6'd0;
    else begin
        adc_div <= (adc_div == 6'd47) ? 6'd0 : adc_div + 6'd1;
        ce_adc  <= !pause && (adc_div == 6'd47);
    end
end

// ---------------------------------------------------------------- timing
wire       ce_pix, hblank, vblank, hsync, vsync, line_start, vbl_irq, latch_pulse;
wire [8:0] hcnt, vcnt;

sh_video_timing timing (
    .clk(clk_sys), .reset(reset),
    .ce_pix(ce_pix), .hcnt(hcnt), .vcnt(vcnt),
    .hblank(hblank), .vblank(vblank), .hsync(hsync), .vsync(vsync),
    .v0(), .line_start(line_start), .vbl_irq(vbl_irq), .latch_pulse(latch_pulse),
    .hires(1'b0), .ce_out(), .ohcnt(), .oline(), .ohblank(), .ohsync()
);
assign ce_vid = ce_pix;
assign hb = hblank;  assign vb = vblank;
assign hs = hsync;   assign vs = vsync;

// ---------------------------------------------------------------- interrupts
// Main: IRQ4 raised entering vblank (line 224) and held until the CPU's
// interrupt acknowledge (MAME irq4_line_hold). On Space Harrier the i8751
// is the only IPL source instead (M7). Sub: level 4 is a plain level from
// PPI1 port A bit 6, active low, no acknowledge (MAME sub_control_adc_w).
reg  m_irq4, vbl_d;
wire m_iack;
always @(posedge clk_sys) begin
    vbl_d <= vbl_irq;
    if (cpu_reset) m_irq4 <= 1'b0;
    else begin
        if (vbl_irq && !vbl_d && !board_desc.has_mcu) m_irq4 <= 1'b1;
        if (m_iack && m_addr[3:1] == 3'd4) m_irq4 <= 1'b0;
    end
end
wire [2:0] ipl_m = m_irq4 ? 3'd4 : 3'd0;
wire [2:0] ipl_s = ~pa1_out[6] ? 3'd4 : 3'd0;

wire cpu_reset = reset;

// ================================================================ MAIN CPU
wire [23:1] m_addr;
wire        m_valid, m_start, m_rd, m_wr;
wire  [1:0] m_be;
wire [15:0] m_dout;
reg  [15:0] m_din;
reg         m_ack;
wire  [2:0] m_fc;
wire        m_as_n, s_as_n;
wire        m_reset_out;     // RESET instruction -> sub CPU reset

sh_m68k_bus main_cpu (
    .clk(clk_sys), .reset(cpu_reset), .enphi1(enphi1), .enphi2(enphi2),
    .ipl(ipl_m), .halt_n(1'b1),
    .bus_addr(m_addr), .bus_valid(m_valid), .bus_start(m_start),
    .bus_rd(m_rd), .bus_wr(m_wr), .bus_be(m_be),
    .bus_dout(m_dout), .bus_din(m_din), .bus_ack(m_ack),
    .reset_out(m_reset_out), .iack(m_iack), .fc(m_fc), .bus_as_n(m_as_n)
);
assign trace_main_addr = m_addr; assign trace_main_start = m_start; assign trace_main_fc = m_fc;

// main decode, hangon map (MAME hangon_map; unmapped reads FFFF). The
// sharrier map is a descriptor-selected second decode in M7.
wire [23:1] ma = m_addr;
wire m_sel_rom    = (ma[23:18] == 6'h00);          // 000000-03FFFF
wire m_sel_wram   = (ma[23:14] == 10'h083);        // 20C000-20FFFF work RAM
wire m_sel_tile   = (ma[23:14] == 10'h100);        // 400000-403FFF tile RAM
wire m_sel_text   = (ma[23:12] == 12'h410);        // 410000-410FFF text RAM
wire m_sel_spr    = (ma[23:11] == 13'h0C00);       // 600000-6007FF sprite RAM
wire m_sel_pal    = (ma[23:12] == 12'hA00);        // A00000-A00FFF palette RAM
wire m_sel_subrom = (ma[23:18] == 6'h30);          // C00000-C3FFFF the sub CPU's ROM
wire m_sel_road   = (ma[23:12] == 12'hC68);        // C68000-C68FFF road RAM (shared)
wire m_sel_subram = (ma[23:14] == 10'h31F);        // C7C000-C7FFFF sub RAM (shared)
// E00000-FFFFFF: PPI0 / inputs / PPI1 / ADC, low byte, mirror 1FCFD8
// (significant bits A13:12, A5, A2:1)
wire m_sel_iozone = (ma[23:21] == 3'b111);
wire m_sel_ppi0   = m_sel_iozone && (ma[13:12] == 2'b00);
wire m_sel_inputs = m_sel_iozone && (ma[13:12] == 2'b01);
wire m_sel_ppi1   = m_sel_iozone && (ma[13:12] == 2'b11) && !ma[5];
wire m_sel_adc    = m_sel_iozone && (ma[13:12] == 2'b11) &&  ma[5];
wire m_sel_shared = m_sel_road | m_sel_subram;

reg m_ram_rdy;
always @(posedge clk_sys) m_ram_rdy <= m_valid && !m_start && !m_ack ? 1'b1 : (m_valid ? m_ram_rdy : 1'b0);
wire m_cs = m_start;

// ---- main ROM cache (256 KB)
wire [15:0] m_rom_data; wire m_rom_ack;
wire        m_rom_req; wire [18:3] m_rom_addr;
sh_rom_cache #(.AW(18), .LINES(512)) main_cache (
    .clk(clk_sys), .reset(reset), .invalidate(reset),
    .cpu_req(m_valid && m_rd && m_sel_rom), .cpu_addr(ma[18:1]),
    .cpu_data(m_rom_data), .cpu_ack(m_rom_ack),
    .rom_req(m_rom_req), .rom_addr(m_rom_addr), .rom_data(p0_dout), .rom_ack(p0_ack)
);
assign p0_req  = m_rom_req;
assign p0_addr = SDR_MAIN_BASE[24:3] + {6'd0, m_rom_addr};

// ---- the main CPU's read window onto the sub ROM (C00000-C3FFFF)
wire [15:0] m_sub_data; wire m_sub_ack;
wire        m_sub_req; wire [18:3] m_sub_addr;
sh_rom_cache #(.AW(18), .LINES(256)) mainsub_cache (
    .clk(clk_sys), .reset(reset), .invalidate(reset),
    .cpu_req(m_valid && m_rd && m_sel_subrom), .cpu_addr(ma[18:1]),
    .cpu_data(m_sub_data), .cpu_ack(m_sub_ack),
    .rom_req(m_sub_req), .rom_addr(m_sub_addr), .rom_data(p3_dout), .rom_ack(p3_ack)
);
assign p3_req  = m_sub_req;
assign p3_addr = SDR_SUB_BASE[24:3] + {6'd0, m_sub_addr};

// ---- main work RAM (16 KB) and the video RAMs (port B goes to the
// renderers from M2 on)
wire [15:0] m_wram_q, tile_q, text_q, spr_q, pal_q;
sh_dpram #(.AW(13)) work_ram (.clk(clk_sys), .a_addr(ma[13:1]), .a_din(m_dout), .a_be(m_be),
    .a_we(m_valid && m_wr && m_sel_wram && m_start), .a_dout(m_wram_q),
    .b_clk(clk_sys), .b_addr(13'd0), .b_dout());
sh_dpram #(.AW(13)) tileram (.clk(clk_sys), .a_addr(ma[13:1]), .a_din(m_dout), .a_be(m_be),
    .a_we(m_valid && m_wr && m_sel_tile && m_start), .a_dout(tile_q),
    .b_clk(clk_sys), .b_addr(13'd0), .b_dout());
sh_dpram #(.AW(11)) textram (.clk(clk_sys), .a_addr(ma[11:1]), .a_din(m_dout), .a_be(m_be),
    .a_we(m_valid && m_wr && m_sel_text && m_start), .a_dout(text_q),
    .b_clk(clk_sys), .b_addr(11'd0), .b_dout());
sh_dpram #(.AW(10)) spriteram (.clk(clk_sys), .a_addr(ma[10:1]), .a_din(m_dout), .a_be(m_be),
    .a_we(m_valid && m_wr && m_sel_spr && m_start), .a_dout(spr_q),
    .b_clk(clk_sys), .b_addr(10'd0), .b_dout());
sh_dpram #(.AW(11)) paletteram (.clk(clk_sys), .a_addr(ma[11:1]), .a_din(m_dout), .a_be(m_be),
    .a_we(m_valid && m_wr && m_sel_pal && m_start), .a_dout(pal_q),
    .b_clk(clk_sys), .b_addr(11'd0), .b_dout());

// ---- PPI0 (E00000): port A = sound latch (mode 1 strobed output, /OBF is
// the Z80's NMI), port B = video/lamps, port C = handshake + tilemap
// control + mute
wire [7:0] ppi0_q, pb0_out, pc0_out, pa0_out;
wire       snd_obf_n, stub_ack_n;
sh_i8255 ppi0 (
    .clk(clk_sys), .reset(cpu_reset), .cs(m_cs && m_sel_ppi0 && m_be[0]), .we(m_wr),
    .addr(ma[2:1]), .din(m_dout[7:0]), .dout(ppi0_q),
    .in_a(8'hFF), .in_b(8'hFF), .in_c(8'hFF),
    .out_a(pa0_out), .out_b(pb0_out), .out_c(pc0_out),
    .acka_n(stub_ack_n), .obfa_n(snd_obf_n), .intra()
);
// port B: 7 flip (M2), 6 SHADE0 (M4), 5 Z80 /RESET, 4 display enable,
// 3:2 lamps, 1:0 coin counters
wire display_enable = pb0_out[4];
wire z80_run        = pb0_out[5];
// port C: 2:1 tilemap column/row scroll enables (M2), 0 mute (M5)

// ---- Z80 stand-in: consumes the sound latch so the mode-1 handshake
// completes (the real Z80's port-40 read arrives in M5). It waits ~2 us
// after /OBF falls, then pulses /ACK for four clocks.
reg [7:0] stub_wait;
reg [1:0] stub_ackw;
reg       stub_ack;
assign stub_ack_n = ~stub_ack;
always @(posedge clk_sys) begin
    if (cpu_reset || !z80_run) begin stub_wait <= 8'd0; stub_ack <= 1'b0; stub_ackw <= 2'd0; end
    else if (stub_ack) begin
        stub_ackw <= stub_ackw + 2'd1;
        if (stub_ackw == 2'd3) stub_ack <= 1'b0;
    end
    else if (!snd_obf_n) begin
        stub_wait <= stub_wait + 8'd1;
        if (stub_wait == 8'd100) begin stub_ack <= 1'b1; stub_ackw <= 2'd0; stub_wait <= 8'd0; end
    end
    else stub_wait <= 8'd0;
end

// ---- PPI1 (E03000): port A = sub CPU control and ADC select, port C in =
// ADC status (D6 = /INTR)
wire [7:0] ppi1_q, pa1_out;
wire       adc_done;
sh_i8255 ppi1 (
    .clk(clk_sys), .reset(cpu_reset), .cs(m_cs && m_sel_ppi1 && m_be[0]), .we(m_wr),
    .addr(ma[2:1]), .din(m_dout[7:0]), .dout(ppi1_q),
    .in_a(8'hFF), .in_b(8'hFF), .in_c({1'b0, ~adc_done, 6'd0}),
    .out_a(pa1_out), .out_b(), .out_c(),
    .acka_n(1'b1), .obfa_n(), .intra()
);
wire sub_res = pa1_out[5];   // 1 = sub CPU held in reset

// ---- inputs (E01000, four byte ports on A2:A1): hangon order SERVICE,
// COINAGE, DSW, unused; sharrier swaps COINAGE/DSW up one (M7). Active low.
wire [7:0] in_service = ~{2'b00, 1'b0, p1_buttons[6], service | p1_buttons[10],
                          test | p1_buttons[9], coin2, coin1 | p1_buttons[7]};
reg [7:0] inputs_q;
always @* begin
    case (ma[2:1])
        2'd0: inputs_q = in_service;
        2'd1: inputs_q = dsw_a;      // COINAGE = SW A
        2'd2: inputs_q = dsw_b;      // DSW = SW B
        2'd3: inputs_q = 8'hFF;
    endcase
end

// ---- ADC0804 (E03021, odd byte): one converter behind the 74HC4052 mux
// selected by PPI1 port A bits 3:2
wire [7:0] adc_q;
sh_adc0804 adc (
    .clk(clk_sys), .reset(cpu_reset), .ce_adc(ce_adc),
    .cs(m_cs && m_sel_adc && m_be[0]), .we(m_wr),
    .dout(adc_q), .intr(adc_done),
    .channel({1'b0, pa1_out[3:2]}), .adc_reverse(board_desc.adc_reverse),
    .ch0(adc_ch0), .ch1(adc_ch1), .ch2(adc_ch2), .ch3(adc_ch3),
    .ch4(8'h80), .ch5(8'h80), .ch6(8'h80), .ch7(8'h80)
);

// ---- analog channels per the descriptor's mode (docs/DESIGN.md Controls).
// Mode 0 hangon/shangon*: steering 0x20-0xE0 reversed on 0, gas on 1,
// brake on 2. Mode 1 sharrier: stick X/Y 0x20-0xE0 reversed on 0/1.
// Mode 2 enduror: gas 0, brake 1, bank (stick Y) 2, steering reversed 3.
// The reversals come through the descriptor's adc_reverse inside the ADC.
// The wheel slews toward the stick at 6 counts a frame (the Y Board's
// Power Drift finding: an instant thumbstick map steers like ice skates).
wire [2:0] am = board_desc.ana_mode;
wire signed [7:0] sx_s, sy_s, thr_s;
sh_ana_shape shape_x (.clk(clk_sys), .axis(stick_x), .curve(ana_curve), .range(ana_range), .out(sx_s));
sh_ana_shape shape_y (.clk(clk_sys), .axis(stick_y), .curve(ana_curve), .range(ana_range), .out(sy_s));
sh_ana_shape shape_t (.clk(clk_sys), .axis(throttle ^ 8'h80), .curve(ana_curve), .range(ana_range), .out(thr_s));
wire [7:0] throttle_s = thr_s ^ 8'h80;
wire use_analog = (stick_mode != 2'd1);
wire use_dpad   = (stick_mode != 2'd0);
wire signed [7:0] in_x = (use_dpad && p1_buttons[0]) ? 8'sd127 :
                         (use_dpad && p1_buttons[1]) ? -8'sd127 :
                         use_analog ? sx_s : 8'sd0;
wire signed [7:0] in_y = (use_dpad && p1_buttons[2]) ? 8'sd127 :
                         (use_dpad && p1_buttons[3]) ? -8'sd127 :
                         use_analog ? sy_s : 8'sd0;
reg signed [7:0] wheel;
reg        vbl_w_d;
wire signed [8:0] wheel_d = {in_x[7], in_x} - {wheel[7], wheel};
always @(posedge clk_sys) begin
    vbl_w_d <= vbl_irq;
    if (cpu_reset) wheel <= 8'sd0;
    else if (vbl_irq && !vbl_w_d) begin
        if (wheel_d > 9'sd6)       wheel <= wheel + 8'sd6;
        else if (wheel_d < -9'sd6) wheel <= wheel - 8'sd6;
        else                       wheel <= in_x;
    end
end
// three-quarter deflection = 0x20..0xE0 around 0x80
function automatic [7:0] tq(input signed [7:0] v);
    reg signed [7:0] q;
    begin q = v - (v >>> 2); tq = {~q[7], q[6:0]}; end
endfunction
wire [7:0] gas   = p1_buttons[4] ? 8'hFF : (throttle_s > 8'h80) ? {throttle_s[6:0], 1'b0} : 8'h00;
wire [7:0] brake = p1_buttons[5] ? 8'hFF : (throttle_s < 8'h80) ? {7'h7F - throttle_s[6:0], 1'b0} : 8'h00;
wire [7:0] adc_ch0 = (am == 3'd0) ? tq(wheel) : (am == 3'd1) ? tq(in_x) : gas;
wire [7:0] adc_ch1 = (am == 3'd0) ? gas       : (am == 3'd1) ? tq(in_y) : brake;
wire [7:0] adc_ch2 = (am == 3'd0) ? brake     : (am == 3'd2) ? {~in_y[7], in_y[6:0]} : 8'h80;
wire [7:0] adc_ch3 = (am == 3'd2) ? {~wheel[7], wheel[6:0]} : 8'h80;

// ================================================================ SUB CPU
wire [23:1] s_addr;
wire        s_valid, s_start, s_rd, s_wr;
wire  [1:0] s_be;
wire [15:0] s_dout;
reg  [15:0] s_din;
reg         s_ack;
wire  [2:0] s_fc;

sh_m68k_bus sub_cpu (
    .clk(clk_sys), .reset(cpu_reset | m_reset_out | sub_res), .enphi1(enphi1), .enphi2(enphi2),
    .ipl(ipl_s), .halt_n(1'b1),
    .bus_addr(s_addr), .bus_valid(s_valid), .bus_start(s_start),
    .bus_rd(s_rd), .bus_wr(s_wr), .bus_be(s_be),
    .bus_dout(s_dout), .bus_din(s_din), .bus_ack(s_ack),
    .reset_out(), .iack(), .fc(s_fc), .bus_as_n(s_as_n)
);
assign trace_sub_addr = s_addr; assign trace_sub_start = s_start; assign trace_sub_fc = s_fc;

// sub decode: 19-bit space (MAME global_mask 0x7ffff)
wire [18:1] sa = s_addr[18:1];
wire s_sel_rom    = !sa[18];                        // 000000-03FFFF
wire s_sel_road   = (sa[18:12] == 7'h68);           // 068000-068FFF road RAM
wire s_sel_subram = (sa[18:14] == 5'h1F);           // 07C000-07FFFF sub RAM
wire s_sel_shared = s_sel_road | s_sel_subram;

reg s_ram_rdy;
always @(posedge clk_sys) s_ram_rdy <= s_valid && !s_start && !s_ack ? 1'b1 : (s_valid ? s_ram_rdy : 1'b0);

wire [15:0] s_rom_data; wire s_rom_ack;
wire        s_rom_req; wire [18:3] s_rom_addr;
sh_rom_cache #(.AW(18), .LINES(512)) sub_cache (
    .clk(clk_sys), .reset(reset), .invalidate(reset),
    .cpu_req(s_valid && s_rd && s_sel_rom), .cpu_addr(sa[18:1]),
    .cpu_data(s_rom_data), .cpu_ack(s_rom_ack),
    .rom_req(s_rom_req), .rom_addr(s_rom_addr), .rom_data(p1_dout), .rom_ack(p1_ack)
);
assign p1_req  = s_rom_req;
assign p1_addr = SDR_SUB_BASE[24:3] + {6'd0, s_rom_addr};

// ================================================================ SHARED RAM
// Sub RAM (16 KB) and road RAM (4 KB) are one shared space seen by both
// CPUs (and the i8751 bridge from M7: requester slot 3 is wired and idle).
// One access per clock in priority order; a CPU that has read keeps the
// space until its next bus cycle starts, an RMW write is served first and
// an instruction fetch releases the hold, so tas and the two-cycle
// bclr/bset/addq on memory are atomic across CPUs (the Y Board's Power
// Drift findings; MAME's instructions are atomic and never see the race).
// A stalled holder is released by a timeout.
reg         m_shr_pend, s_shr_pend;
reg         m_shr_got, s_shr_got;
reg         m_shr_ack, s_shr_ack;
reg  [15:0] m_shr_q, s_shr_q;
wire        mcu_shr_pend = 1'b0;        // i8751 bridge (M7)
reg   [1:0] shr_hold;   // 0 free, 1 main, 2 sub, 3 mcu
reg   [7:0] shr_hold_t;
wire        hold_free  = (shr_hold == 2'd0);
wire        shr_pick_m = m_shr_pend && (hold_free || shr_hold == 2'd1);
wire        shr_pick_s = s_shr_pend && !shr_pick_m && (hold_free || shr_hold == 2'd2);
wire        shr_pick_u = mcu_shr_pend && !shr_pick_m && !shr_pick_s && (hold_free || shr_hold == 2'd3);
// address bit 13 of the sub-RAM word index does not exist in the road RAM;
// the region rides along with the pick
wire        shr_road = shr_pick_m ? m_sel_road : s_sel_road;
wire [12:0] shr_addr = shr_pick_m ? ma[13:1] : sa[13:1];
wire [15:0] shr_din  = shr_pick_m ? m_dout   : s_dout;
wire  [1:0] shr_be   = shr_pick_m ? m_be     : s_be;
wire        shr_we   = shr_pick_m ? m_wr     : (shr_pick_s & s_wr);
wire [15:0] subram_q, road_q;
sh_dpram #(.AW(13)) subram (.clk(clk_sys), .a_addr(shr_addr), .a_din(shr_din), .a_be(shr_be),
    .a_we(shr_we && !shr_road && (shr_pick_m | shr_pick_s | shr_pick_u)), .a_dout(subram_q),
    .b_clk(clk_sys), .b_addr(13'd0), .b_dout());
sh_dpram #(.AW(11)) roadram (.clk(clk_sys), .a_addr(shr_addr[10:0]), .a_din(shr_din), .a_be(shr_be),
    .a_we(shr_we && shr_road && (shr_pick_m | shr_pick_s | shr_pick_u)), .a_dout(road_q),
    .b_clk(clk_sys), .b_addr(11'd0), .b_dout());
reg shr_road_d;
wire [15:0] shr_q = shr_road_d ? road_q : subram_q;
always @(posedge clk_sys) begin
    if (reset) begin
        m_shr_pend <= 1'b0; s_shr_pend <= 1'b0;
        m_shr_got <= 1'b0; s_shr_got <= 1'b0;
        m_shr_ack <= 1'b0; s_shr_ack <= 1'b0;
        shr_hold <= 2'd0; shr_hold_t <= 8'd0; shr_road_d <= 1'b0;
    end
    else begin
        shr_road_d <= shr_road;
        shr_hold_t <= (shr_hold == 2'd0) ? 8'd0 : shr_hold_t + 8'd1;
        if (shr_pick_m && m_rd)      begin shr_hold <= 2'd1; shr_hold_t <= 8'd0; end
        else if (shr_pick_s && s_rd) begin shr_hold <= 2'd2; shr_hold_t <= 8'd0; end
        else if ((shr_hold == 2'd1 && ((m_start && !m_sel_shared) || (shr_pick_m && m_wr) || cpu_reset)) ||
                 (shr_hold == 2'd2 && ((s_start && !s_sel_shared) || (shr_pick_s && s_wr) || cpu_reset || m_reset_out || sub_res)) ||
                 (shr_hold != 2'd0 && shr_hold_t == 8'd255)) shr_hold <= 2'd0;
        if (m_start && m_sel_shared) m_shr_pend <= 1'b1; else if (shr_pick_m) m_shr_pend <= 1'b0;
        if (s_start && s_sel_shared) s_shr_pend <= 1'b1; else if (shr_pick_s) s_shr_pend <= 1'b0;
        m_shr_got <= shr_pick_m; s_shr_got <= shr_pick_s;
        if (!m_valid) m_shr_ack <= 1'b0; else if (m_shr_got) begin m_shr_q <= shr_q; m_shr_ack <= 1'b1; end
        if (!s_valid) s_shr_ack <= 1'b0; else if (s_shr_got) begin s_shr_q <= shr_q; s_shr_ack <= 1'b1; end
    end
end

// ================================================================ read muxes
// Writes into ROM space (main program ROM and the sub-ROM window) are
// acknowledged and dropped: real DTACK logic ignores R/W, MAME drops them
// silently, and a decode that only acks reads stalls the CPU (parents'
// hard-won rule). The bench logs them (ROMWR).
always @* begin
    m_din = 16'hFFFF;
    m_ack = 1'b0;
    if (m_sel_rom)         begin m_din = m_rom_data; m_ack = m_wr ? m_ram_rdy : m_rom_ack; end
    else if (m_sel_subrom) begin m_din = m_sub_data; m_ack = m_wr ? m_ram_rdy : m_sub_ack; end
    else if (m_sel_shared) begin m_din = m_shr_q;    m_ack = m_shr_ack; end
    else if (m_sel_wram)   begin m_din = m_wram_q;   m_ack = m_ram_rdy; end
    else if (m_sel_tile)   begin m_din = tile_q;     m_ack = m_ram_rdy; end
    else if (m_sel_text)   begin m_din = text_q;     m_ack = m_ram_rdy; end
    else if (m_sel_spr)    begin m_din = spr_q;      m_ack = m_ram_rdy; end
    else if (m_sel_pal)    begin m_din = pal_q;      m_ack = m_ram_rdy; end
    else if (m_sel_ppi0)   begin m_din = {8'hFF, ppi0_q};   m_ack = m_ram_rdy; end
    else if (m_sel_inputs) begin m_din = {8'hFF, inputs_q}; m_ack = m_ram_rdy; end
    else if (m_sel_ppi1)   begin m_din = {8'hFF, ppi1_q};   m_ack = m_ram_rdy; end
    else if (m_sel_adc)    begin m_din = {8'hFF, adc_q};    m_ack = m_ram_rdy; end
    else                   begin m_din = 16'hFFFF;   m_ack = m_ram_rdy; end
end

always @* begin
    s_din = 16'hFFFF;
    s_ack = 1'b0;
    if (s_sel_rom)         begin s_din = s_rom_data; s_ack = s_wr ? s_ram_rdy : s_rom_ack; end
    else if (s_sel_shared) begin s_din = s_shr_q;    s_ack = s_shr_ack; end
    else                   begin s_din = 16'hFFFF;   s_ack = s_ram_rdy; end
end

// ================================================================ video (M0 stub)
// Gradient gated by the display enable (PPI0 port B bit 4); the tilemap,
// road, sprite and mixer chain replaces this in M2-M4.
assign r = display_enable ? ({hcnt[7:0]} & {8{~hblank & ~vblank}}) : 8'd0;
assign g = 8'd0;
assign b = display_enable ? ({vcnt[7:0]} & {8{~hblank & ~vblank}}) : 8'd0;

endmodule
