//============================================================================
//  Board simulation top (Verilator). Clocks come from the C++ driver.
//  Writes one PPM per frame, 48 kHz audio and (from M1) the executed-PC
//  traces of the two 68000s. The Y Board bench's chip watches (+watch_a,
//  +trace_vid, +dumpframe RAM dumps, ROMWR/PORTE logs) reached into core
//  internals and come back with the blocks they watch, per milestone; its
//  +dumpframe comment block is the worked example for the dump timing.
//============================================================================
`timescale 1ns/1ps
import sh_pkg::*;

module tb_board (
    input clk_sys,
    input clk_ram,
    input reset,
    input [31:0] max_frames,
    output reg [31:0] frame
);

board_desc_t desc;
integer pa;
reg [7:0] dsw_a, dsw_b;
initial begin dsw_a = 8'hFF; dsw_b = 8'hFE; if ($value$plusargs("dswa=%h", pa)) dsw_a = pa[7:0]; if ($value$plusargs("dswb=%h", pa)) dsw_b = pa[7:0]; end
// descriptor: hangon unless plusargs say otherwise (tools/romsets.py has the values)
initial begin
    desc = '0;
    desc.game_id = 8'd0; desc.spr_banks = 8'd8; desc.adc_reverse = 8'h01;
    desc.sound_board = 2'd0; desc.ana_mode = 3'd0;
    if ($value$plusargs("game_id=%d", pa))     desc.game_id = pa[7:0];
    if ($value$plusargs("sharrier=%d", pa))    desc.sharrier_vid = pa[0];
    if ($value$plusargs("cpu10m=%d", pa))      desc.cpu10m = pa[0];
    if ($value$plusargs("mcu=%d", pa))         desc.has_mcu = pa[0];
    if ($value$plusargs("fd1089b=%d", pa))     desc.fd1089b = pa[0];
    if ($value$plusargs("ops_split=%d", pa))   desc.ops_split = pa[0];
    if ($value$plusargs("sound_board=%d", pa)) desc.sound_board = pa[1:0];
    if ($value$plusargs("spr_banks=%d", pa))   desc.spr_banks = pa[7:0];
    if ($value$plusargs("adc_reverse=%h", pa)) desc.adc_reverse = pa[7:0];
    if ($value$plusargs("ana_mode=%d", pa))    desc.ana_mode = pa[2:0];
end

wire p0_req, p1_req, p2_req, p3_req, p5_req, p6_req;
wire p0_ack, p1_ack, p2_ack, p3_ack, p5_ack, p6_ack, wr_ack, sdr_ready;
wire [24:3] p0_addr, p1_addr, p3_addr, p5_addr;
wire [24:4] p2_addr;
wire [24:1] p6_addr;
wire [63:0] p0_dout, p1_dout, p3_dout, p5_dout;
wire [127:0] p2_dout;
wire [15:0] p6_dout;

sdram_model sdram (
    .clk(clk_ram), .init(reset), .ready(sdr_ready),
    .wr_req(1'b0), .wr_addr(24'd0), .wr_din(16'd0), .wr_be(2'd0), .wr_ack(wr_ack),
    .p0_req(p0_req), .p0_addr(p0_addr), .p0_dout(p0_dout), .p0_ack(p0_ack),
    .p1_req(p1_req), .p1_addr(p1_addr), .p1_dout(p1_dout), .p1_ack(p1_ack),
    .p2_req(p2_req), .p2_addr(p2_addr), .p2_dout(p2_dout), .p2_ack(p2_ack),
    .p3_req(p3_req), .p3_addr(p3_addr), .p3_dout(p3_dout), .p3_ack(p3_ack), .p3_urgent(1'b0),
    .p4_req(1'b0), .p4_addr(21'd0), .p4_dout(), .p4_ack(), .p4_urgent(1'b0),
    .p5_req(p5_req), .p5_addr(p5_addr), .p5_dout(p5_dout), .p5_ack(p5_ack),
    .p6_req(p6_req), .p6_addr(p6_addr), .p6_dout(p6_dout), .p6_ack(p6_ack),
    .p7_req(1'b0), .p7_addr(21'd0), .p7_dout(), .p7_ack()
);

wire [7:0] r, g, b;
wire ce_pix, hs, vs, hb, vb;
wire signed [15:0] al, ar;
wire [23:1] tm_addr, ts_addr; wire tm_start, ts_start; wire [2:0] tm_fc, ts_fc;

// BRAM ROM regions come from hex files in the bench (M2 on); no loader here
sh_core core (
    .clk_sys(clk_sys), .clk_ram(clk_ram), .reset(reset), .pause(1'b0), .board_desc(desc),
    .p0_req(p0_req), .p0_addr(p0_addr), .p0_dout(p0_dout), .p0_ack(p0_ack),
    .p1_req(p1_req), .p1_addr(p1_addr), .p1_dout(p1_dout), .p1_ack(p1_ack),
    .p2_req(p2_req), .p2_addr(p2_addr), .p2_dout(p2_dout), .p2_ack(p2_ack),
    .p3_req(p3_req), .p3_addr(p3_addr), .p3_dout(p3_dout), .p3_ack(p3_ack),
    .p5_req(p5_req), .p5_addr(p5_addr), .p5_dout(p5_dout), .p5_ack(p5_ack),
    .p6_req(p6_req), .p6_addr(p6_addr), .p6_dout(p6_dout), .p6_ack(p6_ack),
    .brm_wr(1'b0), .brm_addr(27'd0), .brm_din(16'd0),
    .p1_buttons({5'd0, 1'b0, test_sw, 1'b0, coin1, p1_start, 6'd0} | hold_now | scr_btn),
    .stick_x(scr_x), .stick_y(scr_y), .throttle(scr_thr),
    .stick_mode(2'd0), .ana_curve(2'd0), .ana_range(2'd0),
    .dsw_a(dsw_a), .dsw_b(dsw_b), .service(1'b0), .test(test_sw), .coin1(coin1), .coin2(1'b0),
    .r(r), .g(g), .b(b), .ce_vid(ce_pix), .hs(hs), .vs(vs), .hb(hb), .vb(vb),
    .audio_l(al), .audio_r(ar),
    .trace_main_addr(tm_addr), .trace_main_start(tm_start), .trace_main_fc(tm_fc),
    .trace_sub_addr(ts_addr), .trace_sub_start(ts_start), .trace_sub_fc(ts_fc),
    .dbg_snd_drop(dbg_snd_drop), .dbg_pcm_drop(dbg_pcm_drop), .dbg_z80_crash(dbg_z80_crash)
);
// the sound board's sticky debug flags, logged the moment they set
wire dbg_snd_drop, dbg_pcm_drop, dbg_z80_crash;
reg  z80_crash_d;
always @(posedge clk_sys) begin
    z80_crash_d <= dbg_z80_crash;
    if (core.snd_overwrite) $display("SNDOVR f=%0d line=%0d: latch byte %02x overwritten before the Z80 took it (z80 pc=%04x rst_n=%b nmi_pending=%b)",
                                     frame, core.vcnt, core.pa0_out, core.soundsys.z_addr, core.soundsys.z_rst_n, core.soundsys.z80_dbg[15]);
    if (core.pcm_tick_lost) $display("PCMLOST f=%0d: PCM tick while the engine was busy", frame);
    if (dbg_z80_crash && !z80_crash_d) $display("Z80CRASH f=%0d: opcode fetch at %04x", frame, core.soundsys.z_addr);
    // a Z80 reset with a latch byte still pending would leave /OBF low with
    // no NMI edge to come: log every reset with the handshake state
    z80_run_d <= core.z80_run;
    if (!core.z80_run && z80_run_d) $display("Z80RST f=%0d obf_n=%b (byte %02x pending=%b)", frame, core.snd_obf_n, core.pa0_out, ~core.snd_obf_n);
end
reg z80_run_d;

// ---- traces
//  trace_*_rtl.txt : program-space word fetches (FC = 2 user / 6 supervisor)
//  trace_*_pc.txt  : executed instructions: the PC when fx68k moves IR to
//                    IRD (instruction start), following the prefetch queue
//                    (the word captured into Irc came from address eab; Ir
//                    and Ird shift the matching address along)
integer fm, fs, fmp, fsp, fppm;
initial begin
    fm  = $fopen("trace_main_rtl.txt", "w");
    fs  = $fopen("trace_sub_rtl.txt", "w");
    fmp = $fopen("trace_main_pc.txt", "w");
    fsp = $fopen("trace_sub_pc.txt", "w");
    frame = 0;
end
`define CPU_TRACE(pfx, cpu, fh) \
reg [23:1] pfx``_a_irc, pfx``_a_ir, pfx``_a_ird; \
reg [23:1] pfx``_last; \
always @(posedge clk_sys) begin \
    if (reset) begin pfx``_a_irc <= 0; pfx``_a_ir <= 0; pfx``_a_ird <= 0; pfx``_last <= 23'h7fffff; end \
    else begin \
        if (cpu.excUnit.dataIo.xToIrc && cpu.enPhi2) pfx``_a_irc <= cpu.eab; \
        if (cpu.enT1) begin \
            if (cpu.Nanod.Ir2Ird) begin \
                pfx``_a_ird <= pfx``_a_ir; \
                if (pfx``_a_ir != pfx``_last) begin $fwrite(fh, "%06x\n", {pfx``_a_ir, 1'b0}); pfx``_last <= pfx``_a_ir; end \
            end \
            else if (cpu.microLatch[0]) pfx``_a_ir <= pfx``_a_irc; \
        end \
    end \
