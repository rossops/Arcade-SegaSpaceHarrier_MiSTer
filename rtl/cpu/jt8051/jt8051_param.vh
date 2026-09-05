/* SPDX-FileCopyrightText: 2026 Jose Tejada Gomez
 * SPDX-License-Identifier: GPL-3.0-or-later
 * Date: 03-09-2026 */

// Control signals
localparam [2:0] // ADDR
        BIT_ADDR = 3'd1,
     DIRECT_ADDR = 3'd2,
         EA_ADDR = 3'd3,
        REG_ADDR = 3'd4,
         RI_ADDR = 3'd5,
      STACK_ADDR = 3'd6,
     STACKP_ADDR = 3'd7;

localparam [4:0] // ALU
         ADD_ALU = 5'd1,
        ADDC_ALU = 5'd2,
         AND_ALU = 5'd3,
         CMP_ALU = 5'd4,
         CPL_ALU = 5'd5,
          DA_ALU = 5'd6,
         DEC_ALU = 5'd7,
         DIV_ALU = 5'd8,
         INC_ALU = 5'd9,
         MUL_ALU = 5'd10,
          OR_ALU = 5'd11,
          RL_ALU = 5'd12,
         RLC_ALU = 5'd13,
          RR_ALU = 5'd14,
         RRC_ALU = 5'd15,
        SUBB_ALU = 5'd16,
        SWAP_ALU = 5'd17,
        XCHD_ALU = 5'd18,
         XOR_ALU = 5'd19;

localparam [1:0] // CODE
        APC_CODE = 2'd1,
      DPTRA_CODE = 2'd2,
         PC_CODE = 2'd3;

localparam [3:0] // COND
        BIT_COND = 4'd1,
          C_COND = 4'd2,
       NBIT_COND = 4'd3,
         NC_COND = 4'd4,
        NEQ_COND = 4'd5,
         NZ_COND = 4'd6,
      NZALU_COND = 4'd7,
          Z_COND = 4'd8;

localparam [4:0] // DST
           A_DST = 5'd1,
           B_DST = 5'd2,
         BIT_DST = 5'd3,
        BITC_DST = 5'd4,
       CARRY_DST = 5'd5,
      DIRECT_DST = 5'd6,
        DPTR_DST = 5'd7,
       DPTRI_DST = 5'd8,
          EA_DST = 5'd9,
         EAW_DST = 5'd10,
          IR_DST = 5'd11,
         LHS_DST = 5'd12,
          MD_DST = 5'd13,
         OP1_DST = 5'd14,
         OP2_DST = 5'd15,
         RHS_DST = 5'd16,
          RI_DST = 5'd17,
          RN_DST = 5'd18,
           X_DST = 5'd19;

localparam [2:0] // FLAG
        ADD_FLAG = 3'd1,
        CMP_FLAG = 3'd2,
        CYA_FLAG = 3'd3,
        MUL_FLAG = 3'd4;

localparam [5:0] // JSR
         ABS_JSR = 6'd1,
       ACALL_JSR = 6'd2,
       ADPTR_JSR = 6'd3,
        AJMP_JSR = 6'd4,
         APC_JSR = 6'd5,
         BIT_JSR = 6'd6,
        BITL_JSR = 6'd7,
      BITREL_JSR = 6'd8,
     BITRELL_JSR = 6'd9,
       CJNED_JSR = 6'd10,
       CJNEI_JSR = 6'd11,
      CJNERI_JSR = 6'd12,
      CJNERN_JSR = 6'd13,
     DDIRECT_JSR = 6'd14,
        DIMM_JSR = 6'd15,
      DIRECT_JSR = 6'd16,
    DIRECTIMML_JSR = 6'd17,
     DIRECTL_JSR = 6'd18,
    DIRECTRELL_JSR = 6'd19,
    DIRECTRI_JSR = 6'd20,
       FETCH_JSR = 6'd21,
         IMM_JSR = 6'd22,
    ISRFETCH_JSR = 6'd23,
        NBIT_JSR = 6'd24,
        NONE_JSR = 6'd25,
         REL_JSR = 6'd26,
         RET_JSR = 6'd27,
          RI_JSR = 6'd28,
    RIDIRECT_JSR = 6'd29,
       RIIMM_JSR = 6'd30,
          RN_JSR = 6'd31,
    RNDIRECT_JSR = 6'd32,
       RNREL_JSR = 6'd33,
       XDPTR_JSR = 6'd34,
         XRI_JSR = 6'd35;

