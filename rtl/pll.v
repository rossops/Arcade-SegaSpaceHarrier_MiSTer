`timescale 1ns/1ps
//============================================================================
//  Sega Space Harrier / Hang-On for MiSTer — clock PLL
//  50 MHz reference -> outclk0 100.6992 MHz (clk_ram), outclk1 50.3496 MHz
//  (clk_sys, twice the PCB's 25.1748 MHz master so the pixel /8, the Hang-On
//  CPU /8 and the ADC /48 enables are exact), outclk2 100.6992 MHz at 180
//  degrees (SDRAM_CLK). The 10 MHz CPUs and the 8/4 MHz sound section run on
//  clk_sys through fractional (accumulator) enables. The ratio 100.6992/50 is
//  not an integer-PLL M/(N*C), so the fractional VCO multiplier is on.
//  Under SIMULATION a behavioural model replaces the Altera IP.
//============================================================================
module pll (
    input  refclk_clk,
    input  reset_reset,
    output outclk0_clk,   // 100.6992 MHz
    output outclk1_clk,   // 50.3496 MHz
    output outclk2_clk,   // 100.6992 MHz, 180 deg
    output locked_export
);
`ifdef SIMULATION
reg c0 = 1'b0, c1 = 1'b0;
always #4.965 c0 = ~c0;
always #9.93  c1 = ~c1;
assign outclk0_clk = c0;
assign outclk1_clk = c1;
assign outclk2_clk = ~c0;
assign locked_export = 1'b1;
`else
// Same hierarchy as a Qsys-generated PLL (pll -> pll_inst -> altera_pll_i):
// sys/sys_top.sdc and derive_pll_clocks match clocks by that path.
pll_pll_inst pll_inst (
    .refclk   (refclk_clk),
    .rst      (reset_reset),
    .outclk_0 (outclk0_clk),
    .outclk_1 (outclk1_clk),
    .outclk_2 (outclk2_clk),
    .locked   (locked_export)
);
`endif
endmodule

`ifndef SIMULATION
module pll_pll_inst (
    input  wire refclk,
    input  wire rst,
    output wire outclk_0,
    output wire outclk_1,
    output wire outclk_2,
    output wire locked
);
altera_pll #(
    .fractional_vco_multiplier("true"),
    .reference_clock_frequency("50.0 MHz"),
    .operation_mode("direct"),
    .number_of_clocks(3),
    .output_clock_frequency0("100.699200 MHz"), .phase_shift0("0 ps"),    .duty_cycle0(50),
    .output_clock_frequency1("50.349600 MHz"),  .phase_shift1("0 ps"),    .duty_cycle1(50),
    .output_clock_frequency2("100.699200 MHz"), .phase_shift2("4965 ps"), .duty_cycle2(50),
    .output_clock_frequency3("0 MHz"),  .phase_shift3("0 ps"),  .duty_cycle3(50),
    .output_clock_frequency4("0 MHz"),  .phase_shift4("0 ps"),  .duty_cycle4(50),
    .output_clock_frequency5("0 MHz"),  .phase_shift5("0 ps"),  .duty_cycle5(50),
    .output_clock_frequency6("0 MHz"),  .phase_shift6("0 ps"),  .duty_cycle6(50),
    .output_clock_frequency7("0 MHz"),  .phase_shift7("0 ps"),  .duty_cycle7(50),
    .output_clock_frequency8("0 MHz"),  .phase_shift8("0 ps"),  .duty_cycle8(50),
    .output_clock_frequency9("0 MHz"),  .phase_shift9("0 ps"),  .duty_cycle9(50),
    .output_clock_frequency10("0 MHz"), .phase_shift10("0 ps"), .duty_cycle10(50),
    .output_clock_frequency11("0 MHz"), .phase_shift11("0 ps"), .duty_cycle11(50),
    .output_clock_frequency12("0 MHz"), .phase_shift12("0 ps"), .duty_cycle12(50),
    .output_clock_frequency13("0 MHz"), .phase_shift13("0 ps"), .duty_cycle13(50),
    .output_clock_frequency14("0 MHz"), .phase_shift14("0 ps"), .duty_cycle14(50),
    .output_clock_frequency15("0 MHz"), .phase_shift15("0 ps"), .duty_cycle15(50),
    .output_clock_frequency16("0 MHz"), .phase_shift16("0 ps"), .duty_cycle16(50),
    .output_clock_frequency17("0 MHz"), .phase_shift17("0 ps"), .duty_cycle17(50),
    .pll_type("General"),
    .pll_subtype("General")
) altera_pll_i (
    .rst      (rst),
    .outclk   ({outclk_2, outclk_1, outclk_0}),
    .locked   (locked),
    .fboutclk (),
    .fbclk    (1'b0),
    .refclk   (refclk)
);
endmodule
`endif
