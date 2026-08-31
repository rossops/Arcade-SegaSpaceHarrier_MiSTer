//============================================================================
//  SEGA_HANGON_SPRITES (sega16sp.cpp) as a line renderer. MAME draws whole
//  sprites from live RAM with a per-sprite row-base accumulator (`addr`,
//  advanced by pitch, doubled on zoom-ROM row skips) and a scratch fetch
//  pointer (data[7]); the real chip is line-based. This renderer takes a
//  private copy of sprite RAM once per frame (at line 260, after the
//  game's vblank writes) with word 7 initialised to word 3, then per line
//  walks the list: an entry spanning the line advances its word-7 row base
//  exactly as MAME's row loop does and emits one source nibble per clock
//  into a double line buffer. Sprite rows land one screen line down
//  (set_local_origin y = -1) and x 0xBD is screen 0 (origin 189).
//
//  ROM words come from SDRAM port p2 in 128-bit bursts, cached one burst
//  at a time; the row's fetch direction is bit 15 of the row base at row
//  start (the address-overflow-into-flip interaction rides on the 16-bit
//  add and the 15-bit fetch mask, as in MAME). Pen 0 and 15 transparent,
//  pen 15 in a word's last position ends the row; the row also ends at
//  the word boundary after x passes the right edge (MAME's group
//  re-entry check). Buffer pixel: {priority[1:0], colour[5:0], pen[3:0]},
//  pen 0 = empty.
//============================================================================
import sh_pkg::*;

module sh_sprite (
    input             clk,
    input             reset,
    input       [7:0] numbanks,     // descriptor: 64 KB banks, bank % numbanks

    // timing
    input             line_start,
    input       [8:0] vcnt,
    input             ce_pix,
    input       [8:0] hcnt,

    // CPU sprite RAM read port (1-clock-registered address and output)
    output reg  [9:0] cram_addr,
    input      [15:0] cram_q,
    // zoom PROM (same cadence)
    output reg [12:0] zoom_addr,
    input       [7:0] zoom_q,

    // SDRAM p2: 128-bit reads
    output reg        rom_req,
    output     [24:4] rom_addr,
    input     [127:0] rom_dout,
    input             rom_ack,

    // per-pixel output, valid the clock after ce_pix for pixel hcnt
    output reg [11:0] spr_pix,

    // bench: clocks the busiest line took, lines that overran
    output reg [11:0] line_clocks,
    output reg  [7:0] late_lines
);

// ---------------------------------------------------------------- line buffer
reg [11:0] lb [0:1023];
wire       disp_bank = vcnt[0];
wire       rend_bank = ~vcnt[0];

// ---------------------------------------------------------------- private copy
reg [15:0] copy [0:1023];
`ifdef SIMULATION
integer ci;
initial begin
    for (ci = 0; ci < 1024; ci = ci + 1) copy[ci] = 16'd0;
    for (ci = 0; ci < 1024; ci = ci + 1) lb[ci] = 12'd0;
end
`endif
reg  [9:0] copy_addr;
reg [15:0] copy_rq;
reg        copy_we;
reg  [9:0] copy_waddr;
reg [15:0] copy_wdata;
always @(posedge clk) begin
    if (copy_we) copy[copy_waddr] <= copy_wdata;
    copy_rq <= copy[copy_addr];
end

// ---------------------------------------------------------------- renderer
typedef enum logic [3:0] {
    S_IDLE, S_COPY, S_ERASE, S_HDR, S_DECIDE, S_ZWAIT, S_STEP,
    S_ROW, S_FETCH, S_PIX, S_LDONE
} st_t;
st_t st;

reg        copied;            // at least one list copy has run
reg  [8:0] ry;
reg [10:0] ccnt;              // copy counter
reg [15:0] w3_hold;
reg  [2:0] hcnt2;             // header read step
reg  [6:0] entry;             // 0..127
reg [15:0] w0, w1, w2, w4, w7;
reg  [8:0] xw;                // erase counter

