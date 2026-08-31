`timescale 1ns/1ps
// Standalone sprite renderer test: load sprite RAM, the zoom PROM and the
// sprite ROM from hex dumps, run the timing for three frames (the first
// list copy happens at line 260), and dump every displayed pixel's sprite
// buffer value to sprites.txt for the Python comparison. A small stub
// serves the SDRAM p2 128-bit bursts from the sprite.hex image.
module tb_sprite;
reg clk = 0; always #10 clk = ~clk;
reg reset = 1;
wire ce_pix, hb, vb, hs, vs, v0, line_start, vbl_irq, latch_pulse;
wire [8:0] hcnt, vcnt;
sh_video_timing timing(.clk(clk), .reset(reset), .ce_pix(ce_pix), .hcnt(hcnt), .vcnt(vcnt),
    .hblank(hb), .vblank(vb), .hsync(hs), .vsync(vs), .v0(v0), .line_start(line_start),
    .vbl_irq(vbl_irq), .latch_pulse(latch_pulse));
wire [9:0] cram_addr; wire [15:0] cram_q;
wire [12:0] zoom_addr; wire [7:0] zoom_q;
sh_dpram #(.AW(10)) spriteram(.clk(clk), .a_addr(10'd0), .a_din(16'd0), .a_be(2'd0), .a_we(1'b0), .a_dout(),
    .b_clk(clk), .b_addr(cram_addr), .b_dout(cram_q));
sh_zoomrom zoomrom(.clk(clk), .wr(1'b0), .wr_addr(13'd0), .wr_data(16'd0), .rd_addr(zoom_addr), .q(zoom_q));

// p2 stub: 1 MB sprite region as 512K words, 128-bit reads, 6-clock
// latency. rom_addr is the absolute 128-bit unit (region base 0x0F0000
// bytes = unit 0xF000); word k of the burst is the low-first 16-bit lane.
reg [15:0] sprrom [0:524287];
wire        rom_req; wire [24:4] rom_addr;
reg [127:0] rom_dout; reg rom_ack;
reg         req_d;
reg   [2:0] lat;
wire [20:0] unit = rom_addr - 21'h0F000;
integer k;
initial lat = 0;
always @(posedge clk) begin
    req_d <= rom_req;
    rom_ack <= 1'b0;
    if (rom_req && !req_d) lat <= 3'd6;
    else if (lat != 3'd0) begin
        lat <= lat - 3'd1;
        if (lat == 3'd1) begin
            for (k = 0; k < 8; k = k + 1)
                rom_dout[16*k +: 16] <= sprrom[{unit[15:0], 3'b000} + k[2:0]];
            rom_ack <= 1'b1;
        end
    end
end

wire [11:0] spr_pix;
sh_sprite dut(.clk(clk), .reset(reset), .numbanks(8'd8),
    .line_start(line_start), .vcnt(vcnt), .ce_pix(ce_pix), .hcnt(hcnt),
    .cram_addr(cram_addr), .cram_q(cram_q),
    .zoom_addr(zoom_addr), .zoom_q(zoom_q),
    .rom_req(rom_req), .rom_addr(rom_addr), .rom_dout(rom_dout), .rom_ack(rom_ack),
    .spr_pix(spr_pix), .line_clocks(), .late_lines());
integer fd, frames = 0;
reg vb_d = 0, ce_d = 0;
reg [8:0] h_d, v_d;
initial begin
    $readmemh("spriteram.hex", spriteram.mem);
    $readmemh("zoomrom.hex", zoomrom.rom);
    $readmemh("sprite.hex", sprrom);
    fd = $fopen("sprites.txt", "w");
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
        $fwrite(fd, "%0d %0d %03x\n", py, px, spr_pix);
end
endmodule
