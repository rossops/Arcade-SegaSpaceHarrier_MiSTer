// Hang-On's latch protocol against the Z80 core, shaped like the board:
// a 68000-style writer (8 bytes a frame, 53 us apart, /OBF checked once,
// then overwritten), an 8255-style latch (/OBF low on write, high on the
// Z80's port read, /OBF drives /NMI as a level), a YM-style timer interrupt
// (level, held until the handler clears it; busy flag for 8 us after every
// register write) and a driver-shaped program: NMI coroutine slots that read
// the port, an IM1 handler that busy-waits with BIT 7,(IY+0) before every
// register write. Counts bytes the Z80 never read.
`timescale 1ns/1ps
module tb_z80_latch;
reg clk = 0; always #10 clk = ~clk;
reg rst_n = 0;
reg [15:0] acc = 0; reg cen = 0; reg ph = 0;
wire [16:0] acc_sum = {1'b0, acc} + 17'd10413;
always @(posedge clk) begin acc <= acc_sum[15:0]; cen <= 1'b0; if (acc_sum[16]) begin ph <= ~ph; if (ph) cen <= 1'b1; end end
wire [15:0] a; wire [7:0] dout; reg [7:0] din;
wire mreq_n, iorq_n, rd_n, wr_n, m1_n;
reg obf_n = 1; reg int_n = 1;
`ifdef SH_Z80_TV80
reg zclk = 0; always @(posedge clk) if (acc_sum[16]) zclk <= ~zclk;
tv80s z80 (.reset_n(rst_n), .clk(zclk), .wait_n(1'b1), .int_n(int_n), .nmi_n(obf_n), .busrq_n(1'b1),
    .m1_n(m1_n), .mreq_n(mreq_n), .iorq_n(iorq_n), .rd_n(rd_n), .wr_n(wr_n), .rfsh_n(), .halt_n(), .busak_n(),
    .A(a), .di(din), .dout(dout));