// per-row state
reg  [7:0] ytop;
wire [8:0] yrow = ry - 9'd1;  // sprite row for this screen line
wire       row_hit = (ry != 9'd0) && ({1'b0, w0[7:0]} <= yrow) && (yrow < {1'b0, w0[15:8]});
reg [15:0] rowbase;
reg        dir;
reg [15:0] cur;
reg  [3:0] bank_eff;
reg  [1:0] nib;
reg  [8:0] xacc;
reg signed [10:0] x;
reg [15:0] word;
reg        word_valid;
reg [11:0] colpri;            // {prio, colour, 0000}
reg  [7:0] hzoom;

// burst cache
reg        tag_valid;
reg [15:0] tag;               // {bank, word[14:3]}
reg [127:0] burst;
wire [15:0] next_cur = dir ? cur - 16'd1 : cur + 16'd1;
wire [15:0] want_tag = {bank_eff, next_cur[14:3]};
assign rom_addr = SDR_SPR_BASE[24:4] + {5'd0, bank_eff, next_cur[14:3]};

wire [5:0] vzoom = w4[7:2];
wire [15:0] pitch = w2;

// current nibble (order depends on direction)
wire [1:0] nsel = dir ? nib : 2'd3 - nib;
wire [3:0] pix = word[{nsel, 2'b00} +: 4];
wire [8:0] xacc_n = {1'b0, xacc[7:0]} + {1'b0, hzoom};

always @(posedge clk) begin
    copy_we <= 1'b0;
    if (reset) begin
        st <= S_IDLE; ry <= 9'd0; tag_valid <= 1'b0; rom_req <= 1'b0;
        copied <= 1'b0;
        line_clocks <= 12'd0; late_lines <= 8'd0;
    end
    else begin
        case (st)
        S_IDLE: begin
            if (line_start) begin
                if (vcnt == 9'd260) begin
                    ccnt <= 11'd0;
                    cram_addr <= 10'd0;
                    st <= S_COPY;
                end
                else if (copied && ((vcnt == 9'd261) || (vcnt < 9'd223))) begin
                    ry <= (vcnt == 9'd261) ? 9'd0 : vcnt + 9'd1;
                    xw <= 9'd0;
                    line_clocks <= 12'd0;
                    st <= S_ERASE;
                end
            end
        end

        // copy the CPU's list. The address was preset at the IDLE edge, so
        // word k's data is readable in cycle k+1 (capture at ccnt-1, unlike
        // the case-issued reads elsewhere that capture at +2). Word 7 of
        // each entry is initialised to its word 3 (MAME's data[7] = addr).
        S_COPY: begin
            ccnt <= ccnt + 11'd1;
            cram_addr <= ccnt[9:0] + 10'd1;
            if (ccnt >= 11'd1) begin
                copy_we    <= 1'b1;
                copy_waddr <= ccnt[9:0] - 10'd1;
                if (ccnt[2:0] == 3'd4) w3_hold <= cram_q;     // word 3 passing
                copy_wdata <= (ccnt[2:0] == 3'd0) ? w3_hold : cram_q;  // word 7 slot
            end
            if (ccnt == 11'd1024) begin copied <= 1'b1; st <= S_IDLE; end
        end

        S_ERASE: begin
            lb[{rend_bank, xw}] <= 12'd0;
            xw <= xw + 9'd1;
            if (xw == 9'd319) begin
                entry <= 7'd0;
                hcnt2 <= 3'd0;
                copy_addr <= 10'd0;
                st <= S_HDR;
            end
        end

        // header words 0,1,2,4,7 (issue in cycle k, capture in cycle k+2 —
        // the RAM cadence, same as every renderer here)
        S_HDR: begin
            hcnt2 <= hcnt2 + 3'd1;
            case (hcnt2)
                3'd0: copy_addr <= {entry, 3'd0};
                3'd1: copy_addr <= {entry, 3'd1};
                3'd2: begin copy_addr <= {entry, 3'd2}; w0 <= copy_rq; end
                3'd3: begin copy_addr <= {entry, 3'd4}; w1 <= copy_rq; end
                3'd4: begin copy_addr <= {entry, 3'd7}; w2 <= copy_rq; end
                3'd5: w4 <= copy_rq;
                default: begin w7 <= copy_rq; st <= S_DECIDE; end
            endcase
        end

        S_DECIDE: begin
            if (w0[15:8] > 8'hF0) st <= S_LDONE;                 // end of list
            else if (!row_hit) begin
                entry <= entry + 7'd1;
                hcnt2 <= 3'd0;
                copy_addr <= {entry + 7'd1, 3'd0};
                if (entry == 7'd127) st <= S_LDONE;
                else st <= S_HDR;
            end
            else begin
                ytop      <= w0[7:0];
                zoom_addr <= {2'b00, vzoom[5:3], 8'd0} + {4'd0, yrow - {1'b0, w0[7:0]}};
                colpri    <= {w4[1:0], w4[13:8], 4'd0};
                hzoom     <= {1'b0, vzoom, 1'b0};
                bank_eff  <= (w1[15:12] >= numbanks[3:0]) ? w1[15:12] - numbanks[3:0] : w1[15:12];
                hcnt2     <= 3'd0;
                st <= S_ZWAIT;
            end
        end

        // zoom byte arrives two clocks after the address
        S_ZWAIT: begin
            hcnt2 <= hcnt2 + 3'd1;
            if (hcnt2 == 3'd1) st <= S_STEP;
        end

        S_STEP: begin
            logic [15:0] a1;
            a1 = w7 + pitch;
            if (zoom_q[vzoom[2:0]]) a1 = a1 + pitch;
            rowbase <= a1;
            copy_we    <= 1'b1;
            copy_waddr <= {entry, 3'd7};
            copy_wdata <= a1;
            dir  <= a1[15];
            cur  <= a1[15] ? a1 + 16'd1 : a1 - 16'd1;
            x    <= $signed({2'b00, w1[8:0]}) - 11'sd189;
            xacc <= 9'd0;
            nib  <= 2'd0;
            word_valid <= 1'b0;
            st <= S_ROW;
        end

        // start of a word: fetch it (cache hit or SDRAM burst)
        S_ROW: begin
            if (x > 11'sd319) begin                     // MAME's group re-entry check
                entry <= entry + 7'd1;
                hcnt2 <= 3'd0;
                copy_addr <= {entry + 7'd1, 3'd0};
                if (entry == 7'd127) st <= S_LDONE;
                else st <= S_HDR;
            end
            else if (tag_valid && tag == want_tag) begin
                cur  <= next_cur;
                word <= burst[{next_cur[2:0], 4'b0000} +: 16];
                nib  <= 2'd0;
                st <= S_PIX;
            end
            else begin
                rom_req <= 1'b1;      // transaction on the rising edge
                st <= S_FETCH;
            end
        end

        S_FETCH: begin
            if (rom_ack) begin
                rom_req <= 1'b0;
                burst <= rom_dout;
                tag <= want_tag;
                tag_valid <= 1'b1;
                cur  <= next_cur;
                word <= rom_dout[{next_cur[2:0], 4'b0000} +: 16];
                nib  <= 2'd0;
                st <= S_PIX;
            end
        end

        // one source nibble per clock
        S_PIX: begin
            xacc <= xacc_n;
            if (xacc_n < 9'h100) begin
                if (x >= 11'sd0 && x <= 11'sd319 && pix != 4'd0 && pix != 4'd15)
                    lb[{rend_bank, x[8:0]}] <= {colpri[11:4], pix};
                x <= x + 11'sd1;
            end
            if (nib == 2'd3) begin
                if (pix == 4'd15) begin                 // end of row
                    entry <= entry + 7'd1;
                    hcnt2 <= 3'd0;
                    copy_addr <= {entry + 7'd1, 3'd0};
                    if (entry == 7'd127) st <= S_LDONE;
                    else st <= S_HDR;
                end
                else st <= S_ROW;
            end
            else nib <= nib + 2'd1;
        end

        S_LDONE: st <= S_IDLE;
        default: st <= S_IDLE;
        endcase

        // line budget accounting (bench)
        if (st != S_IDLE && st != S_COPY) line_clocks <= line_clocks + 12'd1;
        if (line_start && st != S_IDLE && st != S_COPY && late_lines != 8'hFF)
            late_lines <= late_lines + 8'd1;
    end
end

// ---------------------------------------------------------------- display side
wire [8:0] hnext = (hcnt == 9'd399) ? 9'd0 : hcnt + 9'd1;
wire       bnext = (hcnt == 9'd399) ? ~disp_bank : disp_bank;
always @(posedge clk) begin
    if (ce_pix) spr_pix <= lb[{bnext, hnext}];
end
endmodule
