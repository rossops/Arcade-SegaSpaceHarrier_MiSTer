`timescale 1ns/1ps
// Standalone renderer test: load tile/text RAM and tile ROM from hex dumps,
// run the timing for one frame, and dump every displayed pixel's layer
// values (fg, bg, text line-buffer words) to layers.txt for the Python
// comparison. The display side prefetches one pixel (see sh_tilemap_5012),
// so the registered outputs at the clock after ce_pix belong to pixel
// hcnt+1 (pixel 0 arrives at the previous line's hcnt 399).
// +rowscroll / +colscroll assert the external enables (PPI port C bits).
module tb_tilemap;
reg clk = 0; always #10 clk = ~clk;
reg reset = 1;
wire ce_pix, hb, vb, hs, vs, v0, line_start, vbl_irq, latch_pulse;
wire [8:0] hcnt, vcnt;
sh_video_timing timing(.clk(clk), .reset(reset), .ce_pix(ce_pix), .hcnt(hcnt), .vcnt(vcnt),
    .hblank(hb), .vblank(vb), .hsync(hs), .vsync(vs), .v0(v0), .line_start(line_start),
    .vbl_irq(vbl_irq), .latch_pulse(latch_pulse));
wire [12:0] tile_addr; wire [15:0] tile_q; wire [10:0] text_addr; wire [15:0] text_q;
wire [14:0] rom_addr; wire [7:0] p0, p1, p2;
sh_dpram #(.AW(13)) tileram(.clk(clk), .a_addr(13'd0), .a_din(16'd0), .a_be(2'd0), .a_we(1'b0), .a_dout(),
    .b_clk(clk), .b_addr(tile_addr), .b_dout(tile_q));
sh_dpram #(.AW(11)) textram(.clk(clk), .a_addr(11'd0), .a_din(16'd0), .a_be(2'd0), .a_we(1'b0), .a_dout(),
    .b_clk(clk), .b_addr(text_addr), .b_dout(text_q));
sh_tilerom tilerom(.clk(clk), .wr(1'b0), .wr_addr(17'd0), .wr_data(16'd0), .rd_addr(rom_addr),
    .plane0(p0), .plane1(p1), .plane2(p2));
reg rowscroll_en, colscroll_en;
initial begin
    rowscroll_en = $test$plusargs("rowscroll");
    colscroll_en = $test$plusargs("colscroll");
end
wire [10:0] fg, bg; wire [6:0] tx;
sh_tilemap_5012 dut(.clk(clk), .reset(reset), .line_start(line_start), .vcnt(vcnt),
    .ce_pix(ce_pix), .hcnt(hcnt), .rowscroll_en(rowscroll_en), .colscroll_en(colscroll_en),
    .tile_addr(tile_addr), .tile_q(tile_q), .text_addr(text_addr), .text_q(text_q),
    .rom_addr(rom_addr), .rom_p0(p0), .rom_p1(p1), .rom_p2(p2), .fg_pix(fg), .bg_pix(bg), .tx_pix(tx));
integer fd, frames = 0;
reg vb_d = 0, ce_d = 0;
reg [8:0] h_d, v_d;
initial begin
    $readmemh("tileram.hex", tileram.mem);
    $readmemh("textram.hex", textram.mem);
    $readmemh("tilerom0.hex", tilerom.rom0);
    $readmemh("tilerom1.hex", tilerom.rom1);
    $readmemh("tilerom2.hex", tilerom.rom2);
    fd = $fopen("layers.txt", "w");
    repeat (4) @(posedge clk); reset = 0;
end
// +regdump: print the renderer's captured registers at each fg pixel-pass start
reg regdump; initial regdump = $test$plusargs("regdump");
reg [3:0] st_d;
always @(posedge clk) begin
    st_d <= dut.st;
    if (regdump && frames == 2 && dut.st == 3 && st_d != 3 && dut.ry < 3)
        $display("REGS ry=%0d layer=%0d pages_raw=%04x xscroll=%03x yscroll=%02x row=%03x",
                 dut.ry, dut.layer, dut.pages_raw, dut.xscroll, dut.yscroll, dut.rowword);
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
        $fwrite(fd, "%0d %0d %03x %03x %02x\n", py, px, fg, bg, tx);
end
endmodule
