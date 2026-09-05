//============================================================================
//  Space Harrier's i8751 (315-5163A) and its bridge onto the main 68000 bus.
//
//  The MCU is jotego's jt8051 (rtl/cpu/jt8051, GPL-3) on the board's 8 MHz
//  enable (twelve pulses per machine cycle), with its 4 KB internal ROM in
//  BRAM from the stream's MCU slot and its 128 bytes of internal RAM here,
//  both with the enable-registered read the core expects (jtframe's own
//  wrapper is the model). INT0 is the screen's vblank.
//
//  The contract (docs/notes/i8751_315-5163a.md, from the dumped code):
//    - MOVX external data space is a window onto the main bus. Port 1 bits
//      6,5,4,3 land on A20,A18,A17,A16 (A19 always 0); the 16-bit MOVX
//      address is the offset with A0 inverted (byte lanes swapped). One
//      byte per access, anywhere the 68000 can reach: it checksums the
//      main ROM at boot, lives in work RAM, block-writes tile RAM, the
//      palette, sub RAM and the I/O windows.
//    - Port 1 bits 2:0, inverted, are the 68000's IPL. The program drives
//      level 4 once per vblank and nothing else; the level is latched here
//      and cleared by the 68000's interrupt acknowledge, not by the MCU
//      releasing it (MAME: HOLD_LINE).
//    - The MCU paces its bus accesses with settle delays and reads every
//      location twice, so bus latency is nothing to it.
//
//  Timing: the core samples the returned byte four enabled edges after it
//  raises x_acc (the MOVX microcode), which a main-bus access through a
//  halted 68000 cannot promise. So the enable is withheld from the moment
//  a MOVX is seen until the bus has answered, the byte is held here, and
//  the core then runs its fixed sequence against a frozen clock.
//============================================================================
module sh_mcu (
    input             clk,
    input             reset,
    input             ce_8m,        // the MCU's oscillator enable (8 MHz)
    input             vblank,       // INT0 (edge-triggered by the program)

    // internal ROM from the loader: 16-bit stream words, byte 0 in the low half
    input             rom_wr,
    input      [11:0] rom_addr,     // byte address
    input      [15:0] rom_din,

    // main-bus master: one byte per request, held until ack
    output reg        bus_req,
    output reg [23:0] bus_addr,     // byte address on the 68000 bus
    output reg        bus_wr,
    output reg  [7:0] bus_dout,
    input       [7:0] bus_din,
    input             bus_ack,

    output      [2:0] ipl           // level the MCU drives (0 = none), a pulse per write
);

// ---- the core, with jtframe's one-clock registering of its bus outputs
wire [15:0] x_addr_c, rom_a_c;
wire  [7:0] x_dout_c, p1_o, p2_o;
wire        x_wr_c, x_acc_c;
reg  [15:0] x_addr, rom_a;
reg   [7:0] x_dout;
reg         x_wr, x_acc;
always @(posedge clk) begin
    x_addr <= x_addr_c; x_wr <= x_wr_c; x_dout <= x_dout_c; x_acc <= x_acc_c; rom_a <= rom_a_c;
end

// ---- enable: withheld while a bus access is in flight
reg  busy;
wire cen = ce_8m & ~busy;

// ---- internal ROM (4 KB) and RAM (128 B), enable-registered reads
reg [15:0] rom [0:2047];
always @(posedge clk) if (rom_wr) rom[rom_addr[11:1]] <= rom_din;
`ifdef SIMULATION
initial if ($test$plusargs("mcurom")) $readmemh("mcurom.hex", rom);
`endif
reg [15:0] rom_w;
reg        rom_lo;
always @(posedge clk) if (cen) begin rom_w <= rom[rom_a[11:1]]; rom_lo <= rom_a[0]; end
wire [7:0] rom_data = rom_lo ? rom_w[15:8] : rom_w[7:0];

reg  [7:0] iram [0:127];
wire [6:0] ram_addr; wire [7:0] ram_dout; wire ram_we;
reg  [7:0] ram_q;
always @(posedge clk) if (cen) begin
    ram_q <= iram[ram_addr];
    if (ram_we) iram[ram_addr] <= ram_dout;
end
`ifdef SIMULATION
integer ri; initial for (ri = 0; ri < 128; ri = ri + 1) iram[ri] = 8'd0;
`endif

// ---- the bridge: a MOVX becomes one byte cycle on the main bus
reg [7:0] x_din;
reg       acc_d;
always @(posedge clk) begin
    acc_d <= x_acc;
    if (reset) begin
        busy <= 1'b0; bus_req <= 1'b0; bus_wr <= 1'b0; bus_addr <= 24'd0; bus_dout <= 8'd0; x_din <= 8'hFF;
    end
    else begin
        if (x_acc && !acc_d && !busy) begin
            // window {P1.6, P1.5, P1.4, P1.3} -> {A20, A18, A17, A16}, A19 low,
            // the MOVX address with A0 inverted
            busy     <= 1'b1;
            bus_req  <= 1'b1;
            bus_addr <= {3'b000, p1_o[6], 1'b0, p1_o[5], p1_o[4], p1_o[3], x_addr[15:1], ~x_addr[0]};
            bus_wr   <= x_wr;
            bus_dout <= x_dout;
        end
        else if (busy && bus_ack) begin
            busy    <= 1'b0;
            bus_req <= 1'b0;
            if (!bus_wr) x_din <= bus_din;
        end
    end
end

// ---- IPL: P1 bits 2:0 inverted; the core latches it until acknowledge
assign ipl = ~p1_o[2:0];

jt8051 mcu (
    .rst(reset), .clk(clk), .cen(cen),
    .int0n(~vblank), .int1n(1'b1),
    .p0_i(8'hFF), .p1_i(8'hFF), .p2_i(8'hFF), .p3_i(8'hFF),
    .p0_o(), .p1_o(p1_o), .p2_o(p2_o), .p3_o(),
    .rom_data(rom_data), .rom_addr(rom_a_c),
    .ram_din(ram_q), .ram_dout(ram_dout), .ram_addr(ram_addr), .ram_we(ram_we),
    .x_din(x_din), .x_dout(x_dout_c), .x_addr(x_addr_c), .x_wr(x_wr_c), .x_acc(x_acc_c)
);
wire _unused_mcu = &{1'b0, p2_o};
endmodule
