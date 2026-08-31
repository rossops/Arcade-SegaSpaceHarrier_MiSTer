//============================================================================
//  Sega Space Harrier / Hang-On for MiSTer — shared package
//  Board constants, SDRAM map, ioctl stream layout and the per-game
//  descriptor that the MRA prepends to the ROM stream. docs/DESIGN.md ("ROM
//  stream and descriptor") is the reference; tools/romsets.py holds the same
//  slots and tools/pack_roms.py the same descriptor bytes.
//============================================================================
package sh_pkg;

    // ---- board clocks (Hz) -------------------------------------------------
    // clk_sys is twice the PCB's 25.1748 MHz master, so pixel (/8), the
    // Hang-On 68000s (/8) and the ADC (/48) are exact enables. The 10 MHz
    // CPUs (sharrier/enduror/shangon*), the 4 MHz Z80/FM chips and the 8 MHz
    // PCM tick come from fractional (accumulator) enables (DESIGN open q 5).
    localparam int PCB_MASTER_HZ = 25_174_800;
    localparam int PCB_CPU10_HZ  = 10_000_000;
    localparam int PCB_SOUND_HZ  =  8_000_000;   // Z80 = /2, YM2203/YM2151 = /2, i8751 = /1
    localparam int CLK_SYS_HZ    = 50_349_600;   // == 2 x PCB_MASTER_HZ (exact)
    localparam int CLK_RAM_HZ    = 100_699_200;

    // ---- video timing: 400 x 262 at clk_sys/8 = 6.2937 MHz, 320 x 224 -----
    // MAME 0.289 set_raw(25.1748 MHz/4, 400, 0, 320, 262, 0, 224) — measured,
    // unlike the Y Board's set_size placeholder.
    localparam int H_TOTAL   = 400;
    localparam int H_ACTIVE  = 320;
    localparam int V_TOTAL   = 262;
    localparam int V_ACTIVE  = 224;
    localparam int VBLANK_LINE = 224;   // IRQ4 (vblank) asserted during this line
    localparam int LATCH_LINE  = 261;   // end-of-frame pulse (bench framing; the
                                        // HANGON tilemap latches nothing itself)

    // ---- SDRAM byte map (25-bit byte address), contiguous slots -----------
    // Slots sized to the largest set. MAINOPS holds the decrypted-opcode
    // image of the FD1089B and opcode-split bootleg sets; other sets leave it
    // zero and fetch opcodes from SDR_MAIN_BASE (descriptor ops_split flag).
    localparam [24:0] SDR_MAIN_BASE    = 25'h000_0000;  // 256 KB, main 68000
    localparam [24:0] SDR_SUB_BASE     = 25'h004_0000;  // 256 KB, sub 68000 (also the main CPU's C00000 window)
    localparam [24:0] SDR_Z80_BASE     = 25'h008_0000;  //  64 KB
    localparam [24:0] SDR_PCM_BASE     = 25'h009_0000;  // 128 KB, 315-5218 samples
    localparam [24:0] SDR_MAINOPS_BASE = 25'h00B_0000;  // 256 KB, main opcode image
    localparam [24:0] SDR_SPR_BASE     = 25'h00F_0000;  //   1 MB, sprite ROM
    localparam [24:0] SDR_END          = 25'h01F_0000;

    // ---- ioctl index-0 stream layout (byte offsets) -----------------------
    // The SDRAM regions come first in slot order (stream offset = SDRAM
    // offset + OFF_MAIN, a plain copy), then the loader-filled BRAM regions:
    // tile ROM, road ROM, zoom PROM, i8751 ROM, FD1089B key. Every region is
    // padded to its slot except the last one a set populates.
    localparam [26:0] OFF_DESC    = 27'h000_0000;   // 64-byte descriptor
    localparam [26:0] OFF_MAIN    = 27'h000_0040;
    localparam [26:0] OFF_SUB     = OFF_MAIN    + 27'h04_0000;
    localparam [26:0] OFF_Z80     = OFF_SUB     + 27'h04_0000;
    localparam [26:0] OFF_PCM     = OFF_Z80     + 27'h01_0000;
    localparam [26:0] OFF_MAINOPS = OFF_PCM     + 27'h02_0000;
    localparam [26:0] OFF_SPR     = OFF_MAINOPS + 27'h04_0000;
    localparam [26:0] OFF_TILE    = OFF_SPR     + 27'h10_0000;
    localparam [26:0] OFF_ROAD    = OFF_TILE    + 27'h01_8000;
    localparam [26:0] OFF_ZOOM    = OFF_ROAD    + 27'h00_8000;
    localparam [26:0] OFF_MCU     = OFF_ZOOM    + 27'h00_2000;
    localparam [26:0] OFF_KEY     = OFF_MCU     + 27'h00_1000;
    localparam [26:0] OFF_END     = OFF_KEY     + 27'h00_2000;

    // ---- per-game descriptor (first 64 bytes of the stream) ----------------
    //  byte 0: game id (0 hangon, 1 sharrier, 2 enduror, 3 shangon conversion)
    //  byte 1: flags: bit0 sharrier map+video (memory map, sprite/road/mixer
    //                      variants, 2-bank palette; 0 = hangon versions)
    //                 bit1 CPUs at 10 MHz (0 = 25.1748/4)
    //                 bit2 i8751 present (sharrier)
    //                 bit3 FD1089B on the main CPU (enduror)
    //                 bit4 FD1094 on the sub CPU (shangonro/ho, M9)
    //                 bit5 fetch main opcodes from the MAINOPS slot
    //  byte 2: sound board: 0 YM2203 + PCM at 8 MHz; 1 YM2151 + PCM at 4 MHz;
    //          2 = 2x YM2203 + PCM at 4 MHz (endurob2)
    //  byte 3: sprite ROM bank count (64 KB banks on hangon-style sets,
    //          128 KB on sharrier-style; bank % count wrap)
    //  byte 4: ADC reverse mask (bit n: channel n reads 0x100 - value)
    //  byte 5: bits 2:0 analog mode (0 hangon driving, 1 sharrier stick,
    //          2 enduror bike)
    //  bytes 6..63: reserved (0)
    typedef struct packed {
        logic [7:0] game_id;
        logic       sharrier_vid;
        logic       cpu10m;
        logic       has_mcu;
        logic       fd1089b;
        logic       fd1094;
        logic       ops_split;
        logic [1:0] sound_board;
        logic [7:0] spr_banks;
        logic [7:0] adc_reverse;
        logic [2:0] ana_mode;
    } board_desc_t;

endpackage
