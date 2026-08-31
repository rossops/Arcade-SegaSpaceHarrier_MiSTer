//============================================================================
//  i8255 PPI (MAME i8255.cpp is the behavioural reference).
//  What this board uses, and what is implemented:
//   - mode 0 input and output on all three ports (read of an output port
//     returns its latch; a write to an input port only updates the latch);
//   - mode 1 STROBED OUTPUT on group A: the main PPI's port A is the sound
//     latch, /OBFa on PC7 is the Z80's NMI (active low), the Z80's latch
//     read drives /ACKa, INTEa is set through BSR of PC6, INTRa on PC3.
//     A port C read in that mode returns the status bits in place of
//     PC7/PC6/PC3. Mode 2 and strobed input are not on this board and fall
//     back to mode 0 (the bench logs a MODE line if a game ever asks).
//  Register select is A2:A1 (word addresses on the 68000, low byte lane).
//  Reset (and any control-word write): all ports mode 0 inputs, latches 0,
//  which matches MAME driving its output callbacks with the tri value (0)
//  until the game programs the chip.
//============================================================================
module sh_i8255 (
    input             clk,
    input             reset,
    input             cs,          // one-clock strobe
    input             we,
    input       [1:0] addr,        // A2:A1
    input       [7:0] din,
    output reg  [7:0] dout,

    input       [7:0] in_a, in_b, in_c,
    output      [7:0] out_a, out_b, out_c,

    input             acka_n,      // /ACK for group A mode-1 output (tie 1 if unused)
    output            obfa_n,      // /OBF (also on out_c[7] in mode 1)
    output            intra        // INTR A (also on out_c[3] in mode 1)
);

reg [7:0] latch_a, latch_b, latch_c;
reg       mode1_a;                 // group A strobed output
reg       dir_a, dir_b, dir_cl, dir_cu;   // 1 = input
reg       obf_n, inte, intr;
reg       acka_d;

assign obfa_n = obf_n;
assign intra  = intr;
assign out_a  = latch_a;
assign out_b  = latch_b;
// pin view of port C: handshake bits override in mode 1 (PC6 is the /ACK
// input pin then; its latch bit is INTE and is not driven out)
assign out_c  = mode1_a ? {obf_n, 1'b1, latch_c[5:4], intr, latch_c[2:0]} : latch_c;

// read view
wire [7:0] rd_c_pins = {dir_cu ? in_c[7:4] : latch_c[7:4], dir_cl ? in_c[3:0] : latch_c[3:0]};
wire [7:0] rd_c = mode1_a ? {obf_n, inte, rd_c_pins[5:4], intr, rd_c_pins[2:0]} : rd_c_pins;

always @* begin
    case (addr)
        2'd0: dout = dir_a ? in_a : latch_a;
        2'd1: dout = dir_b ? in_b : latch_b;
        2'd2: dout = rd_c;
        2'd3: dout = 8'hFF;    // control register reads FF on the 8255A
    endcase
end

always @(posedge clk) begin
    acka_d <= acka_n;
    if (reset) begin
        latch_a <= 8'd0; latch_b <= 8'd0; latch_c <= 8'd0;
        mode1_a <= 1'b0; dir_a <= 1'b1; dir_b <= 1'b1; dir_cl <= 1'b1; dir_cu <= 1'b1;
        obf_n <= 1'b1; inte <= 1'b0; intr <= 1'b0; acka_d <= 1'b1;
    end
    else begin
        // /ACK handshake (group A mode-1 output): ACK low empties the
        // buffer (/OBF back high); on ACK's rising edge INTR asserts if
        // enabled, telling the CPU the latch is free again
        if (mode1_a && !acka_n) obf_n <= 1'b1;
        if (mode1_a && acka_n && !acka_d && inte) intr <= 1'b1;

        if (cs && we) begin
            case (addr)
                2'd0: begin
                    latch_a <= din;
                    if (mode1_a) begin obf_n <= 1'b0; intr <= 1'b0; end
                end
                2'd1: latch_b <= din;
                2'd2: latch_c <= din;
                2'd3: begin
                    if (din[7]) begin
                        // mode set: group A mode from bits 6:5, direction
                        // bits 4 (A), 3 (C upper), 1 (B), 0 (C lower);
                        // output latches clear (MAME does the same)
                        mode1_a <= (din[6:5] == 2'b01) && !din[4];
                        dir_a   <= din[4];
                        dir_cu  <= din[3];
                        dir_b   <= din[1];
                        dir_cl  <= din[0];
                        latch_a <= 8'd0; latch_b <= 8'd0; latch_c <= 8'd0;
                        obf_n   <= 1'b1; inte <= 1'b0; intr <= 1'b0;
                    end
                    else begin
                        // bit set/reset on port C; in mode 1 PC6's flip-flop
                        // is INTE
                        if (mode1_a && din[3:1] == 3'd6) inte <= din[0];
                        else latch_c[din[3:1]] <= din[0];
                    end
                end
            endcase
        end
    end
end
endmodule
