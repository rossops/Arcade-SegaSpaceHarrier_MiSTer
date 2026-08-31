//============================================================================
//  Road ROM (2 x 16 KB, one bitplane per half of the 32 KB ROM) in BRAM,
//  filled by the ROM loader's brm stream port. A read returns the two
//  plane bytes of one 8-pixel group: address = {line[7:0], group[5:0]},
//  plane 1 at byte offset +0x4000. Pixel p of a group is bit 7-p.
//============================================================================
module sh_roadrom (
    input             clk,
    // loader: one strobe per 16-bit stream word at OFF_ROAD-relative offset
    input             wr,
    input      [14:0] wr_addr,      // byte address 0..0x7FFF (even)
    input      [15:0] wr_data,
    // renderer
    input      [13:0] rd_addr,      // {line, group}
    output reg  [7:0] plane0, plane1
);
reg [7:0] rom0 [0:16383];
reg [7:0] rom1 [0:16383];
`ifdef SIMULATION
initial begin
    if ($test$plusargs("roadrom")) begin
        $readmemh("roadrom0.hex", rom0);
        $readmemh("roadrom1.hex", rom1);
    end
end
`endif
reg        hi_pend;
reg [14:0] hi_addr;
reg  [7:0] hi_data;
wire        do_wr  = wr | hi_pend;
wire [14:0] w_addr = wr ? wr_addr : hi_addr;
wire  [7:0] w_data = wr ? wr_data[7:0] : hi_data;
always @(posedge clk) begin
    if (wr) begin hi_pend <= 1'b1; hi_addr <= wr_addr | 15'd1; hi_data <= wr_data[15:8]; end
    else hi_pend <= 1'b0;
    if (do_wr) begin
        if (!w_addr[14]) rom0[w_addr[13:0]] <= w_data;
        else             rom1[w_addr[13:0]] <= w_data;
    end
    plane0 <= rom0[rd_addr];
    plane1 <= rom1[rd_addr];
end
endmodule
