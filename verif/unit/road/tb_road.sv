`timescale 1ns/1ps
// Standalone road renderer test: load road RAM and road ROM from hex dumps,
// run the timing for one frame, and dump every displayed pixel's palette
// index and the line's PLYCONT to road.txt for the Python comparison.
// The display side prefetches one pixel (see sh_road / sh_tilemap_5012).
// +sharrier asserts the SHARRIER control-bit-9 semantics.
module tb_road;
reg clk = 0; always #10 clk = ~clk;
reg reset = 1;
wire ce_pix, hb, vb, hs, vs, v0, line_start, vbl_irq, latch_pulse;
wire [8:0] hcnt, vcnt;
sh_video_timing timing(.clk(clk), .reset(reset), .ce_pix(ce_pix), .hcnt(hcnt), .vcnt(vcnt),
    .hblank(hb), .vblank(vb), .hsync(hs), .vsync(vs), .v0(v0), .line_start(line_start),
    .vbl_irq(vbl_irq), .latch_pulse(latch_pulse));
wire [10:0] ram_addr; wire [15:0] ram_q;
wire [13:0] rom_addr; wire [7:0] p0, p1;
sh_dpram #(.AW(11)) roadram(.clk(clk), .a_addr(11'd0), .a_din(16'd0), .a_be(2'd0), .a_we(1'b0), .a_dout(),
    .b_clk(clk), .b_addr(ram_addr), .b_dout(ram_q));
sh_roadrom roadrom(.clk(clk), .wr(1'b0), .wr_addr(15'd0), .wr_data(16'd0), .rd_addr(rom_addr),
    .plane0(p0), .plane1(p1));
reg sharrier; initial sharrier = $test$plusargs("sharrier");
wire [10:0] road_pix; wire [1:0] road_ply;
sh_road dut(.clk(clk), .reset(reset), .sharrier(sharrier),
    .line_start(line_start), .vcnt(vcnt), .ce_pix(ce_pix), .hcnt(hcnt),
    .ram_addr(ram_addr), .ram_q(ram_q), .rom_addr(rom_addr), .rom_p0(p0), .rom_p1(p1),
    .road_pix(road_pix), .road_ply(road_ply));
integer fd, frames = 0;
reg vb_d = 0, ce_d = 0;
reg [8:0] h_d, v_d;
initial begin
    $readmemh("roadram.hex", roadram.mem);
    $readmemh("roadrom0.hex", roadrom.rom0);
    $readmemh("roadrom1.hex", roadrom.rom1);
    fd = $fopen("road.txt", "w");
    repeat (4) @(posedge clk); reset = 0;
end
wire [8:0] px = (h_d == 9'd399) ? 9'd0 : h_d + 9'd1;
wire [8:0] py = (h_d == 9'd399) ? ((v_d == 9'd261) ? 9'd0 : v_d + 9'd1) : v_d;
always @(posedge clk) begin
    ce_d <= ce_pix; h_d <= hcnt; v_d <= vcnt;
    vb_d <= vb;
    if (vb && !vb_d) begin
        frames = frames + 1;
        if (frames == 3) begin $fclose(fd); $finish; end
    end
    if (ce_d && frames == 2 && py < 9'd224 && px < 9'd320)
        $fwrite(fd, "%0d %0d %03x %0d\n", py, px, road_pix, road_ply);
end
endmodule
