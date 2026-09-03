// Does the Z80 take a held NMI while spinning in Hang-On's YM2203 busy-wait
// (0x09C6: BIT 7,(IY+0) / JR NZ)? The board caught the T80s in that loop
// executing for 3.5 ms with /NMI low and a latch byte lost. Same core, same
// clock enable as the FPGA (4 MHz from a 50 MHz clock); the "device" at
// 0x4000 answers 0x80 (busy) for a programmable time.
`timescale 1ns/1ps
module tb_z80_nmi;
reg clk = 0; always #10 clk = ~clk;
reg rst_n = 0;
// 4 MHz enable: every 12/13 clocks like the core's accumulator
reg [15:0] acc = 0; reg cen = 0; reg ph = 0;
wire [16:0] acc_sum = {1'b0, acc} + 17'd10413;
always @(posedge clk) begin
    acc <= acc_sum[15:0]; cen <= 1'b0;
    if (acc_sum[16]) begin ph <= ~ph; if (ph) cen <= 1'b1; end
end
wire [15:0] a; wire [7:0] dout; reg [7:0] din;
wire mreq_n, iorq_n, rd_n, wr_n, m1_n;
reg nmi_n = 1;
integer busy_until_ns;            // +busy=<ns>: how long 0x4000 reads busy after reset
integer nmi_at_ns;                // +nmi_at=<ns>: when /NMI falls
initial if (!$value$plusargs("busy=%d", busy_until_ns)) busy_until_ns = 1_000_000_000;
initial if (!$value$plusargs("nmi_at=%d", nmi_at_ns)) nmi_at_ns = 200_000;
`ifdef SH_Z80_TV80
reg zclk = 0; reg ph8 = 0;
always @(posedge clk) if (acc_sum[16]) zclk <= ~zclk;
tv80s z80 (.reset_n(rst_n), .clk(zclk), .wait_n(1'b1), .int_n(1'b1), .nmi_n(nmi_n), .busrq_n(1'b1),
    .m1_n(m1_n), .mreq_n(mreq_n), .iorq_n(iorq_n), .rd_n(rd_n), .wr_n(wr_n), .rfsh_n(), .halt_n(), .busak_n(),
    .A(a), .di(din), .dout(dout));
`else
T80s z80 (.RESET_n(rst_n), .CLK(clk), .CEN(cen), .WAIT_n(1'b1), .INT_n(1'b1), .NMI_n(nmi_n), .BUSRQ_n(1'b1),
    .M1_n(m1_n), .MREQ_n(mreq_n), .IORQ_n(iorq_n), .RD_n(rd_n), .WR_n(wr_n), .RFSH_n(), .HALT_n(), .BUSAK_n(),
    .OUT0(1'b0), .A(a), .DI(din), .DO(dout), .REG(), .DIRSet(1'b0), .DIR(230'd0), .ISet_out());
`endif
// program
reg [7:0] rom [0:255];
integer i;
initial begin
    for (i = 0; i < 256; i = i + 1) rom[i] = 8'h00;
    // 0000: LD IY,0x4000 ; LD SP,0x7F00 ; loop: BIT 7,(IY+0) ; JR NZ,loop ; JP loop2
    rom[8'h00] = 8'hFD; rom[8'h01] = 8'h21; rom[8'h02] = 8'h00; rom[8'h03] = 8'h40;
    rom[8'h04] = 8'h31; rom[8'h05] = 8'h00; rom[8'h06] = 8'hFF;   // SP in the test RAM
    rom[8'h07] = 8'hFD; rom[8'h08] = 8'hCB; rom[8'h09] = 8'h00; rom[8'h0A] = 8'h7E;   // BIT 7,(IY+0)
    rom[8'h0B] = 8'h20; rom[8'h0C] = 8'hFA;                                           // JR NZ,-6
    rom[8'h0D] = 8'hC3; rom[8'h0E] = 8'h0D; rom[8'h0F] = 8'h00;                       // JP $ (busy cleared: park here)
    // 0066: IN A,(40h) ; RETN
    rom[8'h66] = 8'hDB; rom[8'h67] = 8'h40; rom[8'h68] = 8'hED; rom[8'h69] = 8'h45;
end
reg [7:0] ram [0:255];
always @* begin
    din = 8'hFF;
    if (!mreq_n && !rd_n) begin
        if (a[15:14] == 2'b00) din = rom[a[7:0]];
        else if (a[15:14] == 2'b01) din = ($time < busy_until_ns) ? 8'h80 : 8'h00;   // the "YM status"
        else din = ram[a[7:0]];
    end
    else if (!iorq_n && !rd_n) din = 8'h55;      // the latch
end
always @(posedge clk) if (!mreq_n && !wr_n && a[15]) ram[a[7:0]] <= dout;
// observe
reg m1_d = 0; integer fetches = 0, nmi_fetches = 0, port_reads = 0, loop_fetches = 0, trace = 0; reg iord_d = 0;
always @(posedge clk) begin
    m1_d <= !m1_n && !mreq_n;
    if (!m1_n && !mreq_n && !m1_d) begin
        fetches = fetches + 1;
        if (a == 16'h0066) nmi_fetches = nmi_fetches + 1;
        if (a == 16'h0007) loop_fetches = loop_fetches + 1;

    end
    iord_d <= !iorq_n && !rd_n;
    if (!iorq_n && !rd_n && !iord_d) port_reads = port_reads + 1;
end
integer t_nmi, t_taken = -1;
always @(posedge clk) if (nmi_fetches == 1 && t_taken < 0) t_taken = $time;
initial begin
    #500 rst_n = 1;
    #(nmi_at_ns) nmi_n = 0;                 // /NMI falls and stays low (a byte pending)
    t_nmi = $time;
    #300_000;
    $display("RESULT nmi_at=%0d: taken=%0d latency=%0d ns loops=%0d handler_entries=%0d port_reads=%0d",
             nmi_at_ns, nmi_fetches, t_taken < 0 ? -1 : t_taken - t_nmi, loop_fetches, nmi_fetches, port_reads);
    $finish;
end
endmodule
