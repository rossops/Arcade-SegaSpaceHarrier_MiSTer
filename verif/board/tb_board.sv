//============================================================================
//  Board simulation top (Verilator). Clocks come from the C++ driver.
//  Writes one PPM per frame, 48 kHz audio and (from M1) the executed-PC
//  traces of the two 68000s. The Y Board bench's chip watches (+watch_a,
//  +trace_vid, +dumpframe RAM dumps, ROMWR/PORTE logs) reached into core
//  internals and come back with the blocks they watch, per milestone; its
//  +dumpframe comment block is the worked example for the dump timing.
//============================================================================
`timescale 1ns/1ps
import sh_pkg::*;

module tb_board (
    input clk_sys,
    input clk_ram,
    input reset,
    input [31:0] max_frames,
    output reg [31:0] frame
);

board_desc_t desc;
integer pa;
reg [7:0] dsw_a, dsw_b;
initial begin dsw_a = 8'hFF; dsw_b = 8'hFE; if ($value$plusargs("dswa=%h", pa)) dsw_a = pa[7:0]; if ($value$plusargs("dswb=%h", pa)) dsw_b = pa[7:0]; end
// descriptor: hangon unless plusargs say otherwise (tools/romsets.py has the values)
initial begin
    desc = '0;
    desc.game_id = 8'd0; desc.spr_banks = 8'd8; desc.adc_reverse = 8'h01;
    desc.sound_board = 2'd0; desc.ana_mode = 3'd0;
    if ($value$plusargs("game_id=%d", pa))     desc.game_id = pa[7:0];
    if ($value$plusargs("sharrier=%d", pa))    desc.sharrier_vid = pa[0];
    if ($value$plusargs("cpu10m=%d", pa))      desc.cpu10m = pa[0];
    if ($value$plusargs("mcu=%d", pa))         desc.has_mcu = pa[0];
    if ($value$plusargs("fd1089b=%d", pa))     desc.fd1089b = pa[0];
    if ($value$plusargs("ops_split=%d", pa))   desc.ops_split = pa[0];
    if ($value$plusargs("sound_board=%d", pa)) desc.sound_board = pa[1:0];
    if ($value$plusargs("spr_banks=%d", pa))   desc.spr_banks = pa[7:0];
    if ($value$plusargs("adc_reverse=%h", pa)) desc.adc_reverse = pa[7:0];
    if ($value$plusargs("ana_mode=%d", pa))    desc.ana_mode = pa[2:0];
end

wire p0_req, p1_req, p2_req, p5_req, p6_req;
wire p0_ack, p1_ack, p2_ack, p5_ack, p6_ack, wr_ack, sdr_ready;
wire [24:3] p0_addr, p1_addr, p5_addr;
wire [24:4] p2_addr;
wire [24:1] p6_addr;
wire [63:0] p0_dout, p1_dout, p5_dout;
wire [127:0] p2_dout;
wire [15:0] p6_dout;

sdram_model sdram (
    .clk(clk_ram), .init(reset), .ready(sdr_ready),
    .wr_req(1'b0), .wr_addr(24'd0), .wr_din(16'd0), .wr_be(2'd0), .wr_ack(wr_ack),
    .p0_req(p0_req), .p0_addr(p0_addr), .p0_dout(p0_dout), .p0_ack(p0_ack),
    .p1_req(p1_req), .p1_addr(p1_addr), .p1_dout(p1_dout), .p1_ack(p1_ack),
    .p2_req(p2_req), .p2_addr(p2_addr), .p2_dout(p2_dout), .p2_ack(p2_ack),
    .p3_req(1'b0), .p3_addr(22'd0), .p3_dout(), .p3_ack(), .p3_urgent(1'b0),
    .p4_req(1'b0), .p4_addr(21'd0), .p4_dout(), .p4_ack(), .p4_urgent(1'b0),
    .p5_req(p5_req), .p5_addr(p5_addr), .p5_dout(p5_dout), .p5_ack(p5_ack),
    .p6_req(p6_req), .p6_addr(p6_addr), .p6_dout(p6_dout), .p6_ack(p6_ack),
    .p7_req(1'b0), .p7_addr(21'd0), .p7_dout(), .p7_ack()
);

wire [7:0] r, g, b;
wire ce_pix, hs, vs, hb, vb;
wire signed [15:0] al, ar;
wire [23:1] tm_addr, ts_addr; wire tm_start, ts_start; wire [2:0] tm_fc, ts_fc;

// BRAM ROM regions come from hex files in the bench (M2 on); no loader here
sh_core core (
    .clk_sys(clk_sys), .clk_ram(clk_ram), .reset(reset), .pause(1'b0), .board_desc(desc),
    .p0_req(p0_req), .p0_addr(p0_addr), .p0_dout(p0_dout), .p0_ack(p0_ack),
    .p1_req(p1_req), .p1_addr(p1_addr), .p1_dout(p1_dout), .p1_ack(p1_ack),
    .p2_req(p2_req), .p2_addr(p2_addr), .p2_dout(p2_dout), .p2_ack(p2_ack),
    .p5_req(p5_req), .p5_addr(p5_addr), .p5_dout(p5_dout), .p5_ack(p5_ack),
    .p6_req(p6_req), .p6_addr(p6_addr), .p6_dout(p6_dout), .p6_ack(p6_ack),
    .brm_wr(1'b0), .brm_addr(27'd0), .brm_din(16'd0),
    .p1_buttons({5'd0, 1'b0, test_sw, 1'b0, coin1, p1_start, 6'd0} | hold_now),
    .stick_x(8'sd0), .stick_y(8'sd0), .throttle(8'h80),
    .stick_mode(2'd0), .ana_curve(2'd0), .ana_range(2'd0),
    .dsw_a(dsw_a), .dsw_b(dsw_b), .service(1'b0), .test(test_sw), .coin1(coin1), .coin2(1'b0),
    .r(r), .g(g), .b(b), .ce_vid(ce_pix), .hs(hs), .vs(vs), .hb(hb), .vb(vb),
    .audio_l(al), .audio_r(ar),
    .trace_main_addr(tm_addr), .trace_main_start(tm_start), .trace_main_fc(tm_fc),
    .trace_sub_addr(ts_addr), .trace_sub_start(ts_start), .trace_sub_fc(ts_fc)
);

// ---- traces (program-space word fetches; the executed-PC taps that follow
// fx68k's prefetch queue return with the CPUs in M1)
integer fm, fs, fppm;
initial begin
    fm = $fopen("trace_main_rtl.txt", "w");
    fs = $fopen("trace_sub_rtl.txt", "w");
    frame = 0;
end
always @(posedge clk_sys) begin
    if (!reset) begin
        if (tm_start && tm_fc[1]) $fwrite(fm, "%06x\n", {tm_addr, 1'b0});
        if (ts_start && ts_fc[1]) $fwrite(fs, "%06x\n", {ts_addr, 1'b0});
    end
end

// ---- +hold=<hex mask> +hold_from=N: hold P1 buttons from frame N
// (MRA J1 order: 4 gas 5 brake 6 start 7 coin 8 pause 9 test 10 service)
integer hold_mask = 0, hold_from = -1;
initial begin
    if (!$value$plusargs("hold=%h", hold_mask)) hold_mask = 0;
    if (!$value$plusargs("hold_from=%d", hold_from)) hold_from = -1;
end
wire [15:0] hold_now = (hold_from >= 0 && frame >= hold_from) ? hold_mask[15:0] : 16'd0;

// ---- +test_from=N: hold the test switch (service mode) from frame N on
integer test_from = -1;
initial begin if (!$value$plusargs("test_from=%d", test_from)) test_from = -1; end
wire test_sw = (test_from >= 0) && (frame >= test_from);
// ---- +coin=N: press Coin 1 for four frames from frame N (matches tools/mame_coin.lua)
integer coin_frame = -1;
initial begin if (!$value$plusargs("coin=%d", coin_frame)) coin_frame = -1; end
wire coin1 = (coin_frame >= 0) && (frame >= coin_frame) && (frame < coin_frame + 4);
// ---- +start=N (+start2..start5): press P1 Start for four frames from frame N
integer start_frame = -1, start2_frame = -1, start3_frame = -1, start4_frame = -1, start5_frame = -1;
initial begin
    if (!$value$plusargs("start=%d", start_frame))   start_frame = -1;
    if (!$value$plusargs("start2=%d", start2_frame)) start2_frame = -1;
    if (!$value$plusargs("start3=%d", start3_frame)) start3_frame = -1;
    if (!$value$plusargs("start4=%d", start4_frame)) start4_frame = -1;
    if (!$value$plusargs("start5=%d", start5_frame)) start5_frame = -1;
end
function automatic pressed(input integer at);
    pressed = (at >= 0) && (frame >= at) && (frame < at + 4);
endfunction
wire p1_start = pressed(start_frame) || pressed(start2_frame) || pressed(start3_frame) || pressed(start4_frame) || pressed(start5_frame);

// ---- audio: 48 kHz stereo, raw little-endian 16-bit (audio.raw)
integer faud;
reg [15:0] aud_acc;      // 48000/50.3496e6 -> 16-bit phase acc: 65536*0.000953 = 62.5
reg aud_ovf;
initial faud = $fopen("audio.raw", "wb");
always @(posedge clk_sys) begin
    if (!reset) begin
        {aud_ovf, aud_acc} <= aud_acc + 16'd62;
        if (aud_ovf) $fwrite(faud, "%c%c%c%c", al[7:0], al[15:8], ar[7:0], ar[15:8]);
    end
end

// ---- frame dump: one PPM per frame (320x224). ppm_open is assigned
// blocking: the file opens on the same clock pixel (0,0) arrives (vblank
// falls as ce_pix delivers it), and the stub's zero-latency video showed
// the nonblocking version losing that pixel.
reg vb_d;
reg ppm_open;
string fname;
always @(posedge clk_sys) begin
    vb_d <= vb;
    if (vb && !vb_d) begin
        if (ppm_open) begin $fclose(fppm); ppm_open = 0; end
        frame <= frame + 1;
        if (frame + 1 == max_frames) $finish;
    end
    if (!vb && vb_d) begin
        $sformat(fname, "frame_%04d.ppm", frame);
        fppm = $fopen(fname, "wb");
        $fwrite(fppm, "P6\n320 224\n255\n");
        ppm_open = 1;
    end
    if (ce_pix && !hb && !vb && ppm_open) $fwrite(fppm, "%c%c%c", r, g, b);
end
endmodule
