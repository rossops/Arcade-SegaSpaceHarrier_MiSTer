//============================================================================
//  FD1089B decrypt (Enduro Racer's main CPU, key 317-0013A), the static
//  per-address table from MAME's fd1089.cpp (Salmoria, Naive, MacDonald).
//
//  Combinational: one 16-bit word in, one out. Only bits 15:10, 6 and 3 of
//  the word are encrypted. The 8-bit key comes from the set's 16 KB key
//  image at {~opcode, address bits 23:16, 9, 5, 3, 1} (opcode keys in the
//  first 4 KB, data keys in the second); the caller reads it from the key
//  BRAM with the address, so it is ready with the ROM word. A key byte of
//  zero means the word is plain (the data ranges the game reads raw).
//  Opcode = a program-space fetch (FC 2 or 6), MAME's AS_OPCODES: the
//  68000's instruction and extension words alike.
//============================================================================
module sh_fd1089b (
    input      [15:0] din,
    input       [7:0] key,
    input             opcode,
    output     [15:0] dout
);

// ---- bitswap<8>(v, s7..s0): result bit 7 takes source bit s7
function automatic [7:0] bs(input [7:0] v, input [2:0] s7, s6, s5, s4, s3, s2, s1, s0);
    bs = {v[s7], v[s6], v[s5], v[s4], v[s3], v[s2], v[s1], v[s0]};
endfunction

function automatic [7:0] rearrange_key(input [7:0] k, input op);
    reg [7:0] t;
    begin
        t = k;
        if (!op) begin
            t = t ^ 8'h30;                                   // bits 4 and 5
            if (!t[3]) t = t ^ 8'h02;
            t = bs(t, 3'd1,3'd0,3'd6,3'd4,3'd3,3'd5,3'd2,3'd7);
            if (t[6]) t = bs(t, 3'd7,3'd6,3'd2,3'd4,3'd5,3'd3,3'd1,3'd0);
        end
        else begin
            t = t ^ 8'h1c;                                   // bits 2, 3 and 4
            if (!t[3]) t = t ^ 8'h20;
            if (t[7]) t = t ^ 8'h40;
            t = bs(t, 3'd5,3'd7,3'd6,3'd4,3'd2,3'd3,3'd1,3'd0);
            if (t[6]) t = bs(t, 3'd7,3'd6,3'd5,3'd3,3'd2,3'd4,3'd1,3'd0);
        end
        if (t[6]) begin if (t[5]) t = t ^ 8'h10; end
        else begin if (!t[4]) t = t ^ 8'h20; end
        rearrange_key = t;
    end
endfunction

// ---- s_addr_params: xor value and the swap for each of 16 table classes
function automatic [7:0] addr_swap(input [7:0] v, input [3:0] n);
    case (n)
        4'd0:  addr_swap = bs(v, 3'd6,3'd4,3'd5,3'd7,3'd3,3'd0,3'd1,3'd2) ^ 8'h23;
        4'd1:  addr_swap = bs(v, 3'd2,3'd5,3'd3,3'd6,3'd7,3'd1,3'd0,3'd4) ^ 8'h92;
        4'd2:  addr_swap = bs(v, 3'd6,3'd7,3'd4,3'd2,3'd0,3'd5,3'd1,3'd3) ^ 8'hb8;
        4'd3:  addr_swap = bs(v, 3'd5,3'd3,3'd7,3'd1,3'd4,3'd6,3'd0,3'd2) ^ 8'h74;
        4'd4:  addr_swap = bs(v, 3'd7,3'd4,3'd1,3'd0,3'd6,3'd2,3'd3,3'd5) ^ 8'hcf;
        4'd5:  addr_swap = bs(v, 3'd3,3'd1,3'd6,3'd4,3'd5,3'd0,3'd2,3'd7) ^ 8'hc4;
        4'd6:  addr_swap = bs(v, 3'd5,3'd7,3'd2,3'd4,3'd3,3'd1,3'd6,3'd0) ^ 8'h51;
        4'd7:  addr_swap = bs(v, 3'd7,3'd2,3'd0,3'd6,3'd1,3'd3,3'd4,3'd5) ^ 8'h14;
        4'd8:  addr_swap = bs(v, 3'd3,3'd5,3'd6,3'd0,3'd2,3'd1,3'd7,3'd4) ^ 8'h7f;
        4'd9:  addr_swap = bs(v, 3'd2,3'd3,3'd4,3'd0,3'd6,3'd7,3'd5,3'd1) ^ 8'h03;
        4'd10: addr_swap = bs(v, 3'd3,3'd1,3'd7,3'd5,3'd2,3'd4,3'd6,3'd0) ^ 8'h96;
        4'd11: addr_swap = bs(v, 3'd7,3'd6,3'd2,3'd3,3'd0,3'd4,3'd5,3'd1) ^ 8'h30;
        4'd12: addr_swap = bs(v, 3'd1,3'd0,3'd3,3'd7,3'd4,3'd5,3'd2,3'd6) ^ 8'he2;
        4'd13: addr_swap = bs(v, 3'd1,3'd6,3'd0,3'd5,3'd7,3'd2,3'd4,3'd3) ^ 8'h72;
        4'd14: addr_swap = bs(v, 3'd0,3'd4,3'd1,3'd2,3'd6,3'd5,3'd7,3'd3) ^ 8'hf5;
        4'd15: addr_swap = bs(v, 3'd0,3'd7,3'd5,3'd3,3'd1,3'd4,3'd2,3'd6) ^ 8'h5b;
    endcase
