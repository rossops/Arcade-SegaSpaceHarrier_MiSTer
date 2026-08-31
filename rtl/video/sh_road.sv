//============================================================================
//  segaic16 road generator, HANGON/SHARRIER variant — a port of MAME's
//  netlist emulation (segaic16_road.cpp segaic16_road_hangon_draw: the
//  counters at 9M and 9N/9P, the two 9J flip-flops, the 8S serial shift
//  register). Renders the next scanline from live road RAM into a
//  double-buffered line buffer at two clocks per pixel (state step + ROM
//  fetch), 24 warm-up pixels before x 0 as in MAME's loop from -24.
//
//  Road RAM (word offsets): 0x000+y control (bits 11:10 PLYCONT — 0 = the
//  line belongs to the background pass, under the tile layers; else the
//  foreground pass, over them), 0x100+idx horizontal position, 0x200+idx
//  colour word 0, 0x300+idx colour word 1, idx = control[7:0] = ROM line.
//  Colour bases (segahang_v.cpp): road pixels 0x038, background 0x7C0.
//  The variant difference is control bit 9: stripe enable (forces ff9j2,
//  Hang-On) versus ROM /CE (blanks the road data, Space Harrier).
//============================================================================
module sh_road (
    input             clk,
    input             reset,
    input             sharrier,      // descriptor: SHARRIER bit-9 semantics

    // timing
    input             line_start,
    input       [8:0] vcnt,
    input             ce_pix,
    input       [8:0] hcnt,

    // road RAM read port (1-clock latency)
    output reg [10:0] ram_addr,
    input      [15:0] ram_q,
    // road ROM (1-clock latency)
    output reg [13:0] rom_addr,
    input       [7:0] rom_p0, rom_p1,

    // per-pixel output, valid the clock after ce_pix for pixel hcnt
    output reg [10:0] road_pix,      // palette index
    output reg  [1:0] road_ply      // the line's PLYCONT
);

// ---------------------------------------------------------------- line buffer
reg [10:0] lb [0:1023];
reg  [1:0] ply_bank [0:1];
wire       disp_bank = vcnt[0];
wire       rend_bank = ~vcnt[0];

// ---------------------------------------------------------------- renderer
typedef enum logic [2:0] { S_IDLE, S_REGS, S_PRIME, S_PIXA, S_PIXB, S_DONE } st_t;
st_t st;

reg  [8:0] ry;
reg  [2:0] rcnt;
reg [15:0] control, hpos, color0, color1;
reg  [9:0] x;                 // 0..343 (pixel = x - 24)

// netlist state
reg  [2:0] ctr9m;
reg  [8:0] ctr9n9p;           // MAME keeps an int; 9 bits covers its range
reg        ff9j1, ff9j2;
reg  [7:0] ss8j;

// fetch registers, primed one pixel ahead: the address registers at the
// previous pixel's phase B (from the next-state values), the ROM's output
// registers during phase A, and phase B reads settled data — the RAM's
// two-cycle cadence, a third time
reg        mdwin;             // (ctr9n9p & 0xC0) == 0xC0 for the fetched pixel
reg  [2:0] rombit;

