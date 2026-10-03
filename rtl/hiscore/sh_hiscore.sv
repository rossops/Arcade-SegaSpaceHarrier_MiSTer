//============================================================================
//  Hiscore glue: JimmyStones' hiscore.v behind the framework's 16-bit ioctl.
//
//  This board has no battery RAM, so every game refills its score table from
//  ROM at boot and the MRA's <nvram index="4"> is the table alone, the way
//  the X Board does it (the Y Board shares its file with a backup RAM).
//  hps_io runs WIDE here (one 16-bit word per ioctl_wr, addresses step by
//  2), while hiscore.v parses a byte stream. Each incoming word is replayed
//  as two byte writes (low byte = even address, as the DIP loader reads
//  them), and on upload the two bytes of the requested word are fetched in
//  turn from the module's score buffer. The game-RAM side is byte wide with
//  full 68000 addresses; the core decodes them like the CPU would.
//============================================================================
module sh_hiscore #(
    parameter CONFIG_INDEX = 5,   // MRA <rom index="5">: header + hiscore.dat entries
    parameter DUMP_INDEX   = 4    // MRA <nvram index="4">: the saved scores
) (
    input         clk,
    input         reset,
    input         paused,           // the core really is paused (from the pause module)
    input         autosave,
    input         OSD_STATUS,
    input         ioctl_download,
    input         ioctl_upload,
    input         ioctl_wr,
    input  [26:0] ioctl_addr,
    input   [7:0] ioctl_index,
    input  [15:0] ioctl_dout,
    output [15:0] ioctl_din,        // valid while an index DUMP_INDEX upload runs
    output        upload_req,
    output        configured,       // the MRA carried a hiscore table
    // game RAM, byte wide, CPU addresses; read data one clock after the address
    output [23:0] ram_addr,
    output  [7:0] ram_din,          // to game RAM
    input   [7:0] ram_dout,         // from game RAM
    output        ram_write,        // write strobe (with ram_wr)
    output        ram_rd,           // hiscore wants the read port
    output        ram_wr,           // hiscore wants the write port
    output        pause_req
);

wire hs_index = (ioctl_index == CONFIG_INDEX[7:0]) || (ioctl_index == DUMP_INDEX[7:0]);

// ---- download: one 16-bit word becomes two byte writes on consecutive clocks
reg        b_wr, pend;
reg [24:0] b_addr, pend_addr;
reg  [7:0] b_data, pend_data;
reg        dl_d;
always @(posedge clk) begin
    dl_d <= ioctl_download;
    b_wr <= 1'b0;
    if (ioctl_download && !dl_d) begin
        b_addr <= 25'd0;            // a fresh stream starts at its header
        pend   <= 1'b0;
    end
    if (ioctl_download && ioctl_wr && hs_index) begin
        b_wr      <= 1'b1;
        b_addr    <= ioctl_addr[24:0];
        b_data    <= ioctl_dout[7:0];
        pend      <= 1'b1;
        pend_addr <= ioctl_addr[24:0] + 25'd1;
        pend_data <= ioctl_dout[15:8];
    end
    else if (pend) begin
        b_wr   <= 1'b1;
        b_addr <= pend_addr;
        b_data <= pend_data;
        pend   <= 1'b0;
    end
end

// ---- upload: alternate the two byte addresses of the word the host asked
// for; hiscore.v returns a byte two clocks after it sees the address
// (address register, then the buffer RAM), so the phase is delayed to match.
wire        uploading = ioctl_upload && (ioctl_index == DUMP_INDEX[7:0]);
wire  [7:0] data_to_hps;
reg         phase, ph_d1, ph_d2;
reg  [15:0] din;
always @(posedge clk) begin
    phase <= ~phase;
    ph_d1 <= phase;
    ph_d2 <= ph_d1;
    if (ph_d2) din[15:8] <= data_to_hps;
    else       din[7:0]  <= data_to_hps;
end
assign ioctl_din = din;

wire [24:0] hs_ioctl_addr = uploading ? {ioctl_addr[24:1], phase} : b_addr;

hiscore #(
    .HS_ADDRESSWIDTH(24),
    .HS_SCOREWIDTH(11),           // 2 KB buffer: Hang-On's table is 1188 bytes, Enduro Racer's 1200
    .HS_CONFIGINDEX(CONFIG_INDEX),
    .HS_DUMPINDEX(DUMP_INDEX),
    .CFG_ADDRESSWIDTH(3),         // up to 8 hiscore.dat lines
    .CFG_LENGTHWIDTH(2)           // two-byte entry lengths (the tables run to 0x4A0)
) hs (
    .clk(clk),
    .paused(paused),
    .reset(reset),
    .autosave(autosave),
    .ioctl_upload(ioctl_upload),
    .ioctl_upload_req(upload_req),
    .ioctl_download(ioctl_download),
    .ioctl_wr(b_wr),
    .ioctl_addr(hs_ioctl_addr),
    .ioctl_index(ioctl_index),
    .OSD_STATUS(OSD_STATUS),
    .data_from_hps(b_data),
    .data_from_ram(ram_dout),
    .ram_address(ram_addr),
    .data_to_hps(data_to_hps),
    .data_to_ram(ram_din),
    .ram_write(ram_write),
    .ram_intent_read(ram_rd),
    .ram_intent_write(ram_wr),
    .pause_cpu(pause_req),
    .configured(configured)
);

endmodule
