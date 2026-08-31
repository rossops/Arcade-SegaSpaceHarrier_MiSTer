//============================================================================
//  Tile ROM (3 x 32 KB, one bitplane per ROM) held in BRAM and filled by the
//  ROM loader's brm stream port (16-bit words; the two bytes are written on
//  consecutive clocks). A read returns the three plane bytes of one tile
//  row: address = {code[11:0], row[2:0]} -> plane p byte at p*0x8000 + addr.
//  Plane 2 (third ROM, epr-6843) is pen bit 2 (MAME gfx_8x8x3_planar:
//  RGN_FRAC(2,3) is the MSB plane). Pixel x of a row is bit 7-x of each byte.
//============================================================================
module sh_tilerom (
    input             clk,
    // loader: one strobe per 16-bit stream word at OFF_TILE-relative offset
    input             wr,
    input      [16:0] wr_addr,      // byte address 0..0x17FFF (even)
    input      [15:0] wr_data,
    // renderer
    input      [14:0] rd_addr,      // {code, row}
    output reg  [7:0] plane0, plane1, plane2
);
reg [7:0] rom0 [0:32767];
reg [7:0] rom1 [0:32767];
reg [7:0] rom2 [0:32767];
`ifdef SIMULATION
initial begin
    if ($test$plusargs("tilerom")) begin
        $readmemh("tilerom0.hex", rom0);
        $readmemh("tilerom1.hex", rom1);
        $readmemh("tilerom2.hex", rom2);
    end
end
`endif
reg        hi_pend;
reg [16:0] hi_addr;
reg  [7:0] hi_data;
wire       do_wr   = wr | hi_pend;
wire [16:0] w_addr = wr ? wr_addr : hi_addr;
wire  [7:0] w_data = wr ? wr_data[7:0] : hi_data;
always @(posedge clk) begin
    // ioctl words arrive many clocks apart; the odd byte is written on the
    // following clock
    if (wr) begin hi_pend <= 1'b1; hi_addr <= wr_addr | 17'd1; hi_data <= wr_data[15:8]; end
    else hi_pend <= 1'b0;
    if (do_wr) begin
        case (w_addr[16:15])
            2'd0: rom0[w_addr[14:0]] <= w_data;
            2'd1: rom1[w_addr[14:0]] <= w_data;
            default: rom2[w_addr[14:0]] <= w_data;
        endcase
    end
    plane0 <= rom0[rd_addr];
    plane1 <= rom1[rd_addr];
    plane2 <= rom2[rd_addr];
end
endmodule
