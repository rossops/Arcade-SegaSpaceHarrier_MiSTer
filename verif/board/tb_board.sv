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
    .clk_sys(clk_sys), .clk_ram(clk_ram), .reset(core_reset), .pause(hs_pause), .board_desc(desc),
    .hs_addr(hs_addr), .hs_din(hs_din), .hs_dout(hs_dout), .hs_write(hs_write), .hs_rd(hs_rd), .hs_wr(hs_wr),
    .p0_req(p0_req), .p0_addr(p0_addr), .p0_dout(p0_dout), .p0_ack(p0_ack),
    .p1_req(p1_req), .p1_addr(p1_addr), .p1_dout(p1_dout), .p1_ack(p1_ack),
    .p2_req(p2_req), .p2_addr(p2_addr), .p2_dout(p2_dout), .p2_ack(p2_ack),
    .p3_req(p3_req), .p3_addr(p3_addr), .p3_dout(p3_dout), .p3_ack(p3_ack),
    .p5_req(p5_req), .p5_addr(p5_addr), .p5_dout(p5_dout), .p5_ack(p5_ack),
    .p6_req(p6_req), .p6_addr(p6_addr), .p6_dout(p6_dout), .p6_ack(p6_ack),
    .brm_wr(brm_wr), .brm_addr(brm_addr), .brm_din(brm_din),
    .p1_buttons({5'd0, 1'b0, test_sw, 1'b0, coin1, p1_start, 6'd0} | hold_now | scr_btn),
    .stick_x(scr_x), .stick_y(scr_y), .throttle(scr_thr),
    .stick_mode(scr_dpad ? 2'd2 : 2'd0), .stick_hold(scr_hold), .cpu_boost(boost[1:0]), .ana_curve(2'd0), .ana_range(2'd0),
    .dsw_a(dsw_a), .dsw_b(dsw_b), .service(1'b0), .test(test_sw), .coin1(coin1), .coin2(1'b0),
    .r(r), .g(g), .b(b), .ce_vid(ce_pix), .hs(hs), .vs(vs), .hb(hb), .vb(vb),
    .audio_l(al), .audio_r(ar),
    .trace_main_addr(tm_addr), .trace_main_start(tm_start), .trace_main_fc(tm_fc),
    .trace_sub_addr(ts_addr), .trace_sub_start(ts_start), .trace_sub_fc(ts_fc),
    .dbg_snd_drop(dbg_snd_drop), .dbg_pcm_drop(dbg_pcm_drop), .dbg_z80_crash(dbg_z80_crash)
);

