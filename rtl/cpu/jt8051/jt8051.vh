reg jsr_en;
reg [14:0] jsr_ua, jsr_ret, uaddr;

// wire [2:0] addr_sel;
// wire [4:0] alu_sel;
// wire [1:0] code_sel;
// wire [3:0] cond_sel;
// wire [4:0] dst_sel;
// wire [2:0] flag_sel;
// wire [5:0] jsr_sel;
// wire [3:0] pc_sel;
// wire [4:0] src_sel;
// wire [1:0] x_sel;
// wire [1:0] xwr_sel;

// wire       x_acc;
// wire       sp_dec;
// wire       sp_inc;
// wire       ni;
// wire       latch;
// wire       reti;
// wire       wr;

reg  [47:0] ucode_rom[0:2**15-1];
wire [47:0] ucode_data;

initial begin
    $readmemb("jt8051.uc",ucode_rom);
end

assign ucode_data = ucode_rom[uaddr];

assign x_acc      = ucode_data[ 0+:1];
assign sp_dec     = ucode_data[15+:1];
assign sp_inc     = ucode_data[24+:1];
assign ni         = ucode_data[31+:1];
assign latch      = ucode_data[32+:1];
assign reti       = ucode_data[37+:1];
assign wr         = ucode_data[43+:1];
assign addr_sel   = ucode_data[ 1+:3];
assign alu_sel    = ucode_data[ 4+:5];
assign code_sel   = ucode_data[ 9+:2];
assign cond_sel   = ucode_data[11+:4];
assign dst_sel    = ucode_data[16+:5];
assign flag_sel   = ucode_data[21+:3];
assign jsr_sel    = ucode_data[25+:6];
assign pc_sel     = ucode_data[33+:4];
assign src_sel    = ucode_data[38+:5];
assign x_sel      = ucode_data[44+:2];
assign xwr_sel    = ucode_data[46+:2];


always @* begin
    case( jsr_sel )
        FETCH_JSR:   begin jsr_en=1; jsr_ua = 15'h101*15'd64; end 
        ISRFETCH_JSR: begin jsr_en=1; jsr_ua = 15'h102*15'd64; end 
        NONE_JSR:    begin jsr_en=1; jsr_ua = 15'h103*15'd64; end 
        IMM_JSR:     begin jsr_en=1; jsr_ua = 15'h104*15'd64; end 
        REL_JSR:     begin jsr_en=1; jsr_ua = 15'h105*15'd64; end 
        ABS_JSR:     begin jsr_en=1; jsr_ua = 15'h106*15'd64; end 
        AJMP_JSR:    begin jsr_en=1; jsr_ua = 15'h107*15'd64; end 
        ACALL_JSR:   begin jsr_en=1; jsr_ua = 15'h108*15'd64; end 
        DIRECT_JSR:  begin jsr_en=1; jsr_ua = 15'h109*15'd64; end 
        DIRECTL_JSR: begin jsr_en=1; jsr_ua = 15'h10A*15'd64; end 
        DIMM_JSR:    begin jsr_en=1; jsr_ua = 15'h10B*15'd64; end 
        DIRECTIMML_JSR: begin jsr_en=1; jsr_ua = 15'h10D*15'd64; end 
        RN_JSR:      begin jsr_en=1; jsr_ua = 15'h10E*15'd64; end 
        RI_JSR:      begin jsr_en=1; jsr_ua = 15'h10F*15'd64; end 
        RIIMM_JSR:   begin jsr_en=1; jsr_ua = 15'h110*15'd64; end 
        BIT_JSR:     begin jsr_en=1; jsr_ua = 15'h111*15'd64; end 
        BITL_JSR:    begin jsr_en=1; jsr_ua = 15'h112*15'd64; end 
        BITREL_JSR:  begin jsr_en=1; jsr_ua = 15'h113*15'd64; end 
        BITRELL_JSR: begin jsr_en=1; jsr_ua = 15'h114*15'd64; end 
        APC_JSR:     begin jsr_en=1; jsr_ua = 15'h115*15'd64; end 
        ADPTR_JSR:   begin jsr_en=1; jsr_ua = 15'h116*15'd64; end 
        XDPTR_JSR:   begin jsr_en=1; jsr_ua = 15'h117*15'd64; end 
        XRI_JSR:     begin jsr_en=1; jsr_ua = 15'h118*15'd64; end 
        NBIT_JSR:    begin jsr_en=1; jsr_ua = 15'h119*15'd64; end 
        DDIRECT_JSR: begin jsr_en=1; jsr_ua = 15'h11A*15'd64; end 
        RIDIRECT_JSR: begin jsr_en=1; jsr_ua = 15'h11B*15'd64; end 
        DIRECTRI_JSR: begin jsr_en=1; jsr_ua = 15'h11C*15'd64; end 
        RNDIRECT_JSR: begin jsr_en=1; jsr_ua = 15'h11D*15'd64; end 
        CJNEI_JSR:   begin jsr_en=1; jsr_ua = 15'h11E*15'd64; end 
        CJNED_JSR:   begin jsr_en=1; jsr_ua = 15'h11F*15'd64; end 
        CJNERI_JSR:  begin jsr_en=1; jsr_ua = 15'h120*15'd64; end 
        CJNERN_JSR:  begin jsr_en=1; jsr_ua = 15'h121*15'd64; end 
        DIRECTRELL_JSR: begin jsr_en=1; jsr_ua = 15'h123*15'd64; end 
        RNREL_JSR:   begin jsr_en=1; jsr_ua = 15'h125*15'd64; end 
        RET_JSR:     begin jsr_en=1; jsr_ua = jsr_ret; end
        default:     begin jsr_en=0; jsr_ua = 'h00; end
    endcase
end
