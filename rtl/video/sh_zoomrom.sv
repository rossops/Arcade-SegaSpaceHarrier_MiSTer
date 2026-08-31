//============================================================================
//  Sprite zoom PROM (8 KB, epr-6844) in BRAM, filled by the ROM loader's
//  brm stream port. The renderer reads one byte per sprite row:
//  address = ((vzoom & 0x38) << 5) + row index; bit (vzoom & 7) set means
//  the row address advances by pitch a second time (row skip).
//============================================================================
module sh_zoomrom (
    input             clk,
    input             wr,
    input      [12:0] wr_addr,      // byte address 0..0x1FFF (even)
    input      [15:0] wr_data,
    input      [12:0] rd_addr,
    output reg  [7:0] q
);
reg [7:0] rom [0:8191];
`ifdef SIMULATION
initial begin
    if ($test$plusargs("zoomrom")) $readmemh("zoomrom.hex", rom);
end
`endif
reg        hi_pend;
reg [12:0] hi_addr;
reg  [7:0] hi_data;
wire        do_wr  = wr | hi_pend;
wire [12:0] w_addr = wr ? wr_addr : hi_addr;
wire  [7:0] w_data = wr ? wr_data[7:0] : hi_data;
always @(posedge clk) begin
    if (wr) begin hi_pend <= 1'b1; hi_addr <= wr_addr | 13'd1; hi_data <= wr_data[15:8]; end
    else hi_pend <= 1'b0;
    if (do_wr) rom[w_addr] <= w_data;
    q <= rom[rd_addr];
end
endmodule
