//============================================================================
//  Sega 315-5011/5012 tilemap generator, "TILEMAP_HANGON" register layout
//  (MAME segaic16.cpp tilemap_16a_*, the 4-page 16A variant). Renders the
//  next scanline of the foreground (which = 0), background (which = 1) and
//  text layers into double-buffered line buffers, one pixel per clock.
//
//  Unlike the 16B chip there is no register latch (registers are read from
//  text RAM as each line renders), no alternate register sets, and the row/
//  column scroll enables are external signals (PPI0 port C bits 1 and 2,
//  active low, already inverted to active-high here).
//
//  Text RAM (word offsets in the 2048-word RAM):
//    0x74F / 0x74E  fg / bg page select (0x746/0x747 when flipped, M6+)
//    0x7FC / 0x7FD  fg / bg x scroll (9 bits); eff = (0xC8 - x) & 0x3FF
//    0x792 / 0x793  fg / bg y scroll (8 bits)
//    0x7C0 + (y>>3)*2 + which   row scroll (9 bits)
//    0x798 + (x>>4)*2 + which   column scroll (8 bits)
//  Virtual map: 4 pages of 64x32 tiles in 2x2; the page word is nibble-
//  swapped along X and masked to 0x3333. Tile word: 12 priority category,
//  11:5 colour, code = {bit13, 11:0} (wraps on the 4096-tile ROM). Text:
//  64x28 at screen x = col*8 - 192; word: 11 priority, 10:8 colour, 7:0 code.
//============================================================================
module sh_tilemap_5012 (
    input             clk,
    input             reset,

    // timing
    input             line_start,     // one clk at hcnt == 0 (with ce_pix)
    input       [8:0] vcnt,           // line now being displayed
    input             ce_pix,
    input       [8:0] hcnt,

    // control (from PPI0 port C, active high here)
    input             rowscroll_en,
    input             colscroll_en,

    // tile RAM / text RAM read ports (1-clock latency)
    output reg [12:0] tile_addr,
    input      [15:0] tile_q,
    output reg [10:0] text_addr,
    input      [15:0] text_q,
    // tile ROM (1-clock latency)
    output reg [14:0] rom_addr,
    input       [7:0] rom_p0, rom_p1, rom_p2,

    // per-pixel output, valid the clock after ce_pix for pixel hcnt
    output reg [10:0] fg_pix,         // {category, colour[6:0], pen[2:0]}
    output reg [10:0] bg_pix,
    output reg  [6:0] tx_pix          // {category, colour[2:0], pen[2:0]}
);

integer i;

// ---------------------------------------------------------------- line buffers
reg [10:0] lb_fg [0:1023];
reg [10:0] lb_bg [0:1023];
reg  [6:0] lb_tx [0:1023];
wire       disp_bank = vcnt[0];
wire       rend_bank = ~vcnt[0];

// ---------------------------------------------------------------- renderer FSM
typedef enum logic [3:0] {
    S_IDLE, S_REGS, S_COL, S_PIX, S_DRAIN, S_TEXT, S_TEXT_DRAIN, S_DONE
} st_t;
st_t st;

reg  [8:0] ry;              // line being rendered
reg        layer;           // 0 fg, 1 bg (MAME's 'which')
reg  [2:0] rcnt;            // register read counter
reg  [4:0] ccnt;            // column-scroll read counter
reg [15:0] pages_raw;
reg  [8:0] xscroll;
reg  [7:0] yscroll;
reg  [8:0] rowword;
reg  [7:0] colscroll [0:19];
reg  [9:0] x;               // pixel counter 0..319

// nibble swap + 4-page mask, applied once the raw word is read
wire [15:0] pages = (((pages_raw >> 4) & 16'h0707) | ((pages_raw << 4) & 16'h7070)) & 16'h3333;

// pipeline: stage k = k clocks after the tile/text RAM address registered.
//   k=1 word valid -> ROM address registered, k=2 ROM registers,
//   k=3 plane bytes valid -> line buffer write.
reg  [4:0] pipe;
reg  [8:0] xq [0:4];
reg  [2:0] bitq [0:4];
reg  [2:0] rowq [0:4];
reg [15:0] word_s3, word_s4;