endfunction

// ---- s_basetable_fd1089
function automatic [7:0] basetable(input [7:0] i);
    case (i)
        8'h00: basetable=8'h00; 8'h01: basetable=8'h1c; 8'h02: basetable=8'h76; 8'h03: basetable=8'h6a; 8'h04: basetable=8'h5e; 8'h05: basetable=8'h42; 8'h06: basetable=8'h24; 8'h07: basetable=8'h38;
        8'h08: basetable=8'h4b; 8'h09: basetable=8'h67; 8'h0a: basetable=8'had; 8'h0b: basetable=8'h81; 8'h0c: basetable=8'he9; 8'h0d: basetable=8'hc5; 8'h0e: basetable=8'h03; 8'h0f: basetable=8'h2f;
        8'h10: basetable=8'h45; 8'h11: basetable=8'h69; 8'h12: basetable=8'haf; 8'h13: basetable=8'h83; 8'h14: basetable=8'he7; 8'h15: basetable=8'hcb; 8'h16: basetable=8'h01; 8'h17: basetable=8'h2d;
        8'h18: basetable=8'h02; 8'h19: basetable=8'h1e; 8'h1a: basetable=8'h78; 8'h1b: basetable=8'h64; 8'h1c: basetable=8'h5c; 8'h1d: basetable=8'h40; 8'h1e: basetable=8'h2a; 8'h1f: basetable=8'h36;
        8'h20: basetable=8'h32; 8'h21: basetable=8'h2e; 8'h22: basetable=8'h44; 8'h23: basetable=8'h58; 8'h24: basetable=8'he4; 8'h25: basetable=8'hf8; 8'h26: basetable=8'h9e; 8'h27: basetable=8'h82;
        8'h28: basetable=8'h29; 8'h29: basetable=8'h05; 8'h2a: basetable=8'hcf; 8'h2b: basetable=8'he3; 8'h2c: basetable=8'h93; 8'h2d: basetable=8'hbf; 8'h2e: basetable=8'h79; 8'h2f: basetable=8'h55;
        8'h30: basetable=8'h3f; 8'h31: basetable=8'h13; 8'h32: basetable=8'hd5; 8'h33: basetable=8'hf9; 8'h34: basetable=8'h85; 8'h35: basetable=8'ha9; 8'h36: basetable=8'h63; 8'h37: basetable=8'h4f;
        8'h38: basetable=8'hb8; 8'h39: basetable=8'ha4; 8'h3a: basetable=8'hc2; 8'h3b: basetable=8'hde; 8'h3c: basetable=8'h6e; 8'h3d: basetable=8'h72; 8'h3e: basetable=8'h18; 8'h3f: basetable=8'h04;
        8'h40: basetable=8'h0c; 8'h41: basetable=8'h10; 8'h42: basetable=8'h7a; 8'h43: basetable=8'h66; 8'h44: basetable=8'hfc; 8'h45: basetable=8'he0; 8'h46: basetable=8'h86; 8'h47: basetable=8'h9a;
        8'h48: basetable=8'h47; 8'h49: basetable=8'h6b; 8'h4a: basetable=8'ha1; 8'h4b: basetable=8'h8d; 8'h4c: basetable=8'hbb; 8'h4d: basetable=8'h97; 8'h4e: basetable=8'h51; 8'h4f: basetable=8'h7d;
        8'h50: basetable=8'h17; 8'h51: basetable=8'h3b; 8'h52: basetable=8'hfd; 8'h53: basetable=8'hd1; 8'h54: basetable=8'heb; 8'h55: basetable=8'hc7; 8'h56: basetable=8'h0d; 8'h57: basetable=8'h21;
        8'h58: basetable=8'ha0; 8'h59: basetable=8'hbc; 8'h5a: basetable=8'hda; 8'h5b: basetable=8'hc6; 8'h5c: basetable=8'h50; 8'h5d: basetable=8'h4c; 8'h5e: basetable=8'h26; 8'h5f: basetable=8'h3a;
        8'h60: basetable=8'h3e; 8'h61: basetable=8'h22; 8'h62: basetable=8'h48; 8'h63: basetable=8'h54; 8'h64: basetable=8'h46; 8'h65: basetable=8'h5a; 8'h66: basetable=8'h3c; 8'h67: basetable=8'h20;
        8'h68: basetable=8'h25; 8'h69: basetable=8'h09; 8'h6a: basetable=8'hc3; 8'h6b: basetable=8'hef; 8'h6c: basetable=8'hc1; 8'h6d: basetable=8'hed; 8'h6e: basetable=8'h2b; 8'h6f: basetable=8'h07;
        8'h70: basetable=8'h6d; 8'h71: basetable=8'h41; 8'h72: basetable=8'h87; 8'h73: basetable=8'hab; 8'h74: basetable=8'h89; 8'h75: basetable=8'ha5; 8'h76: basetable=8'h6f; 8'h77: basetable=8'h43;
        8'h78: basetable=8'h1a; 8'h79: basetable=8'h06; 8'h7a: basetable=8'h60; 8'h7b: basetable=8'h7c; 8'h7c: basetable=8'h62; 8'h7d: basetable=8'h7e; 8'h7e: basetable=8'h14; 8'h7f: basetable=8'h08;
        8'h80: basetable=8'h0a; 8'h81: basetable=8'h16; 8'h82: basetable=8'h70; 8'h83: basetable=8'h6c; 8'h84: basetable=8'hdc; 8'h85: basetable=8'hc0; 8'h86: basetable=8'haa; 8'h87: basetable=8'hb6;
        8'h88: basetable=8'h4d; 8'h89: basetable=8'h61; 8'h8a: basetable=8'ha7; 8'h8b: basetable=8'h8b; 8'h8c: basetable=8'hf7; 8'h8d: basetable=8'hdb; 8'h8e: basetable=8'h11; 8'h8f: basetable=8'h3d;
        8'h90: basetable=8'h5b; 8'h91: basetable=8'h77; 8'h92: basetable=8'hbd; 8'h93: basetable=8'h91; 8'h94: basetable=8'he1; 8'h95: basetable=8'hcd; 8'h96: basetable=8'h0b; 8'h97: basetable=8'h27;
        8'h98: basetable=8'h80; 8'h99: basetable=8'h9c; 8'h9a: basetable=8'hf6; 8'h9b: basetable=8'hea; 8'h9c: basetable=8'h56; 8'h9d: basetable=8'h4a; 8'h9e: basetable=8'h2c; 8'h9f: basetable=8'h30;
        8'ha0: basetable=8'hb0; 8'ha1: basetable=8'hac; 8'ha2: basetable=8'hca; 8'ha3: basetable=8'hd6; 8'ha4: basetable=8'hee; 8'ha5: basetable=8'hf2; 8'ha6: basetable=8'h98; 8'ha7: basetable=8'h84;
        8'ha8: basetable=8'h37; 8'ha9: basetable=8'h1b; 8'haa: basetable=8'hdd; 8'hab: basetable=8'hf1; 8'hac: basetable=8'h95; 8'had: basetable=8'hb9; 8'hae: basetable=8'h73; 8'haf: basetable=8'h5f;
        8'hb0: basetable=8'h39; 8'hb1: basetable=8'h15; 8'hb2: basetable=8'hdf; 8'hb3: basetable=8'hf3; 8'hb4: basetable=8'h9b; 8'hb5: basetable=8'hb7; 8'hb6: basetable=8'h71; 8'hb7: basetable=8'h5d;
        8'hb8: basetable=8'hb2; 8'hb9: basetable=8'hae; 8'hba: basetable=8'hc4; 8'hbb: basetable=8'hd8; 8'hbc: basetable=8'hec; 8'hbd: basetable=8'hf0; 8'hbe: basetable=8'h96; 8'hbf: basetable=8'h8a;
        8'hc0: basetable=8'ha8; 8'hc1: basetable=8'hb4; 8'hc2: basetable=8'hd2; 8'hc3: basetable=8'hce; 8'hc4: basetable=8'hd0; 8'hc5: basetable=8'hcc; 8'hc6: basetable=8'ha6; 8'hc7: basetable=8'hba;
        8'hc8: basetable=8'h1f; 8'hc9: basetable=8'h33; 8'hca: basetable=8'hf5; 8'hcb: basetable=8'hd9; 8'hcc: basetable=8'hfb; 8'hcd: basetable=8'hd7; 8'hce: basetable=8'h1d; 8'hcf: basetable=8'h31;
        8'hd0: basetable=8'h57; 8'hd1: basetable=8'h7b; 8'hd2: basetable=8'hb1; 8'hd3: basetable=8'h9d; 8'hd4: basetable=8'hb3; 8'hd5: basetable=8'h9f; 8'hd6: basetable=8'h59; 8'hd7: basetable=8'h75;
        8'hd8: basetable=8'h8c; 8'hd9: basetable=8'h90; 8'hda: basetable=8'hfa; 8'hdb: basetable=8'he6; 8'hdc: basetable=8'hf4; 8'hdd: basetable=8'he8; 8'hde: basetable=8'h8e; 8'hdf: basetable=8'h92;
        8'he0: basetable=8'h12; 8'he1: basetable=8'h0e; 8'he2: basetable=8'h68; 8'he3: basetable=8'h74; 8'he4: basetable=8'he2; 8'he5: basetable=8'hfe; 8'he6: basetable=8'h94; 8'he7: basetable=8'h88;
        8'he8: basetable=8'h65; 8'he9: basetable=8'h49; 8'hea: basetable=8'h8f; 8'heb: basetable=8'ha3; 8'hec: basetable=8'h99; 8'hed: basetable=8'hb5; 8'hee: basetable=8'h7f; 8'hef: basetable=8'h53;
        8'hf0: basetable=8'h35; 8'hf1: basetable=8'h19; 8'hf2: basetable=8'hd3; 8'hf3: basetable=8'hff; 8'hf4: basetable=8'hc9; 8'hf5: basetable=8'he5; 8'hf6: basetable=8'h23; 8'hf7: basetable=8'h0f;
        8'hf8: basetable=8'hbe; 8'hf9: basetable=8'ha2; 8'hfa: basetable=8'hc8; 8'hfb: basetable=8'hd4; 8'hfc: basetable=8'h4e; 8'hfd: basetable=8'h52; 8'hfe: basetable=8'h34; 8'hff: basetable=8'h28;
    endcase
