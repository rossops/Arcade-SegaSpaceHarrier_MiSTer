//============================================================================
//  Sega Space Harrier / Hang-On — ioctl ROM loader
//  Index-0 stream (see sh_pkg OFF_*): [64-byte descriptor][main][sub][z80]
//  [pcm][mainops][sprite][tile][road][zoom][mcu][key]. The SDRAM regions
//  come first and land at (stream address - OFF_MAIN); the regions from
//  OFF_TILE on are handed to the core on the brm_* port for its BRAM ROMs.
//  Every region is padded to its slot except the last one a set populates.
//  Words arrive little-endian (WIDE=1); tools/pack_roms.py builds the stream
//  so each 16-bit word already holds the byte order the consumer expects.
//  rom_loaded releases the game reset only after the last SDRAM write of an
//  index-0 transfer has been acknowledged.
//============================================================================
import sh_pkg::*;

module sh_rom_loader (
    input             clk,
    input             rst,
    input             mem_ready,

    input             ioctl_download,
    input       [7:0] ioctl_index,
    input             ioctl_wr,
    input      [26:0] ioctl_addr,
    input      [15:0] ioctl_dout,
    output            ioctl_wait,

    output board_desc_t board_desc,

    output reg        sdr_wr_req,
    output reg [24:1] sdr_wr_addr,
    output reg [15:0] sdr_wr_din,
    output reg  [1:0] sdr_wr_be,
    input             sdr_wr_ack,

    // BRAM ROM regions (tile, road, zoom, MCU, key): one-clock write strobe,
    // address is the stream offset so the core routes by OFF_* range
    output reg        brm_wr,
    output reg [26:0] brm_addr,
    output reg [15:0] brm_din,

    output reg        rom_loaded
);

reg [7:0] desc_bytes [0:5];
reg       busy;
reg       index0_seen;
integer   i;

assign ioctl_wait = busy | ~mem_ready;

board_desc_t desc_r;
assign board_desc = desc_r;

always @(posedge clk) begin
    brm_wr <= 1'b0;
    if (rst) begin
        sdr_wr_req <= 1'b0; sdr_wr_addr <= '0; sdr_wr_din <= '0; sdr_wr_be <= '0;
        brm_addr <= '0; brm_din <= '0;
        rom_loaded <= 1'b0; busy <= 1'b0; index0_seen <= 1'b0;
        desc_r <= '0;
        for (i = 0; i < 6; i = i + 1) desc_bytes[i] <= 8'd0;
    end
    else begin
        if (sdr_wr_ack) begin
            sdr_wr_req <= 1'b0;
            busy       <= 1'b0;
        end

        if (mem_ready && ioctl_download && ioctl_wr && !busy && ioctl_index == 8'd0) begin
            if (ioctl_addr < OFF_MAIN) begin
                if (ioctl_addr[26:3] == 0) begin
                    if (ioctl_addr[2:0] < 3'd6) desc_bytes[ioctl_addr[2:0]]        <= ioctl_dout[7:0];
                    if (ioctl_addr[2:0] < 3'd5) desc_bytes[ioctl_addr[2:0] + 1'b1] <= ioctl_dout[15:8];
                end
                if (ioctl_addr == OFF_MAIN - 27'd2) begin
                    desc_r.game_id      <= desc_bytes[0];
                    desc_r.sharrier_vid <= desc_bytes[1][0];
                    desc_r.cpu10m       <= desc_bytes[1][1];
                    desc_r.has_mcu      <= desc_bytes[1][2];
                    desc_r.fd1089b      <= desc_bytes[1][3];
                    desc_r.fd1094       <= desc_bytes[1][4];
                    desc_r.ops_split    <= desc_bytes[1][5];
                    desc_r.sound_board  <= desc_bytes[2][1:0];
                    desc_r.spr_banks    <= desc_bytes[3];
                    desc_r.adc_reverse  <= desc_bytes[4];
                    desc_r.ana_mode     <= desc_bytes[5][2:0];
                end
            end
            else if (ioctl_addr < OFF_TILE) begin
                logic [26:0] ma;
                ma = ioctl_addr - OFF_MAIN;
                sdr_wr_req  <= 1'b1;
                busy        <= 1'b1;
                sdr_wr_addr <= ma[24:1];
                sdr_wr_din  <= ioctl_dout;
                sdr_wr_be   <= 2'b11;
                // the Z80 ROM also lands in the sound board's zero-wait
                // BRAM; the stream layout is unchanged (dual write)
                if (ioctl_addr >= OFF_Z80 && ioctl_addr < OFF_PCM) begin
                    brm_wr   <= 1'b1;
                    brm_addr <= ioctl_addr;
                    brm_din  <= ioctl_dout;
                end
            end
            else if (ioctl_addr < OFF_END) begin
                brm_wr   <= 1'b1;
                brm_addr <= ioctl_addr;
                brm_din  <= ioctl_dout;
            end
        end

        if (mem_ready && ioctl_download && ioctl_wr && ioctl_index == 8'd0 && ioctl_addr == 0) begin
            rom_loaded  <= 1'b0;
            index0_seen <= 1'b1;
        end
        if (mem_ready && !ioctl_download && index0_seen && !busy && !sdr_wr_req) begin
            rom_loaded  <= 1'b1;
            index0_seen <= 1'b0;
        end
    end
end
endmodule