// effective scroll for the current pixel
wire [8:0] xs_eff = rowscroll_en ? rowword : xscroll;
wire [7:0] ys_pix = colscroll_en ? colscroll[x[8:4]] : yscroll;
wire [9:0] effx   = (10'h0C8 - {1'b0, xs_eff}) & 10'h3FF;
wire [9:0] px     = (x + effx) & 10'h3FF;
wire [8:0] py     = (ry + {1'b0, ys_pix}) & 9'h1FF;
wire [1:0] quadrant = {py[8], px[9]};
wire [1:0] page   = quadrant == 2'd0 ? pages[1:0]  : quadrant == 2'd1 ? pages[5:4] :
                    quadrant == 2'd2 ? pages[9:8]  : pages[13:12];

wire [2:0] pen_s3 = {rom_p2[bitq[3]], rom_p1[bitq[3]], rom_p0[bitq[3]]};

always @(posedge clk) begin
    if (reset) begin
        st <= S_IDLE; ry <= 9'd0; pipe <= 5'd0; layer <= 1'b0;
    end
    else begin
        case (st)
        S_IDLE: begin
            if (line_start) begin
                ry <= (vcnt == 9'd261) ? 9'd0 : vcnt + 9'd1;
                layer <= 1'b0;
                rcnt <= 3'd0;
                st <= S_REGS;
            end
        end

        // register reads for this layer: pages, xscroll, yscroll, this
        // line's rowscroll word, then the first column-scroll word. The RAM
        // data is capturable two cycles after the address registers (the
        // address registers on one edge, the RAM output on the next), so
        // each capture trails its issue by two rcnt steps.
        S_REGS: begin
            if (ry >= 9'd224) st <= S_DONE;
            else begin
                rcnt <= rcnt + 3'd1;
                case (rcnt)
                    3'd0: text_addr <= layer ? 11'h74E : 11'h74F;   // pages
                    3'd1: text_addr <= layer ? 11'h7FD : 11'h7FC;   // x scroll
                    3'd2: text_addr <= layer ? 11'h793 : 11'h792;   // y scroll
                    3'd3: text_addr <= 11'h7C0 + {5'd0, ry[7:3], 1'b0} + {10'd0, layer};   // row scroll
                    default: text_addr <= 11'h798 + {10'd0, layer};  // column scroll word 0
                endcase
                case (rcnt)
                    3'd2: pages_raw <= text_q;
                    3'd3: xscroll   <= text_q[8:0];
                    3'd4: yscroll   <= text_q[7:0];
                    default: ;
                endcase
                if (rcnt == 3'd5) begin
                    rowword <= text_q[8:0];
                    ccnt <= 5'd0;
                    st <= S_COL;
                end
            end
        end
        // read the 20 column-scroll words (harmless when disabled)
        S_COL: begin
            ccnt <= ccnt + 5'd1;
            text_addr <= 11'h798 + {4'd0, ccnt + 5'd1, 1'b0} + {10'd0, layer};
            if (ccnt != 5'd0) colscroll[ccnt - 5'd1] <= text_q[7:0];
            if (ccnt == 5'd20) begin x <= 10'd0; pipe <= 5'd0; st <= S_PIX; end
        end
        // pixel pipeline
        S_PIX: begin
            tile_addr <= {page, py[7:3], px[8:3]};
            xq[0] <= x[8:0]; bitq[0] <= ~px[2:0]; rowq[0] <= py[2:0];
            x <= x + 10'd1;
            if (x == 10'd319) st <= S_DRAIN;
        end
        S_DRAIN: begin
            if (pipe == 5'd0) begin
                if (!layer) begin layer <= 1'b1; rcnt <= 3'd0; st <= S_REGS; end
                else begin x <= 10'd0; st <= S_TEXT; end
            end
        end
        // text layer: word at row*64 + 24 + x/8
        S_TEXT: begin
            text_addr <= {ry[7:3], 6'd0} + 11'd24 + {5'd0, x[8:3]};
            xq[0] <= x[8:0]; bitq[0] <= ~x[2:0]; rowq[0] <= ry[2:0];
            x <= x + 10'd1;
            if (x == 10'd319) st <= S_TEXT_DRAIN;
        end
        S_TEXT_DRAIN: begin
            if (pipe == 5'd0) st <= S_DONE;
        end
        S_DONE: st <= S_IDLE;
        default: st <= S_IDLE;
        endcase

        // pipeline shift
        pipe <= {pipe[3:0], (st == S_PIX || st == S_TEXT)};
        for (i = 1; i < 5; i = i + 1) begin xq[i] <= xq[i-1]; bitq[i] <= bitq[i-1]; rowq[i] <= rowq[i-1]; end
        // stage 1: tile/text word valid, register the ROM address
        if (pipe[1]) begin
            if (st == S_PIX || st == S_DRAIN) begin
                rom_addr <= {tile_q[11:0], rowq[1]};   // code bit 13 wraps on 4096 tiles
                word_s3  <= tile_q;
            end
            else begin
                rom_addr <= {4'd0, text_q[7:0], rowq[1]};
                word_s3  <= text_q;
            end
        end
        word_s4 <= word_s3;
        // stage 3: plane bytes valid, write the line buffer
        if (pipe[3]) begin
            if (st == S_PIX || st == S_DRAIN) begin
                if (!layer) lb_fg[{rend_bank, xq[3]}] <= {word_s4[12], word_s4[11:5], pen_s3};
                else        lb_bg[{rend_bank, xq[3]}] <= {word_s4[12], word_s4[11:5], pen_s3};
            end
            else lb_tx[{rend_bank, xq[3]}] <= {word_s4[11], word_s4[10:8], pen_s3};
        end
    end
end

// ---------------------------------------------------------------- display side
// One pixel of prefetch: at pixel N's ce_pix the buffers are read for
// pixel N+1, so the palette's registered pipeline delivers pixel N+1's
// RGB in time for its own ce_pix sample (the parents' M2/M3 alignment
// lesson, applied up front). At the line wrap the next pixel belongs to
// the next line's display bank.
wire [8:0] hnext = (hcnt == 9'd399) ? 9'd0 : hcnt + 9'd1;
wire       bnext = (hcnt == 9'd399) ? ~disp_bank : disp_bank;
always @(posedge clk) begin
    if (ce_pix) begin
        fg_pix <= lb_fg[{bnext, hnext}];
        bg_pix <= lb_bg[{bnext, hnext}];
        tx_pix <= lb_tx[{bnext, hnext}];
    end
end
endmodule