`else
T80s z80 (.RESET_n(rst_n), .CLK(clk), .CEN(cen), .WAIT_n(1'b1), .INT_n(int_n), .NMI_n(obf_n), .BUSRQ_n(1'b1),
    .M1_n(m1_n), .MREQ_n(mreq_n), .IORQ_n(iorq_n), .RD_n(rd_n), .WR_n(wr_n), .RFSH_n(), .HALT_n(), .BUSAK_n(),
    .OUT0(1'b0), .A(a), .DI(din), .DO(dout), .REG(), .DIRSet(1'b0), .DIR(230'd0), .ISet_out(), .DBG());
`endif
// ---- program (ROM 0000-7FFF, RAM C000-C7FF, YM at D000/D001, latch port 40)
reg [7:0] rom [0:32767];
integer i, p;
task emit(input [7:0] b); begin rom[p] = b; p = p + 1; end endtask
initial begin
    for (i = 0; i < 32768; i = i + 1) rom[i] = 8'h00;
    // 0000: DI; IM 1; LD SP,C800; LD HL,0069; EXX; LD IY,D000; JP 0100
    p = 0; emit(8'hF3); emit(8'hED); emit(8'h56); emit(8'h31); emit(8'h00); emit(8'hC8);
    emit(8'h21); emit(8'h69); emit(8'h00); emit(8'hD9); emit(8'hFD); emit(8'h21); emit(8'h00); emit(8'hD0);
    emit(8'hC3); emit(8'h00); emit(8'h01);
    // 0038: INT handler: PUSH AF/BC/DE/HL; CALL 09C6; LD (IY+0),26; LD (IY+1),F2 (clears INT);
    //       CALL 09C6; LD (IY+0),28; LD (IY+1),xx x6 (busy writes); POPs; EI; RET
    p = 16'h38; emit(8'hF5); emit(8'hC5); emit(8'hD5); emit(8'hE5);
    emit(8'hCD); emit(8'hC6); emit(8'h09);
    emit(8'hFD); emit(8'h36); emit(8'h00); emit(8'h26);
    emit(8'hFD); emit(8'h36); emit(8'h01); emit(8'hF2);
    emit(8'hC3); emit(8'h00); emit(8'h02);                 // JP 0200 (handler body)
    // 0066: NMI: EXX; EX AF,AF'; JP (HL)   slots at 0069, 0075, 0081, ... (8 slots, 12 bytes each)
    p = 16'h66; emit(8'hD9); emit(8'h08); emit(8'hE9);
    for (i = 0; i < 8; i = i + 1) begin
        // slot: LD HL,next; IN A,(40); LD (C2C6+i),A; EXX; EX AF,AF'; RETN
        emit(8'h21); emit((i == 7) ? 8'h69 : 8'h69 + 12 * (i + 1)); emit(8'h00);
        emit(8'hDB); emit(8'h40); emit(8'h32); emit(8'hC6 + i); emit(8'hC2);
        emit(8'hD9); emit(8'h08); emit(8'hED); emit(8'h45);
    end
    // 0100: main loop: EI; loop: LD HL,C2D6; INC (HL); ADD HL,HL x5; AND A; JP loop
    p = 16'h100; emit(8'hFB); emit(8'h21); emit(8'hD6); emit(8'hC2); emit(8'h34);
    emit(8'h29); emit(8'h29); emit(8'h29); emit(8'h29); emit(8'h29); emit(8'hA7); emit(8'hC3); emit(8'h01); emit(8'h01);
    // 0200: handler body: 12 x (CALL 09C6; LD (IY+0),reg; CALL 09C6; LD (IY+1),val) then LD IX,C040; BIT 7,(IX+0)...; POPs; EI; RET
    p = 16'h200;
    for (i = 0; i < 12; i = i + 1) begin
        emit(8'hCD); emit(8'hC6); emit(8'h09); emit(8'hFD); emit(8'h36); emit(8'h00); emit(8'h30 + i);
        emit(8'hCD); emit(8'hC6); emit(8'h09); emit(8'hFD); emit(8'h36); emit(8'h01); emit(8'h10 + i);
    end
    emit(8'hDD); emit(8'h21); emit(8'h40); emit(8'hC0);                       // LD IX,C040
    for (i = 0; i < 14; i = i + 1) begin emit(8'hDD); emit(8'hCB); emit(8'h00); emit(8'h7E); emit(8'h11); emit(8'h20); emit(8'h00); emit(8'hDD); emit(8'h19); end // BIT 7,(IX); LD DE,20; ADD IX,DE
    emit(8'hE1); emit(8'hD1); emit(8'hC1); emit(8'hF1); emit(8'hFB); emit(8'hC9);   // POP HL,DE,BC,AF; EI; RET
    // 09C6: BIT 7,(IY+0); JR NZ,09C6; RET
    p = 16'h9C6; emit(8'hFD); emit(8'hCB); emit(8'h00); emit(8'h7E); emit(8'h20); emit(8'hFA); emit(8'hC9);
end
reg [7:0] ram [0:2047];
// ---- YM-like device: busy for 8 us after any write; INT level cleared by a write to reg 0x26 data (addr 1 after 0x26 select)
reg [7:0] ym_reg = 0; integer busy_until = 0;
reg ym_wr_d = 0; wire ym_wr = !mreq_n && !wr_n && a[15:12] == 4'hD;
always @(posedge clk) begin
    ym_wr_d <= ym_wr;
    if (ym_wr && !ym_wr_d) begin
        busy_until = $time + 8000;
        if (!a[0]) ym_reg <= dout;
        else if (ym_reg == 8'h26) int_n <= 1'b1;     // timer reload clears the flag
    end
end
wire ym_busy = ($time < busy_until);
// timer: assert INT every 1.344 ms (level, held until cleared)
initial forever begin #1_344_000 int_n = 1'b0; end
// ---- latch / PPI: /OBF low on 68000 write, high on Z80 port read
reg [7:0] latch = 0;
reg iord_d = 0; wire iord = !iorq_n && !rd_n && m1_n && a[7:6] == 2'b01;
integer writes = 0, reads = 0, overwrites = 0, lost_frames = 0, frame = 0;
always @(posedge clk) begin
    iord_d <= iord;
    if (iord && !iord_d) begin reads = reads + 1; obf_n <= 1'b1; end
end
// 68000 writer: every 16.7 ms a burst of 8 bytes, 53.44 us apart; check once, overwrite
task write_byte(input [7:0] b); begin
    @(posedge clk);
    if (!obf_n) begin overwrites = overwrites + 1; $display("OVERWRITE at %0d us frame %0d (byte %0d): z80 pc=%04x", $time/1000, frame, b[2:0], a); end
    latch <= b; obf_n <= 1'b0; writes = writes + 1;
end endtask
initial begin
    #500 rst_n = 1;
    #2_000_000;
    forever begin
        for (i = 0; i < 8; i = i + 1) begin write_byte(i == 0 ? 8'h80 : 8'h10 + i[7:0]); #53_440; end
        frame = frame + 1;
        #(16_690_000 - 8 * 53_440);
    end
end
// ---- memory map
always @* begin
    din = 8'hFF;
    if (!mreq_n && !rd_n) begin
        if (!a[15]) din = rom[a[14:0]];
        else if (a[15:12] == 4'hD) din = {ym_busy, 7'd0};
        else din = ram[a[10:0]];
    end
    else if (!iorq_n && !rd_n && m1_n) din = latch;
end
always @(posedge clk) if (!mreq_n && !wr_n && a[15:12] == 4'hC) ram[a[10:0]] <= dout;
integer seconds; initial if (!$value$plusargs("seconds=%d", seconds)) seconds = 10;
initial begin
    repeat (seconds) #1_000_000_000;
    $display("RESULT %0d s: frames %0d writes %0d reads %0d overwrites %0d", seconds, frame, writes, reads, overwrites);
    $finish;
end
endmodule
