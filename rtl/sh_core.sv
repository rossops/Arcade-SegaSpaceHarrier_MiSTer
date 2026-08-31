//============================================================================
//  Sega Space Harrier / Hang-On — board top (M0 stub)
//  Real video timing (400 x 262 at clk_sys/8 = 6.2937 MHz) and a test
//  gradient; every board block arrives with its milestone (M1 CPUs and I/O,
//  M2 tilemaps, M3 road, M4 sprites and mixer, M5 sound). The port list is
//  the board's: five SDRAM clients (main, sub, Z80, PCM, sprites), the
//  descriptor, inputs, video, audio and the two CPU trace taps.
//============================================================================
import sh_pkg::*;

module sh_core (
    input             clk_sys,
    input             clk_ram,
    input             reset,
    input             pause,

    input board_desc_t board_desc,

    // SDRAM ports (sdram.sv p0..p7 subset; unused clients stay quiet)
    output            p0_req,   // main 68000 cache, 64-bit bursts
    output [24:3]     p0_addr,
    input  [63:0]     p0_dout,
    input             p0_ack,
    output            p1_req,   // sub 68000 cache
    output [24:3]     p1_addr,
    input  [63:0]     p1_dout,
    input             p1_ack,
    output            p2_req,   // sprite ROM line fetch, 128-bit bursts
    output [24:4]     p2_addr,
    input  [127:0]    p2_dout,
    input             p2_ack,
    output            p5_req,   // Z80 cache
    output [24:3]     p5_addr,
    input  [63:0]     p5_dout,
    input             p5_ack,
    output            p6_req,   // 315-5218 PCM byte reads
    output [24:1]     p6_addr,
    input  [15:0]     p6_dout,
    input             p6_ack,

    // BRAM ROM load path (tile, road, zoom, MCU, key), byte writes from the
    // loader; consumed from M2 on
    input             brm_wr,
    input      [26:0] brm_addr,   // stream offset (OFF_TILE..OFF_END)
    input      [15:0] brm_din,

    // inputs
    input      [15:0] p1_buttons,
    input       [7:0] stick_x,
    input       [7:0] stick_y,
    input       [7:0] throttle,
    input       [1:0] stick_mode,
    input       [1:0] ana_curve,
    input       [1:0] ana_range,
    input       [7:0] dsw_a,
    input       [7:0] dsw_b,
    input             service,
    input             test,
    input             coin1,
    input             coin2,

    // video out
    output      [7:0] r,
    output      [7:0] g,
    output      [7:0] b,
    output            ce_vid,
    output            hs,
    output            vs,
    output            hb,
    output            vb,

    // audio
    output signed [15:0] audio_l,
    output signed [15:0] audio_r,

    // executed-instruction taps for the board bench (see sh_m68k_bus)
    output     [23:1] trace_main_addr,
    output            trace_main_start,
    output      [2:0] trace_main_fc,
    output     [23:1] trace_sub_addr,
    output            trace_sub_start,
    output      [2:0] trace_sub_fc
);

// no SDRAM traffic and no audio until M1/M5
assign p0_req = 1'b0;  assign p0_addr = '0;
assign p1_req = 1'b0;  assign p1_addr = '0;
assign p2_req = 1'b0;  assign p2_addr = '0;
assign p5_req = 1'b0;  assign p5_addr = '0;
assign p6_req = 1'b0;  assign p6_addr = '0;
assign audio_l = '0;
assign audio_r = '0;
assign trace_main_addr = '0;  assign trace_main_start = 1'b0;  assign trace_main_fc = '0;
assign trace_sub_addr  = '0;  assign trace_sub_start  = 1'b0;  assign trace_sub_fc  = '0;

// ---- video timing ----------------------------------------------------------
wire       ce_pix, hblank, vblank, hsync, vsync;
wire [8:0] hcnt, vcnt;

sh_video_timing timing (
    .clk(clk_sys), .reset(reset),
    .ce_pix(ce_pix), .hcnt(hcnt), .vcnt(vcnt),
    .hblank(hblank), .vblank(vblank), .hsync(hsync), .vsync(vsync),
    .v0(), .line_start(), .vbl_irq(), .latch_pulse(),
    .hires(1'b0), .ce_out(), .ohcnt(), .oline(), .ohblank(), .ohsync()
);
assign ce_vid = ce_pix;
assign hb = hblank;
assign vb = vblank;
assign hs = hsync;
assign vs = vsync;

// M0 test pattern: a gradient the monitor and the bench can both see
assign r = {hcnt[7:0]} & {8{~hblank & ~vblank}};
assign g = 8'h00;
assign b = {vcnt[7:0]} & {8{~hblank & ~vblank}};

endmodule