end
`CPU_TRACE(mt, core.main_cpu.cpu, fmp)
`CPU_TRACE(st, core.sub_cpu.cpu, fsp)
always @(posedge clk_sys) begin
    if (!reset) begin
        if (tm_start && tm_fc[1]) $fwrite(fm, "%06x\n", {tm_addr, 1'b0});
        if (ts_start && ts_fc[1]) $fwrite(fs, "%06x\n", {ts_addr, 1'b0});
    end
end

// ---- PPI port B (display enable, Z80 reset, lamps, coins) and the sub
// control byte (PPI1 port A: sub reset, sub IRQ4, ADC channel): log changes
reg [7:0] pb0_d, pa1_d;
always @(posedge clk_sys) begin
    pb0_d <= core.pb0_out;
    pa1_d <= core.pa1_out;
    if (core.pb0_out !== pb0_d) $display("PORTB f=%0d line=%0d %02x (flip=%0d shade=%0d z80run=%0d disp=%0d)", frame, core.vcnt,
        core.pb0_out, core.pb0_out[7], core.pb0_out[6], core.pb0_out[5], core.pb0_out[4]);
    if (core.pa1_out !== pa1_d) $display("SUBCTL f=%0d line=%0d %02x (irq4n=%0d res=%0d adcsel=%0d)", frame, core.vcnt,
        core.pa1_out, core.pa1_out[6], core.pa1_out[5], core.pa1_out[3:2]);
end

// ---- writes into ROM space: acknowledged and dropped by the core; logged
// (first 8) because a game doing this is worth knowing about
integer romwr_n = 0;
always @(posedge clk_sys) begin
    if (core.m_start && core.m_wr && (core.m_sel_rom || core.m_sel_subrom) && romwr_n < 8) begin
        romwr_n = romwr_n + 1; $display("ROMWR f=%0d line=%0d main %06x", frame, core.vcnt, {core.m_addr, 1'b0});
    end
    if (core.s_start && core.s_wr && core.s_sel_rom && romwr_n < 8) begin
        romwr_n = romwr_n + 1; $display("ROMWR f=%0d line=%0d sub %06x", frame, core.vcnt, {core.s_addr, 1'b0});
    end
end

// ---- +watch_a=/+watch_b=<hex byte addr>: log shared-space accesses (sub
// RAM C7C000-C7FFFF / road C68000-C68FFF, give the sub-CPU-view low bits):
// writes always, reads when the value changed. For chasing CPU handshakes.
integer watch_a = -1, watch_b = -1;
initial begin
    if (!$value$plusargs("watch_a=%h", watch_a)) watch_a = -1;
    if (!$value$plusargs("watch_b=%h", watch_b)) watch_b = -1;
end
reg        w_hit; reg w_cpu; reg w_we; reg [1:0] w_be; reg [15:0] w_din; reg [13:0] w_addr;
reg [15:0] w_last_a, w_last_b;
reg        w_seen_a, w_seen_b;
initial begin w_seen_a = 1'b0; w_seen_b = 1'b0; end
always @(posedge clk_sys) begin
    w_hit <= 1'b0;
    if (core.shr_pick_m || core.shr_pick_s) begin
        if ({18'd0, core.shr_addr, 1'b0} == watch_a || {18'd0, core.shr_addr, 1'b0} == watch_b) begin
            w_hit <= 1'b1; w_cpu <= core.shr_pick_s;
            w_we <= core.shr_we; w_be <= core.shr_be; w_din <= core.shr_din; w_addr <= {core.shr_addr, 1'b0};
        end
    end
    if (w_hit) begin
        if (w_we || (w_addr == watch_a[13:0] ? (!w_seen_a || core.shr_q != w_last_a) : (!w_seen_b || core.shr_q != w_last_b))) begin
            $display("SHR f=%0d line=%0d %s %s +%04x be=%b din=%04x q=%04x", frame, core.vcnt,
                     w_cpu ? "sub" : "main", w_we ? "wr" : "rd", w_addr, w_be, w_din, core.shr_q);
            if (w_addr == watch_a[13:0]) begin w_seen_a <= !w_we; w_last_a <= core.shr_q; end
            else begin w_seen_b <= !w_we; w_last_b <= core.shr_q; end
        end
    end
end

// ---- +hold=<hex mask> +hold_from=N: hold P1 buttons from frame N
// (MRA J1 order: 4 gas 5 brake 6 start 7 coin 8 pause 9 test 10 service)
integer hold_mask = 0, hold_from = -1;
initial begin
    if (!$value$plusargs("hold=%h", hold_mask)) hold_mask = 0;
    if (!$value$plusargs("hold_from=%d", hold_from)) hold_from = -1;
end
wire [15:0] hold_now = (hold_from >= 0 && frame >= hold_from) ? hold_mask[15:0] : 16'd0;

// ---- +script=<file>: scripted inputs, one row per change, applied from
// that frame on: "frame buttons_hex stick_x stick_y throttle_hex"
// (buttons in the J1 order above, stick signed decimal, throttle 80 = idle)
integer scr_fd, scr_n = 0, scr_i = 0;
integer scr_f [0:255]; integer scr_b [0:255]; integer scr_sx [0:255]; integer scr_sy [0:255]; integer scr_t [0:255];
reg [15:0] scr_btn = 16'd0; reg signed [7:0] scr_x = 8'sd0, scr_y = 8'sd0; reg [7:0] scr_thr = 8'h80;
string scr_name;
initial begin
    if ($value$plusargs("script=%s", scr_name)) begin
        scr_fd = $fopen(scr_name, "r");
        while (scr_n < 256 && $fscanf(scr_fd, "%d %h %d %d %h", scr_f[scr_n], scr_b[scr_n], scr_sx[scr_n], scr_sy[scr_n], scr_t[scr_n]) == 5) scr_n = scr_n + 1;
        $fclose(scr_fd);
        $display("SCRIPT %s: %0d rows", scr_name, scr_n);
    end
end
always @(posedge clk_sys) begin
    if (scr_i < scr_n && frame >= scr_f[scr_i]) begin
        scr_btn <= scr_b[scr_i][15:0]; scr_x <= scr_sx[scr_i][7:0]; scr_y <= scr_sy[scr_i][7:0]; scr_thr <= scr_t[scr_i][7:0];
        $display("SCRIPT f=%0d buttons=%04x stick=%0d,%0d throttle=%02x", frame, scr_b[scr_i][15:0], scr_sx[scr_i], scr_sy[scr_i], scr_t[scr_i][7:0]);
        scr_i = scr_i + 1;
    end
end

// ---- +test_from=N: hold the test switch (service mode) from frame N on
integer test_from = -1;
initial begin if (!$value$plusargs("test_from=%d", test_from)) test_from = -1; end
wire test_sw = (test_from >= 0) && (frame >= test_from);
// ---- +coin=N: press Coin 1 for four frames from frame N (matches tools/mame_coin.lua)
integer coin_frame = -1;
initial begin if (!$value$plusargs("coin=%d", coin_frame)) coin_frame = -1; end
wire coin1 = (coin_frame >= 0) && (frame >= coin_frame) && (frame < coin_frame + 4);
// ---- +start=N (+start2..start5): press P1 Start for four frames from frame N
integer start_frame = -1, start2_frame = -1, start3_frame = -1, start4_frame = -1, start5_frame = -1;
initial begin
    if (!$value$plusargs("start=%d", start_frame))   start_frame = -1;
    if (!$value$plusargs("start2=%d", start2_frame)) start2_frame = -1;
    if (!$value$plusargs("start3=%d", start3_frame)) start3_frame = -1;
    if (!$value$plusargs("start4=%d", start4_frame)) start4_frame = -1;
    if (!$value$plusargs("start5=%d", start5_frame)) start5_frame = -1;
end
function automatic pressed(input integer at);
    pressed = (at >= 0) && (frame >= at) && (frame < at + 4);
endfunction
wire p1_start = pressed(start_frame) || pressed(start2_frame) || pressed(start3_frame) || pressed(start4_frame) || pressed(start5_frame);

// ---- +dumpframe=N: dump the video RAMs as frame N's last visible line
// ends (the state MAME's frame-end draw would see) plus the PPI video
// bits, for tools/board_check.py to render the model from and compare
// frame N's PPM. Per-consumer timing refines per milestone as the
// consumers arrive (the tilemap reads its registers per line; a static
// frame makes end-of-frame equivalent).
integer dumpframe = -1;
initial begin if (!$value$plusargs("dumpframe=%d", dumpframe)) dumpframe = -1; end
task automatic dump_ram(input string name, input integer words, input integer which);
    integer fd, k;
    fd = $fopen(name, "wb");
    for (k = 0; k < words; k = k + 1) begin
        case (which)
            0: $fwrite(fd, "%c%c", core.tileram.mem[k][7:0], core.tileram.mem[k][15:8]);
            1: $fwrite(fd, "%c%c", core.textram.mem[k][7:0], core.textram.mem[k][15:8]);
            2: $fwrite(fd, "%c%c", core.palette.mem[k][7:0], core.palette.mem[k][15:8]);
            3: $fwrite(fd, "%c%c", core.roadram.mem[k][7:0], core.roadram.mem[k][15:8]);
            4: $fwrite(fd, "%c%c", core.spriteram.mem[k][7:0], core.spriteram.mem[k][15:8]);
            default: $fwrite(fd, "%c%c", core.work_ram.mem[k][7:0], core.work_ram.mem[k][15:8]);
        endcase
    end
    $fclose(fd);
endtask
reg vb_dump_d;
integer fppi;
always @(posedge clk_sys) begin
    vb_dump_d <= vb;
    // the sprite renderer copies its list at line 260. The tb frame
    // counter increments at vb rise, so the vblank lines already carry
    // the next frame's number: the copy with frame == N feeds visible
    // frame N (per-consumer dump timing).
    if (dumpframe >= 0 && frame == dumpframe && core.line_start && core.vcnt == 9'd260)
        dump_ram("rtl_spriteram.bin", 1024, 4);
    if (dumpframe >= 0 && frame == dumpframe && vb && !vb_dump_d) begin
        dump_ram("rtl_tileram.bin", 8192, 0);
        dump_ram("rtl_textram.bin", 2048, 1);
        dump_ram("rtl_paletteram.bin", 2048, 2);
        dump_ram("rtl_roadram.bin", 2048, 3);
        dump_ram("rtl_workram.bin", 8192, 5);
        fppi = $fopen("rtl_ppi.txt", "w");
        $fwrite(fppi, "%0d\n%0d\n%0d\n", core.pb0_out, core.pc0_out, core.display_enable);
        $fclose(fppi);
        $display("dumped the video RAMs at the end of frame %0d", frame);
    end
end

// ---- sprite renderer budget: worst clocks per line and lines that were
// still rendering at the next line_start (cumulative), every 100 frames
reg [11:0] spr_worst;
reg vb_spr_d;
always @(posedge clk_sys) begin
    vb_spr_d <= vb;
    if (core.sprites.line_clocks > spr_worst) spr_worst <= core.sprites.line_clocks;
    if (vb && !vb_spr_d && frame != 0 && (frame % 100 == 0))
        $display("SPRLINE f=%0d worst clocks/line=%0d late lines so far=%0d", frame, spr_worst, core.sprites.late_lines);
end

// ---- sound path trace: the first few latch bytes, YM2203 and PCM
// register writes, and a once-per-second Z80 PC sample
integer snd_n = 0, ym_n = 0, pcmw_n = 0, ppi_n = 0, rd_n_cnt = 0, ppird_n = 0;
integer fstream;
initial fstream = $fopen("sndstream.txt", "w");
integer fzram;
always @(posedge clk_sys) begin
    if (frame == 23 && core.line_start && core.vcnt == 9'd100) begin
        fzram = $fopen("z80ram.bin", "wb");
        for (integer zk = 0; zk < 1024; zk = zk + 1)
            $fwrite(fzram, "%c", core.soundsys.ram[zk]);
        $fclose(fzram);
    end
end
integer fzpc;
reg [15:0] zpc_last;
initial begin fzpc = $fopen("z80pc.txt", "w"); zpc_last = 16'hFFFF; end
always @(posedge clk_sys) begin
    if (!core.soundsys.z_m1_n && !core.soundsys.z_mreq_n && !core.soundsys.z_rd_n
        && core.soundsys.z_addr != zpc_last && frame >= 9 && frame <= 24) begin
        zpc_last <= core.soundsys.z_addr;
        $fwrite(fzpc, "%04x\n", core.soundsys.z_addr);
    end
end
integer fym;
reg [7:0] ym_sel;
initial fym = $fopen("ymtrace.txt", "w");
always @(posedge clk_sys) begin
    if (core.soundsys.ym_access && !core.soundsys.ym_cs_d) begin
        if (core.soundsys.mem_wr) begin
            if (!core.soundsys.z_addr[0]) ym_sel <= core.soundsys.z_dout;
            else $fwrite(fym, "%0d W %02x %02x\n", frame, ym_sel, core.soundsys.z_dout);
        end
        else if (!core.soundsys.z_addr[0])
            $fwrite(fym, "%0d R %02x\n", frame, core.soundsys.ym_dout);
    end
end
integer fa_cnt = 0, fb_cnt = 0;
reg fa_d, fb_d;
always @(posedge clk_sys) begin
    fa_d <= core.soundsys.ym.u_jt12.flag_A;
    fb_d <= core.soundsys.ym.u_jt12.flag_B;
    if (core.soundsys.ym.u_jt12.flag_A && !fa_d) fa_cnt = fa_cnt + 1;
    if (core.soundsys.ym.u_jt12.flag_B && !fb_d) fb_cnt = fb_cnt + 1;
    if (vb && !vb_d && (frame % 60) == 0)
        $display("YMFLAGS f=%0d flagA_edges=%0d flagB_edges=%0d", frame, fa_cnt, fb_cnt);
end
always @(posedge clk_sys) begin
    if (core.m_cs && core.m_sel_ppi0 && core.m_wr && core.m_be[0] && core.m_addr[2:1] == 2'd0)
        $fwrite(fstream, "%0d %02x\n", frame, core.m_dout[7:0]);
end
integer lw_total = 0, lr_total = 0, drop_frames = 0, lw_f = 0, lr_f = 0;
always @(posedge clk_sys) begin
    if (core.m_cs && core.m_sel_ppi0 && core.m_wr && core.m_be[0] && core.m_addr[2:1] == 2'd0) begin
        lw_total = lw_total + 1; lw_f = lw_f + 1;
    end
    if (core.soundsys.snd_read) begin lr_total = lr_total + 1; lr_f = lr_f + 1; end
    if (vb && !vb_d) begin
        if (lw_f != lr_f && drop_frames < 10) begin
            drop_frames = drop_frames + 1;
            $display("SNDDROP f=%0d wrote=%0d read=%0d", frame, lw_f, lr_f);
        end
        lw_f = 0; lr_f = 0;
        if ((frame % 100) == 0) begin
            $display("SNDTOT f=%0d wrote=%0d read=%0d", frame, lw_total, lr_total);
            // the latch protocol's margin: the Z80 must read each byte before the
            // 68000's next write; worst write-to-read latency vs shortest write gap
            $display("SNDTIME f=%0d max_latency=%0d ns min_gap=%0d ns", frame, lat_max, gap_min);
            lat_max = 0; gap_min = 0;
        end
    end
end
// main.cpp does not advance $time, so count clk_sys cycles (20 ns each)
integer cyc = 0, lw_t = 0, lat_max = 0, gap_min = 0; reg lw_pending = 1'b0;
always @(posedge clk_sys) begin
    cyc = cyc + 1;
    if (core.m_cs && core.m_sel_ppi0 && core.m_wr && core.m_be[0] && core.m_addr[2:1] == 2'd0) begin
        if (lw_t != 0 && (gap_min == 0 || (cyc - lw_t) * 20 < gap_min)) gap_min = (cyc - lw_t) * 20;
        lw_t = cyc; lw_pending = 1'b1;
    end
    if (core.soundsys.snd_read && lw_pending) begin
        if ((cyc - lw_t) * 20 > lat_max) lat_max = (cyc - lw_t) * 20;
        lw_pending = 1'b0;
    end
end
always @(posedge clk_sys) begin
    if (core.m_cs && core.m_sel_ppi0 && core.m_wr && core.m_be[0] && ppi_n < 20) begin
        ppi_n = ppi_n + 1;
        $display("PPI0WR f=%0d reg=%0d d=%02x", frame, core.m_addr[2:1], core.m_dout[7:0]);
    end
end
reg obf_d;
always @(posedge clk_sys) begin
    obf_d <= core.snd_obf_n;
    if (!core.snd_obf_n && obf_d && snd_n < 32) begin
        snd_n = snd_n + 1;
        $display("SNDLATCH f=%0d %02x", frame, core.pa0_out);
    end
    if (core.soundsys.ym_access && !core.soundsys.ym_cs_d && core.soundsys.mem_wr && ym_n < 8) begin
        ym_n = ym_n + 1;
        $display("YMWR f=%0d a=%0d d=%02x", frame, core.soundsys.z_addr[0], core.soundsys.z_dout);
    end
    if (core.soundsys.pcm_access && !core.soundsys.pcm_cs_d && core.soundsys.mem_wr && pcmw_n < 8) begin
        pcmw_n = pcmw_n + 1;
        $display("PCMWR f=%0d a=%02x d=%02x", frame, core.soundsys.z_addr[7:0], core.soundsys.z_dout);
    end
    if (vb && !vb_d && (frame % 60) == 0)
        $display("Z80PC f=%0d pc=%04x rstn=%b", frame, core.soundsys.z_addr, core.soundsys.z_rst_n);
    if (core.soundsys.snd_read && rd_n_cnt < 12) begin
        rd_n_cnt = rd_n_cnt + 1;
        $display("SNDRD f=%0d byte=%02x obf=%b", frame, core.pa0_out, core.snd_obf_n);
    end
    if (core.m_cs && core.m_sel_ppi0 && !core.m_wr && core.m_be[0] && core.m_addr[2:1] == 2'd2 && ppird_n < 12) begin
        ppird_n = ppird_n + 1;
        $display("PPIC_RD f=%0d q=%02x", frame, core.ppi0_q);
    end
end

// ---- audio: 48 kHz stereo, raw little-endian 16-bit (audio.raw)
integer faud;
reg [31:0] aud_acc;      // 48000/50.3496e6 * 2^32 = 4094540: a 16-bit
                         // accumulator truncated this to 47.63 kHz and
                         // the 0.78% time warp capped the M5 envelope
                         // correlation at 0.88 no matter the mix
reg aud_ovf;
initial faud = $fopen("audio.raw", "wb");
// +auddump: the three mixer sources as separate mono 16-bit streams at
// the same 48 kHz ticks, for fitting the mix gains against MAME's wav
integer fcomp = 0;
initial if ($test$plusargs("auddump")) fcomp = $fopen("audcomp.raw", "wb");
wire [15:0] comp_fm  = core.soundsys.fm_snd;
wire [15:0] comp_pcm = core.soundsys.pcm_l;
wire [15:0] comp_ssg = {core.soundsys.ssg_sum, 6'd0};
always @(posedge clk_sys) begin
    if (!reset) begin
        {aud_ovf, aud_acc} <= {1'b0, aud_acc} + 33'd4094540;
        if (aud_ovf) $fwrite(faud, "%c%c%c%c", al[7:0], al[15:8], ar[7:0], ar[15:8]);
        if (aud_ovf && fcomp) $fwrite(fcomp, "%c%c%c%c%c%c",
            comp_fm[7:0], comp_fm[15:8], comp_ssg[7:0], comp_ssg[15:8],
            comp_pcm[7:0], comp_pcm[15:8]);
    end
end

// ---- frame dump: one PPM per frame (320x224). ppm_open is assigned
// blocking: the file opens on the same clock pixel (0,0) arrives (vblank
// falls as ce_pix delivers it), and the stub's zero-latency video showed
// the nonblocking version losing that pixel.
reg vb_d;
reg ppm_open;
string fname;
always @(posedge clk_sys) begin
    vb_d <= vb;
    if (vb && !vb_d) begin
        if (ppm_open) begin $fclose(fppm); ppm_open = 0; end
        frame <= frame + 1;
        if (frame + 1 == max_frames) $finish;
    end
    if (!vb && vb_d) begin
        $sformat(fname, "frame_%04d.ppm", frame);
        fppm = $fopen(fname, "wb");
        $fwrite(fppm, "P6\n320 224\n255\n");
        ppm_open = 1;
    end
    if (ce_pix && !hb && !vb && ppm_open) $fwrite(fppm, "%c%c%c", r, g, b);
end
endmodule