// ---- hiscore (+hiscore=<dir>): the emu top's sh_hiscore driven the way the
// HPS drives it. <dir>/hs_cfg.bin (ioctl index 5, header + entries) and
// <dir>/hs_dump.bin (the index 4 NVRAM file) stream through the 16-bit
// ioctl path with the core held in reset; at +hs_check=N (start of that
// frame) the work RAM is compared with the dump, then the OSD is "opened"
// (extraction, pauses the CPUs) and the table is read back as an upload.
string  hs_dir;
reg     hs_en, hs_loading;
initial begin hs_en = $value$plusargs("hiscore=%s", hs_dir); hs_loading = hs_en; end
wire    core_reset = reset | hs_loading;
reg         io_download = 1'b0, io_upload = 1'b0, io_wr = 1'b0, osd = 1'b0;
reg  [26:0] io_addr = 27'd0;
reg   [7:0] io_index = 8'd0;
reg  [15:0] io_dout = 16'd0;
wire [15:0] io_din;
wire        hs_pause, hs_upload_req, hs_configured, hs_write, hs_rd, hs_wr;
wire [23:0] hs_addr;
wire  [7:0] hs_din, hs_dout;
sh_hiscore hiscore (
    .clk(clk_sys), .reset(core_reset), .paused(hs_pause), .autosave(1'b1), .OSD_STATUS(osd),
    .ioctl_download(io_download), .ioctl_upload(io_upload), .ioctl_wr(io_wr), .ioctl_addr(io_addr),
    .ioctl_index(io_index), .ioctl_dout(io_dout), .ioctl_din(io_din),
    .upload_req(hs_upload_req), .configured(hs_configured),
    .ram_addr(hs_addr), .ram_din(hs_din), .ram_dout(hs_dout), .ram_write(hs_write), .ram_rd(hs_rd), .ram_wr(hs_wr),
    .pause_req(hs_pause)
);
reg [7:0] hs_cfg [0:255];
reg [7:0] hs_dump [0:2047];
integer hs_cfg_n = 0, hs_dump_n = 0, hs_check;
initial begin if (!$value$plusargs("hs_check=%d", hs_check)) hs_check = 60; end
// one ioctl download, 16-bit words, little-endian like hps_io WIDE
task automatic io_send(input [7:0] index, input integer n, input integer which);
    integer i;
    begin
        io_index = index; io_addr = 0;
        @(posedge clk_sys); io_download <= 1'b1;
        repeat (8) @(posedge clk_sys);
        for (i = 0; i < n; i = i + 2) begin
            io_addr <= i;
            io_dout <= which ? {hs_dump[i+1], hs_dump[i]} : {hs_cfg[i+1], hs_cfg[i]};
            io_wr   <= 1'b1;
            @(posedge clk_sys); io_wr <= 1'b0;
            repeat (7) @(posedge clk_sys);
        end
        io_download <= 1'b0;
        repeat (8) @(posedge clk_sys);
    end
endtask
// compare the work RAM with the dump, entry by entry (cfg: 16-byte header,
// then 4 address bytes, 2 length bytes, start, end per line; every line of
// this board family points into the main CPU's 16 KB work RAM)
task automatic hs_verify;
    integer e, i, n_ent, bad, total, len; reg [23:0] a; reg [7:0] exp, got; reg [15:0] w;
    begin
        n_ent = (hs_cfg_n - 16) / 8; total = 0; bad = 0;
        for (e = 0; e < n_ent; e = e + 1) begin
            a = {hs_cfg[16 + 8*e + 1], hs_cfg[16 + 8*e + 2], hs_cfg[16 + 8*e + 3]};
            len = {hs_cfg[16 + 8*e + 4], hs_cfg[16 + 8*e + 5]};
            for (i = 0; i < len; i = i + 1) begin
                w = core.work_ram.mem[a[13:1]];
                got = a[0] ? w[7:0] : w[15:8];
                exp = hs_dump[total];
                if (got != exp) begin bad = bad + 1; if (bad <= 8) $display("HISCORE mismatch %06x: ram %02x dump %02x", a, got, exp); end
                total = total + 1; a = a + 24'd1;
            end
        end
        $display("HISCORE restore check frame %0d: %0d/%0d bytes match -> %s", frame, total - bad, total, bad == 0 ? "PASS" : "FAIL");
    end
endtask
// read the table back the way arcade_nvm_save does (index 4 upload)
task automatic hs_upload_check;
    integer i, bad; reg [15:0] w;
    begin
        bad = 0; io_index = 8'd4; io_addr = 0; io_upload <= 1'b1;
        repeat (16) @(posedge clk_sys);
        for (i = 0; i < hs_dump_n; i = i + 2) begin
            io_addr <= i;
            repeat (12) @(posedge clk_sys);
            w = io_din;
            if (w[7:0] != hs_dump[i] || (i + 1 < hs_dump_n && w[15:8] != hs_dump[i+1])) begin
                bad = bad + 1;
                if (bad <= 8) $display("HISCORE upload mismatch @%0d: %04x vs %02x%02x", i, w, hs_dump[i+1], hs_dump[i]);
            end
        end
        io_upload <= 1'b0;
        $display("HISCORE upload check: %0d bad words -> %s", bad, bad == 0 ? "PASS" : "FAIL");
    end
endtask
integer hs_fd;
initial begin
    if (hs_en) begin
        hs_fd = $fopen({hs_dir, "/hs_cfg.bin"}, "rb");  hs_cfg_n  = $fread(hs_cfg, hs_fd);  $fclose(hs_fd);
        hs_fd = $fopen({hs_dir, "/hs_dump.bin"}, "rb"); hs_dump_n = $fread(hs_dump, hs_fd); $fclose(hs_fd);
        $display("HISCORE cfg %0d bytes, dump %0d bytes", hs_cfg_n, hs_dump_n);
        wait (!reset);
        repeat (20) @(posedge clk_sys);
        io_send(8'd5, hs_cfg_n, 0);
        io_send(8'd4, (hs_dump_n + 1) & ~1, 1);
        @(posedge clk_sys); hs_loading <= 1'b0;
        $display("HISCORE loaded, configured=%0d, core released at frame %0d", hs_configured, frame);
        wait (frame == hs_check);
        hs_verify;
        osd <= 1'b1; repeat (200) @(posedge clk_sys); osd <= 1'b0;
        repeat (20000) @(posedge clk_sys);
        $display("HISCORE after OSD open: upload_req seen=%0d", hs_upload_req);
        hs_upload_check;
    end
end

// the sound board's sticky debug flags, logged the moment they set
wire dbg_snd_drop, dbg_pcm_drop, dbg_z80_crash;
reg  z80_crash_d;
always @(posedge clk_sys) begin
    z80_crash_d <= dbg_z80_crash;
    if (core.snd_overwrite) $display("SNDOVR f=%0d line=%0d: latch byte %02x overwritten before the Z80 took it (z80 pc=%04x rst_n=%b nmi_pending=%b)",
                                     frame, core.vcnt, core.pa0_out, core.soundsys.z_addr, core.soundsys.z_rst_n, core.soundsys.z80_dbg[15]);
    if (core.pcm_tick_lost) $display("PCMLOST f=%0d: PCM tick while the engine was busy", frame);
    if (dbg_z80_crash && !z80_crash_d) $display("Z80CRASH f=%0d: opcode fetch at %04x", frame, core.soundsys.z_addr);
    // i8751 bring-up: every P1 write that changes the window or drives an IPL,
    // the first bus cycles, and each IRQ 4 delivered
    if (core.board_desc.has_mcu) begin
        // (the checksum loop toggles the window every read: log the first
        // few window changes, and every write that drives an IPL)
        if (core.mcu.p1_o != mcu_p1_d && (mcu_p1_n < 60 || core.mcu.p1_o[2:0] != 3'b111)) begin
            mcu_p1_n = mcu_p1_n + 1;
            $display("MCUP1 f=%0d line=%0d p1=%02x window=%02x ipl=%0d", frame, core.vcnt, core.mcu.p1_o,
                     {core.mcu.p1_o[6], 1'b0, core.mcu.p1_o[5:3]}, ~core.mcu.p1_o[2:0]);
        end
        mcu_p1_d <= core.mcu.p1_o;
        if (core.mcu_start && (mcu_n < 40 || frame >= mcu_trace_from)) begin
            mcu_n = mcu_n + 1;
            mcu_shown = 1'b1;
            $display("MCUBUS f=%0d %s %06x%s", frame, core.mcu_wr ? "wr" : "rd", core.mcu_baddr, core.mcu_wr ? $sformatf(" = %02x", core.mcu_bdout) : "");
        end
        else if (core.mcu_start) mcu_shown = 1'b0;
        // the returned byte only for accesses whose start line was shown (the
        // cap once let every checksum read through here: 100k lines a run)
        if (core.mcu_ack && !core.mcu_wr && mcu_shown) $display("MCUBUS    -> %02x", core.mcu_bdin);
        if (core.c_start && core.mcu_grant) $display("MCUBUS COLLISION f=%0d: the 68000 started a cycle under an MCU grant", frame);
        // the two masters' state, for deadlocks
        if (vb && !vb_d && (frame % 20) == 0)
            $display("MCUSTATE f=%0d busy=%b req=%b hold=%b grant=%b c_valid=%b c_addr=%06x mcu_pc=%04x p1=%02x ipl_l=%0d",
                     frame, core.mcu.busy, core.mcu_req, core.mcu_hold, core.mcu_grant, core.c_valid, {core.c_addr, 1'b0},
                     core.mcu.mcu.pc, core.mcu.p1_o, core.mcu_ipl_l);
        if (core.mcu_baddr == 24'h040385 && core.mcu_start && core.mcu_wr) $display("MCU40385 f=%0d write %02x", frame, core.mcu_bdout);
        if (core.mcu_drop && core.mcu_req && core.mcu_ack) $display("MCU40385 f=%0d write %02x dropped", frame, core.mcu_bdout);
        // the stick bytes the MCU hands the 68000 (its ADC loop, one pair a frame)
        if (core.mcu_start && core.mcu_wr && core.mcu_baddr == 24'h040492) mcu_stick_x = core.mcu_bdout;
        if (core.mcu_start && core.mcu_wr && core.mcu_baddr == 24'h040493) $display("MCUSTICK f=%0d x=%02x y=%02x", frame, mcu_stick_x, core.mcu_bdout);
        // the MCU's fallback mode (internal bit 22.0): it stops sampling the stick
        if (core.mcu.iram[8'h22][0] && !mcu_fallback_d) $display("MCUFALLBACK f=%0d: the MCU gave up on the heartbeat", frame);
        mcu_fallback_d <= core.mcu.iram[8'h22][0];
        // the 68000's side of the heartbeat (odd byte, low lane): written once at boot
        if (core.c_start && core.c_wr && core.c_addr == 23'h0201C2 && core.c_be[0]) $display("CPU40385 f=%0d line=%0d write %02x", frame, core.vcnt, core.c_dout[7:0]);
        // bus cycles per frame and the mean clocks from request to acknowledge
        if (core.mcu_req && !mcu_req_d) mcu_t0 = cyc;
        if (core.mcu_ack) begin mcu_cyc = mcu_cyc + 1; mcu_lat = mcu_lat + (cyc - mcu_t0); end
        mcu_req_d <= core.mcu_req;
        if (vb && !vb_d && (frame % 20) == 0) begin
            $display("MCUTOT f=%0d cycles=%0d mean_latency=%0d clk", frame, mcu_cyc, mcu_cyc == 0 ? 0 : mcu_lat / mcu_cyc);
            mcu_cyc = 0; mcu_lat = 0;
        end
    end
    // a Z80 reset with a latch byte still pending would leave /OBF low with
    // no NMI edge to come: log every reset with the handshake state
    z80_run_d <= core.z80_run;
    if (!core.z80_run && z80_run_d) $display("Z80RST f=%0d obf_n=%b (byte %02x pending=%b)", frame, core.snd_obf_n, core.pa0_out, ~core.snd_obf_n);
end
reg z80_run_d; reg [7:0] mcu_p1_d = 8'hFF; reg [7:0] mcu_stick_x = 8'd0; reg mcu_fallback_d = 1'b0;
integer mcu_n = 0, mcu_p1_n = 0, mcu_cyc = 0, mcu_lat = 0, mcu_t0 = 0, mcu_trace_from = -1; reg mcu_req_d = 0;
reg mcu_shown = 1'b0;
initial if (!$value$plusargs("mcutrace=%d", mcu_trace_from)) mcu_trace_from = -1;

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

// +boost=N: the M11 CPU speed option (0 PCB, 1 12.5 MHz, 2 15 MHz, 3 20 MHz)
integer boost = 0;
initial if (!$value$plusargs("boost=%d", boost)) boost = 0;
// ---- update cadence: does sprite RAM change between consecutive frames? The
// game is vblank-synced and drops a frame when its 68000 overruns; MAME's
// zero-wait 68000 keeps every frame once the race is under way (M11)
reg [31:0] cad_hash = 0, cad_prev = 0;
integer    cad_i, cad_upd = 0, cad_tot = 0, cad_last = -1;
reg [99:0] cad_hist = 0;
always @(posedge clk_sys) begin
    if (core.vcnt == 0 && core.hcnt == 0 && frame != cad_last) begin
        cad_last = frame;
        cad_hash = 0;
        for (cad_i = 0; cad_i < 2048; cad_i = cad_i + 1) cad_hash = cad_hash * 31 + {16'd0, core.spriteram.mem[cad_i]};
        if (frame > 1) begin
            cad_tot = cad_tot + 1;
            cad_hist = {cad_hist[98:0], cad_hash != cad_prev};
            if (cad_hash != cad_prev) cad_upd = cad_upd + 1;
        end
        cad_prev = cad_hash;
        if (frame % 100 == 0) begin
            $display("CADENCE f=%0d updated %0d of %0d frames (last 100: %b)", frame, cad_upd, cad_tot, cad_hist);
            cad_upd = 0; cad_tot = 0;
        end
    end
end
// ---- where the 68000s wait (M11): per 100 frames, clocks each CPU has a bus
// cycle open, and of those how many are waits on the ROM cache and on the
// shared RAM arbiter. BUSWAIT lines.
integer bw_m_cyc = 0, bw_m_rom = 0, bw_m_shr = 0, bw_s_cyc = 0, bw_s_rom = 0, bw_s_shr = 0, bw_last = -1;
always @(posedge clk_sys) begin
    if (core.c_valid) begin
        bw_m_cyc = bw_m_cyc + 1;
        if (core.m_sel_rom && core.m_rd && !core.m_rom_ack) bw_m_rom = bw_m_rom + 1;
        if (core.m_sel_shared && !core.m_shr_ack) bw_m_shr = bw_m_shr + 1;
    end
    if (core.s_valid) begin
        bw_s_cyc = bw_s_cyc + 1;
        if (core.s_sel_rom && core.s_rd && !core.s_rom_ack) bw_s_rom = bw_s_rom + 1;
        if (core.s_sel_shared && !core.s_shr_ack) bw_s_shr = bw_s_shr + 1;
    end
    if (frame % 100 == 0 && frame != bw_last) begin
        bw_last = frame;
        $display("BUSWAIT f=%0d main: cycle-open %0d rom-wait %0d shared-wait %0d | sub: cycle-open %0d rom-wait %0d shared-wait %0d (of %0d clocks in 100 frames)",
                 frame, bw_m_cyc, bw_m_rom, bw_m_shr, bw_s_cyc, bw_s_rom, bw_s_shr, 100 * 400 * 262 * 8);
        bw_m_cyc = 0; bw_m_rom = 0; bw_m_shr = 0; bw_s_cyc = 0; bw_s_rom = 0; bw_s_shr = 0;
    end
end
// ---- +pcsample=F: both 68000s' instruction addresses sampled every 32 clocks
// through frames F..F+29 (pcsample_main.txt, pcsample_sub.txt), for a histogram
// of where a CPU spends a dropped frame (M11)
integer pcs_from = -1, pcs_n = 0, fpm = 0, fps = 0;
initial begin
    if ($value$plusargs("pcsample=%d", pcs_from)) begin fpm = $fopen("pcsample_main.txt", "w"); fps = $fopen("pcsample_sub.txt", "w"); end
end
always @(posedge clk_sys) begin
    if (pcs_from >= 0 && frame >= pcs_from && frame < pcs_from + 30) begin
        pcs_n = pcs_n + 1;
        if (pcs_n[4:0] == 0) begin $fwrite(fpm, "%06x\n", {mt_a_ir, 1'b0}); $fwrite(fps, "%06x\n", {st_a_ir, 1'b0}); end
    end
end
// +stick_hold: the OSD "re-centering off" (held stick); +dpad: analog+d-pad mode
reg scr_hold = 1'b0, scr_dpad = 1'b0;
initial begin
    if ($test$plusargs("stick_hold")) scr_hold = 1'b1;
    if ($test$plusargs("dpad")) scr_dpad = 1'b1;
end
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
        dump_ram("rtl_spriteram.bin", core.board_desc.sharrier_vid ? 2048 : 1024, 4);
    if (dumpframe >= 0 && frame == dumpframe && vb && !vb_dump_d) begin
        dump_ram("rtl_tileram.bin", core.board_desc.sharrier_vid ? 16384 : 8192, 0);
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
integer latch_from = -1;   // +latchlog=F: every latch byte in frames F..F+39 (the first 32 always)
initial if (!$value$plusargs("latchlog=%d", latch_from)) latch_from = -1;
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
    if (!core.snd_obf_n && obf_d && (snd_n < 32 || (frame >= latch_from && frame < latch_from + 40))) begin
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

// ---- the Z80's YM accesses (the 2203 at D000/D001, the 2151 on ports 00/01):
// the first 80 in full, then totals every 100 frames
integer ymt_n = 0, ym_wr = 0, ym_rd = 0, ymt_last = -1;
wire ym03_go = core.soundsys.ym_access && !core.soundsys.ym_cs_d;
wire ym51_go = core.soundsys.io_ym && !core.soundsys.ym51_cs_d;
always @(posedge clk_sys) begin
    if (ym03_go || ym51_go) begin
        if (core.soundsys.mem_wr || (ym51_go && !core.soundsys.z_wr_n)) ym_wr = ym_wr + 1; else ym_rd = ym_rd + 1;
        if (ymt_n < 80) begin
            ymt_n = ymt_n + 1;
            $display("YM f=%0d %s %s a=%0d d=%02x", frame, ym03_go ? "2203" : "2151",
                     (core.soundsys.mem_wr || !core.soundsys.z_wr_n) ? "wr" : "rd", core.soundsys.z_addr[0],
                     (core.soundsys.mem_wr || !core.soundsys.z_wr_n) ? core.soundsys.z_dout : core.soundsys.z_din);
        end
    end
    if (frame % 100 == 0 && frame != ymt_last) begin
        ymt_last = frame;
        $display("YMTOT f=%0d wr=%0d rd=%0d", frame, ym_wr, ym_rd);
    end
end

// ---- YM2203 register decode: key-on writes (reg 28) in full, and every
// 100 frames the timer/prescaler view and the chip's output peaks
reg  [7:0] ym_alat = 8'd0;
integer    ym_kon = 0, ym_fm_pk = 0, ym_ssg_pk = 0, ymr_last = -1;
wire signed [15:0] ym_fm_now = core.soundsys.fm_snd;
always @(posedge clk_sys) begin
    if (ym03_go && core.soundsys.mem_wr) begin
        if (!core.soundsys.z_addr[0]) ym_alat = core.soundsys.z_dout;
        else begin
            if (ym_alat == 8'h28) begin
                ym_kon = ym_kon + 1;
                if (ym_kon <= 40) $display("YMKON f=%0d ch=%0d ops=%01x", frame, core.soundsys.z_dout[1:0], core.soundsys.z_dout[7:4]);
            end
            if (ym_alat == 8'h27 || ym_alat == 8'h22) $display("YMREG f=%0d reg=%02x val=%02x", frame, ym_alat, core.soundsys.z_dout);
        end
    end
    if ((ym_fm_now > 0 ? ym_fm_now : -ym_fm_now) > ym_fm_pk) ym_fm_pk = (ym_fm_now > 0 ? ym_fm_now : -ym_fm_now);
    if (core.soundsys.psg_a > ym_ssg_pk) ym_ssg_pk = core.soundsys.psg_a;
    if (frame % 100 == 0 && frame != ymr_last) begin
        ymr_last = frame;
        $display("YMSTATE f=%0d keyons=%0d debug_view=%02x fm_peak=%0d ssg_peak=%0d", frame, ym_kon, core.soundsys.ym.u_jt12.debug_view, ym_fm_pk, ym_ssg_pk);
        ym_fm_pk = 0; ym_ssg_pk = 0;
    end
end

// ---- +pcmdump: the 315-5218's 256 register bytes at frames 800 and 1000,
// in the format of tools' MAME Lua dump (scratchpad pcmdump.lua) for a diff
integer pcmd_last = -1, pcmd_i, pcmd_f = 1000;
initial if (!$value$plusargs("pcmdumpf=%d", pcmd_f)) pcmd_f = 1000;   // +pcmdumpf=N: the second dump frame (800 is always dumped)
always @(posedge clk_sys) begin
    if ($test$plusargs("pcmdump") && (frame == 800 || frame == pcmd_f) && frame != pcmd_last) begin
        pcmd_last = frame;
        $write("PCMREGS f=%0d", frame);
        for (pcmd_i = 0; pcmd_i < 256; pcmd_i = pcmd_i + 1) $write(" %02x", core.soundsys.pcm.regs[pcmd_i]);
        $write("\n");
    end
end

// ---- +pcmtrace=CH: that channel's fetch address and byte at every tick of
// frames 1000-1001, to diff against the Python model from the frame-1000 dump
integer pcmt_ch = -1;
initial if (!$value$plusargs("pcmtrace=%d", pcmt_ch)) pcmt_ch = -1;
always @(posedge clk_sys) begin
    if (pcmt_ch >= 0 && (frame == 1000 || frame == 1001) && core.soundsys.pcm.es == 3'd5 && core.soundsys.pcm.ch == pcmt_ch[3:0])
        $display("PCMS f=%0d a=%06x rom_addr=%06x odd=%0d byte=%02x", frame, core.soundsys.pcm.a, {core.soundsys.pcm.rom_addr, 1'b0}, core.soundsys.pcm.rom_odd,
                 core.soundsys.pcm.rom_byte);
end

// ---- +pcmwlog: every Z80 write to the 315-5218 in frames 1000-1001 with
// the screen line, to set beside MAME's Lua log of the same
integer pcmw_f = 1000;
initial if (!$value$plusargs("pcmwlogf=%d", pcmw_f)) pcmw_f = 1000;   // +pcmwlogf=N: the two frames logged are N and N+1
always @(posedge clk_sys) begin
    if ($test$plusargs("pcmwlog") && (frame == pcmw_f || frame == pcmw_f + 1) && core.soundsys.pcm.cs && core.soundsys.pcm.we)
        $display("PCMW f=%0d line=%0d off=%02x data=%02x es=%0d ch=%0d", frame, core.vcnt, core.soundsys.pcm.addr, core.soundsys.pcm.din, core.soundsys.pcm.es, core.soundsys.pcm.ch);
end

// ---- +keystream: the FD1089B key image streamed through the core's loader
// port (brm_*) after reset, the way the MiSTer delivers it, instead of the
// $readmemh shortcut (+keyrom). The first Enduro Racer hardware build boot-
// looped because the core indexed that write with the raw stream offset;
// the bench had only ever used the shortcut. Every keyed set now takes this
// path in the gate.
reg        brm_wr = 1'b0;
reg [26:0] brm_addr = 27'd0;
reg [15:0] brm_din = 16'd0;
reg [15:0] key_img [0:4095];
integer    ks_i;
initial begin
    if ($test$plusargs("keystream")) begin
        $readmemh("key.hex", key_img);
        @(negedge reset);
        repeat (20) @(posedge clk_sys);
        for (ks_i = 0; ks_i < 4096; ks_i = ks_i + 1) begin
            @(posedge clk_sys);
            brm_wr <= 1'b1; brm_addr <= OFF_KEY + 27'(2 * ks_i); brm_din <= key_img[ks_i];
        end
        @(posedge clk_sys);
        brm_wr <= 1'b0;
        $display("KEYSTREAM: 4096 words delivered through the loader port");
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
wire [15:0] comp_fm  = core.soundsys.b2151 ? core.soundsys.ym51_l : core.soundsys.fm_snd;   // the board's FM chip
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