// MAME's loop-top order: the 0xFF clear first, then the control-bit-8 set,
// so the set wins when both apply
wire       f1_forced = ~control[8] ? 1'b1 : (&ctr9n9p[7:0]) ? 1'b0 : ff9j1;
// this pixel's effective ff9j2 (the loop-top forced set, HANGON only)
wire       ff9j2_eff = (!sharrier && !control[9]) ? 1'b1 : ff9j2;
// this pixel's fetch index (used only by S_PRIME, for pixel 0)
wire [8:0] pixidx = {ctr9n9p[5:0], (ss8j[0] ? ctr9m : ctr9m ^ 3'd7)};
// next-state values, for priming the following pixel's fetch in phase B
wire [2:0] ctr9m_n   = ctr9m + 3'd1;
wire [8:0] ctr9n9p_n = (ctr9m == 3'd7) ? (f1_forced ? ctr9n9p + 9'd1 : ctr9n9p - 9'd1) : ctr9n9p;
wire [8:0] pixidx_n  = {ctr9n9p_n[5:0], (f1_forced ? ctr9m_n : ctr9m_n ^ 3'd7)};
// colour logic, combinational; phase B writes its result to the buffer
reg  [1:0] md_c;
reg        sel_c;
reg [10:0] col_c;
always @* begin
    md_c  = mdwin ? {rom_p1[rombit], rom_p0[rombit]} : 2'd3;
    sel_c = ss8j[3];
    if (ff9j2_eff && md_c == 2'd3)
        col_c = 11'h7C0 | {5'd0, sel_c ? color0[5:0] : color0[13:8]};
    else begin
        if (color1[7] && md_c == 2'd3) md_c = 2'd0;
        col_c = 11'h038 | {7'd0, sel_c, md_c, color1[{1'b0, md_c, sel_c}]};
    end
end

always @(posedge clk) begin
    if (reset) begin
        st <= S_IDLE; ry <= 9'd0;
    end
    else begin
        case (st)
        S_IDLE: begin
            if (line_start) begin
                ry <= (vcnt == 9'd261) ? 9'd0 : vcnt + 9'd1;
                rcnt <= 3'd0;
                st <= S_REGS;
            end
        end

        // control first (its low byte indexes the other three), then hpos,
        // colour 0, colour 1; a capture trails its issue by two steps (the
        // RAM's registered address then registered output — the tilemap's
        // hard-won cadence)
        S_REGS: begin
            if (ry >= 9'd224) st <= S_DONE;
            else begin
                rcnt <= rcnt + 3'd1;
                case (rcnt)
                    3'd0: ram_addr <= {2'b00, ry};
                    3'd2: ram_addr <= {3'b001, ram_q[7:0]};   // idx straight off the bus
                    3'd3: ram_addr <= {3'b010, control[7:0]};
                    3'd4: ram_addr <= {3'b011, control[7:0]};
                    default: ;
                endcase
                case (rcnt)
                    3'd2: control <= ram_q;
                    3'd4: hpos    <= ram_q;
                    3'd5: color0  <= ram_q;
                    default: ;
                endcase
                if (rcnt == 3'd6) begin
                    color1  <= ram_q;
                    ctr9m   <= hpos[2:0];
                    ctr9n9p <= {1'b0, hpos[10:3]};
                    ff9j1   <= hpos[11];
                    ff9j2   <= 1'b1;
                    ss8j    <= 8'd0;
                    x       <= 10'd0;
                    ply_bank[rend_bank] <= control[11:10];
                    st <= S_PRIME;
                end
            end
        end

        // prime pixel 0's fetch from the initial state
        S_PRIME: begin
            rom_addr <= {control[7:0], pixidx[8:3]};
            rombit   <= ~pixidx[2:0];
            mdwin    <= (ctr9n9p[7:6] == 2'b11) && !(sharrier && control[9]);
            st <= S_PIXA;
        end

        // phase A: the ROM's output register catches up with the address
        S_PIXA: st <= S_PIXB;

        // phase B: ROM bytes settled — colour, line-buffer write, the 6M
        // state clock, and the next pixel's fetch primed from next-state
        S_PIXB: begin
            if (x >= 10'd24) lb[{rend_bank, 9'((x - 10'd24))}] <= col_c;
            ctr9m   <= ctr9m_n;
            ctr9n9p <= ctr9n9p_n;
            ff9j2   <= (!f1_forced && ss8j[7]) ? 1'b0 : 1'b1;
            ss8j    <= {ss8j[6:0], f1_forced};
            ff9j1   <= f1_forced;
            rom_addr <= {control[7:0], pixidx_n[8:3]};
            rombit   <= ~pixidx_n[2:0];
            mdwin    <= (ctr9n9p_n[7:6] == 2'b11) && !(sharrier && control[9]);
            x <= x + 10'd1;
            if (x == 10'd343) st <= S_DONE;
            else st <= S_PIXA;
        end

        S_DONE: st <= S_IDLE;
        default: st <= S_IDLE;
        endcase
    end
end

// ---------------------------------------------------------------- display side
// one pixel of prefetch, as the tilemap's display side
wire [8:0] hnext = (hcnt == 9'd399) ? 9'd0 : hcnt + 9'd1;
wire       bnext = (hcnt == 9'd399) ? ~disp_bank : disp_bank;
always @(posedge clk) begin
    if (ce_pix) begin
        road_pix <= lb[{bnext, hnext}];
        road_ply <= ply_bank[bnext];
    end
end
endmodule