localparam [3:0] // PC
        ABS11_PC = 4'd1,
        ABS16_PC = 4'd2,
        DPTRA_PC = 4'd3,
          INC_PC = 4'd4,
          IRQ_PC = 4'd5,
          REL_PC = 4'd6,
        REL2C_PC = 4'd7,
         RELC_PC = 4'd8,
          RET_PC = 4'd9;

localparam [4:0] // SRC
           A_SRC = 5'd1,
         ABS_SRC = 5'd2,
         ALU_SRC = 5'd3,
         AUX_SRC = 5'd4,
           B_SRC = 5'd5,
         BIT_SRC = 5'd6,
        BITQ_SRC = 5'd7,
       CARRY_SRC = 5'd8,
        CODE_SRC = 5'd9,
      DIRECT_SRC = 5'd10,
        DPTR_SRC = 5'd11,
     ISRPCHI_SRC = 5'd12,
     ISRPCLO_SRC = 5'd13,
          MD_SRC = 5'd14,
        NBIT_SRC = 5'd15,
         ONE_SRC = 5'd16,
         OP1_SRC = 5'd17,
         OP2_SRC = 5'd18,
        PCHI_SRC = 5'd19,
        PCLO_SRC = 5'd20,
         RAM_SRC = 5'd21,
           X_SRC = 5'd22,
        ZERO_SRC = 5'd23;

localparam [1:0] // X
          DPTR_X = 2'd1,
            RI_X = 2'd2;

localparam [1:0] // XWR
         OFF_XWR = 2'd1,
          ON_XWR = 2'd2;

// entry points for ucode procedures
localparam ABS_SEQA             = 15'h4180;
localparam ACALL_SEQA           = 15'h4200;
localparam ADPTR_SEQA           = 15'h4580;
localparam AJMP_SEQA            = 15'h41C0;
localparam APC_SEQA             = 15'h4540;
localparam BIT_SEQA             = 15'h4440;
localparam BITL_SEQA            = 15'h4480;
localparam BITREL_SEQA          = 15'h44C0;
localparam BITRELL_SEQA         = 15'h4500;
localparam CJNED_SEQA           = 15'h47C0;
localparam CJNEI_SEQA           = 15'h4780;
localparam CJNERI_SEQA          = 15'h4800;
localparam CJNERN_SEQA          = 15'h4840;
localparam DDIRECT_SEQA         = 15'h4680;
localparam DIMM_SEQA            = 15'h42C0;
localparam DIRECT_SEQA          = 15'h4240;
localparam DIRECTIMM_SEQA       = 15'h4300;
localparam DIRECTIMML_SEQA      = 15'h4340;
localparam DIRECTL_SEQA         = 15'h4280;
localparam DIRECTREL_SEQA       = 15'h4880;
localparam DIRECTRELL_SEQA      = 15'h48C0;
localparam DIRECTRI_SEQA        = 15'h4700;
localparam FETCH_SEQA           = 15'h4040;
localparam FETCH0_SEQA          = 15'h4000;
localparam IMM_SEQA             = 15'h4100;
localparam ISR_SEQA             = 15'h4980;
localparam ISRFETCH_SEQA        = 15'h4080;
localparam NBIT_SEQA            = 15'h4640;
localparam NONE_SEQA            = 15'h40C0;
localparam REL_SEQA             = 15'h4140;
localparam RI_SEQA              = 15'h43C0;
localparam RIDIRECT_SEQA        = 15'h46C0;
localparam RIIMM_SEQA           = 15'h4400;
localparam RIREL_SEQA           = 15'h4900;
localparam RN_SEQA              = 15'h4380;
localparam RNDIRECT_SEQA        = 15'h4740;
localparam RNREL_SEQA           = 15'h4940;
localparam XDPTR_SEQA           = 15'h45C0;
localparam XRI_SEQA             = 15'h4600;