endfunction

// ---- fd1089b_device::decode on the 8 encrypted bits
function automatic [7:0] decode_b(input [7:0] val, input [7:0] k, input op);
    reg [7:0] t, v;
    begin
        if (k == 8'd0) decode_b = val;
        else begin
            t = rearrange_key(k, op);
            v = addr_swap(val, t[7:4]);
            if (t[3]) v = v ^ 8'h01;
            if (t[0]) v = v ^ 8'hb1;
            if (op)   v = v ^ 8'h34;
            if (!op && t[6]) v = v ^ 8'h01;
            v = basetable(v);
            if (!op) begin
                if (!t[6] && t[2]) v = v ^ 8'h01;
                if (t[4])          v = v ^ 8'h01;
            end
            else begin
                if (t[6] && t[2])  v = v ^ 8'h01;
                if (t[5])          v = v ^ 8'h01;
            end
            if (t[2]) begin
                v = bs(v, 3'd7,3'd6,3'd5,3'd4,3'd1,3'd0,3'd3,3'd2);
                if (t[0] ^ t[1]) v = bs(v, 3'd7,3'd6,3'd5,3'd4,3'd0,3'd1,3'd3,3'd2);
            end
            else begin
                v = bs(v, 3'd7,3'd6,3'd5,3'd4,3'd3,3'd2,3'd0,3'd1);
                if (t[0] ^ t[1]) v = bs(v, 3'd7,3'd6,3'd5,3'd4,3'd1,3'd0,3'd2,3'd3);
            end
            decode_b = v;
        end
    end
endfunction

// the 8 encrypted bits gathered as in decrypt_one: {15:10, 6, 3}
wire [7:0] src = {din[15:10], din[6], din[3]};
wire [7:0] dec = decode_b(src, key, opcode);
assign dout = {dec[7:2], din[9:7], dec[1], din[5:4], dec[0], din[2:0]};

endmodule
