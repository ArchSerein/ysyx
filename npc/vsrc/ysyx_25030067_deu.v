`include "autoconf.vh"
`include "ysyx_25030067_riscv_param.vh"

module ysyx_25030067_deu (
    input                           clock,
    input                           reset,

    input                           excp_flush,
    input                           mret_flush,

    input                           icu_valid_i,
    input  [`ICU_DEU_BUS_WIDTH-1:0] icu_deu_bus_i,
    input  [ 1:0]                   icu_excp_bus_i,

    output                          deu_ready_o,
    output [`DEU_RFU_BUS_WIDTH-1:0] deu_rfu_bus_o,
    output [ 4:0]                   deu_excp_bus_o,

    output [`ADDR_WIDTH-1:0]        cache_flush_target,
    output                          cache_flush,
    input                           branch_flush,
    input                           wait_cache_flush,

    input                           rfu_ready_i,
    output                          valid_o
);

    reg valid;
    reg [`ICU_DEU_BUS_WIDTH-1:0] icu_deu_bus;
    reg [ 1:0]                   icu_excp_bus;

    wire [31:0] deu_pc;
    wire [31:0] deu_snpc;

    wire [ 4:0] deu_rs1;
    wire [ 4:0] deu_rs2;
    wire [ 4:0] deu_rd;
    wire [ 6:0] deu_funct7;
    wire [ 2:0] deu_funct3;
    wire [ 6:0] deu_opcode;
    wire [31:0] deu_imm_i;
    wire [31:0] deu_imm_s;
    wire [31:0] deu_imm_b;
    wire [31:0] deu_imm_u;
    wire [31:0] deu_imm_j;
    wire [31:0] deu_imm;
    wire [ 2:0] deu_optype;
    wire [11:0] deu_csr_addr;
    wire [ 2:0] deu_compare_fn;

    wire [31:0] deu_inst;

    assign { deu_pc, deu_snpc, deu_inst} = icu_deu_bus;

    always @ (posedge clock) begin
      if (icu_valid_i && deu_ready_o) begin
        icu_deu_bus <= icu_deu_bus_i;
      end
    end
    always @ (posedge clock) begin
      if (icu_valid_i && deu_ready_o) begin
        icu_excp_bus <= icu_excp_bus_i;
      end
    end

    wire has_flush_sign;
    always @(posedge clock) begin
      if (has_flush_sign) begin
        valid <= 1'b0;
      end else if (icu_valid_i) begin
        valid <= 1'b1;
      end else if (valid_o && rfu_ready_i) begin
        valid <= 1'b0;
      end
    end
    assign has_flush_sign = reset || branch_flush || excp_flush || mret_flush || wait_cache_flush;

    // instruction
    wire            inst_lui;
    wire            inst_auipc;
    wire            inst_jal;
    wire            inst_jalr;
    wire            inst_lb;
    wire            inst_lh;
    wire            inst_lw;
    wire            inst_lbu;
    wire            inst_lhu;
    wire            inst_sb;
    wire            inst_sh;
    wire            inst_sw;
    wire            inst_addi;
    wire            inst_xori;
    wire            inst_ori;
    wire            inst_andi;
    wire            inst_slli;
    wire            inst_srli;
    wire            inst_srai;
    wire            inst_add;
    wire            inst_sub;
    wire            inst_sll;
    wire            inst_xor;
    wire            inst_srl;
    wire            inst_sra;
    wire            inst_or;
    wire            inst_and;
    // branch instruction
    wire            inst_bne;
    wire            inst_beq;
    wire            inst_blt;
    wire            inst_bge;
    wire            inst_bltu;
    wire            inst_bgeu;

    wire            inst_slti;
    wire            inst_sltiu;
    wire            inst_slt;
    wire            inst_sltu;
    // privileged instruction
    wire            inst_ecall;
    wire            inst_mret;
    wire            inst_ebreak;
    // csr instruction
    wire            inst_csrrw;
    wire            inst_csrrs;

    wire            inst_fence_i;

    assign deu_csr_addr   = deu_inst[31:20];

    assign deu_rs1        = deu_inst[19:15];
    assign deu_rs2        = deu_inst[24:20];
    assign deu_rd         = deu_inst[11:7];

    assign deu_funct7     = deu_inst[31:25];
    assign deu_funct3     = deu_inst[14:12];
    assign deu_opcode     = deu_inst[6:0];

    assign deu_imm_i      = { {20{deu_inst[31]}}, deu_inst[31:20] };
    assign deu_imm_s      = { {20{deu_inst[31]}}, deu_inst[31:25], deu_inst[11:7] };
    assign deu_imm_b      = { {19{deu_inst[31]}}, deu_inst[31], deu_inst[7], deu_inst[30:25],
                                deu_inst[11:8], 1'b0 };
    assign deu_imm_u      = { deu_inst[31:12], 12'b0 };
    assign deu_imm_j      = { {12{deu_inst[31]}}, deu_inst[19:12], deu_inst[20],
                                deu_inst[30:21], 1'b0 };

    assign deu_optype     = {3{deu_opcode == 7'b0110011}} & `INST_R |
                            {3{deu_opcode == 7'b0100011}} & `INST_S |
                            {3{deu_opcode == 7'b1100011}} & `INST_B |
                            {3{deu_opcode == 7'b1101111}} & `INST_J |
                            {3{deu_opcode == 7'b0110111}} & `INST_U |
                            {3{deu_opcode == 7'b0010111}} & `INST_U |
                            {3{deu_opcode == 7'b0010011}} & `INST_I |
                            {3{deu_opcode == 7'b0000011}} & `INST_I |
                            {3{deu_opcode == 7'b1100111}} & `INST_I |
                            {3{deu_opcode == 7'b1110011}} & `INST_PRIV;

    assign deu_imm        = {32{deu_optype == `INST_S}} & deu_imm_s |
                            {32{deu_optype == `INST_B}} & deu_imm_b |
                            {32{deu_optype == `INST_J}} & deu_imm_j |
                            {32{deu_optype == `INST_U}} & deu_imm_u |
                            {32{deu_optype == `INST_I}} & deu_imm_i;


    assign inst_lui       = deu_opcode == 7'b0110111;
    assign inst_auipc     = deu_opcode == 7'b0010111;
    assign inst_jal       = deu_opcode == 7'b1101111;
    assign inst_jalr      = deu_opcode == 7'b1100111 && deu_funct3 == 3'b000;
    assign inst_lb        = deu_opcode == 7'b0000011 && deu_funct3 == 3'b000;
    assign inst_lh        = deu_opcode == 7'b0000011 && deu_funct3 == 3'b001;
    assign inst_lw        = deu_opcode == 7'b0000011 && deu_funct3 == 3'b010;
    assign inst_lbu       = deu_opcode == 7'b0000011 && deu_funct3 == 3'b100;
    assign inst_lhu       = deu_opcode == 7'b0000011 && deu_funct3 == 3'b101;
    assign inst_sb        = deu_opcode == 7'b0100011 && deu_funct3 == 3'b000;
    assign inst_sh        = deu_opcode == 7'b0100011 && deu_funct3 == 3'b001;
    assign inst_sw        = deu_opcode == 7'b0100011 && deu_funct3 == 3'b010;
    assign inst_addi      = deu_opcode == 7'b0010011 && deu_funct3 == 3'b000;
    assign inst_xori      = deu_opcode == 7'b0010011 && deu_funct3 == 3'b100;
    assign inst_ori       = deu_opcode == 7'b0010011 && deu_funct3 == 3'b110;
    assign inst_andi      = deu_opcode == 7'b0010011 && deu_funct3 == 3'b111;
    assign inst_slli      = deu_opcode == 7'b0010011 && deu_funct3 == 3'b001 &&
                               deu_funct7 == 7'b0000000;
    assign inst_srli      = deu_opcode == 7'b0010011 && deu_funct3 == 3'b101 &&
                               deu_funct7 == 7'b0000000;
    assign inst_srai      = deu_opcode == 7'b0010011 && deu_funct3 == 3'b101 &&
                               deu_funct7 == 7'b0100000;
    assign inst_add       = deu_opcode == 7'b0110011 && deu_funct3 == 3'b000 &&
                               deu_funct7 == 7'b0000000;
    assign inst_sub       = deu_opcode == 7'b0110011 && deu_funct3 == 3'b000 &&
                               deu_funct7 == 7'b0100000;
    assign inst_sll       = deu_opcode == 7'b0110011 && deu_funct3 == 3'b001 &&
                               deu_funct7 == 7'b0000000;
    assign inst_xor       = deu_opcode == 7'b0110011 && deu_funct3 == 3'b100 &&
                               deu_funct7 == 7'b0000000;
    assign inst_srl       = deu_opcode == 7'b0110011 && deu_funct3 == 3'b101 &&
                               deu_funct7 == 7'b0000000;
    assign inst_sra       = deu_opcode == 7'b0110011 && deu_funct3 == 3'b101 &&
                               deu_funct7 == 7'b0100000;
    assign inst_or        = deu_opcode == 7'b0110011 && deu_funct3 == 3'b110 &&
                               deu_funct7 == 7'b0000000;
    assign inst_and       = deu_opcode == 7'b0110011 && deu_funct3 == 3'b111 &&
                               deu_funct7 == 7'b0000000;
    assign inst_beq       = deu_opcode == 7'b1100011 && deu_funct3 == 3'b000;
    assign inst_bne       = deu_opcode == 7'b1100011 && deu_funct3 == 3'b001;
    assign inst_blt       = deu_opcode == 7'b1100011 && deu_funct3 == 3'b100;
    assign inst_bge       = deu_opcode == 7'b1100011 && deu_funct3 == 3'b101;
    assign inst_bltu      = deu_opcode == 7'b1100011 && deu_funct3 == 3'b110;
    assign inst_bgeu      = deu_opcode == 7'b1100011 && deu_funct3 == 3'b111;
    assign inst_slti      = deu_opcode == 7'b0010011 && deu_funct3 == 3'b010;
    assign inst_sltiu     = deu_opcode == 7'b0010011 && deu_funct3 == 3'b011;
    assign inst_slt       = deu_opcode == 7'b0110011 && deu_funct3 == 3'b010 &&
                               deu_funct7 == 7'b0000000;
    assign inst_sltu      = deu_opcode == 7'b0110011 && deu_funct3 == 3'b011 &&
                              deu_funct7 == 7'b0000000;
    // privileged instruction
    assign inst_ecall     = deu_opcode == 7'b1110011 && deu_funct3 == 3'b000 &&
                               deu_funct7 == 7'b0000000 && deu_rd == 5'b00000 &&
                               deu_rs1 == 5'b00000 && deu_rs2 == 5'b00000;
    assign inst_ebreak    = deu_opcode == 7'b1110011 && deu_funct3 == 3'b000 &&
                               deu_funct7 == 7'b0000000 && deu_rd == 5'b00000 &&
                               deu_rs1 == 5'b00000 && deu_rs2 == 5'b00001;
    assign inst_mret      = deu_opcode == 7'b1110011 && deu_funct3 == 3'b000 &&
                            deu_funct7 == 7'b0011000 && deu_rd == 5'b00000 &&
                            deu_rs1 == 5'b00000 && deu_rs2 == 5'b00010;

    // csr instruction
    assign inst_csrrw     = deu_opcode == 7'b1110011 && deu_funct3 == 3'b001;
    assign inst_csrrs     = deu_opcode == 7'b1110011 && deu_funct3 == 3'b010;

    assign inst_fence_i   = deu_opcode == 7'b0001111;

    wire          valid_inst;
    assign valid_inst = inst_ecall | inst_ebreak | inst_mret |
                      inst_lui | inst_auipc | inst_jal | inst_jalr |
                      inst_lb | inst_lh | inst_lw | inst_lbu | inst_lhu |
                      inst_sb | inst_sh | inst_sw |
                      inst_addi | inst_xori | inst_ori | inst_andi |
                      inst_slli | inst_srli | inst_srai |
                      inst_add | inst_sub | inst_sll |
                      inst_xor | inst_srl | inst_sra |
                      inst_or  | inst_and |
                      inst_beq | inst_bne |
                      inst_blt | inst_bge |
                      inst_bltu| inst_bgeu|
                      inst_slti| inst_sltiu|
                      inst_slt | inst_sltu |
                      inst_csrrw | inst_csrrs |
                      inst_fence_i;

    assign deu_compare_fn = {3{inst_beq}} & 3'b000 |
                            {3{inst_bne}} & 3'b001 |
                            {3{inst_bge}} & 3'b010 |
                            {3{inst_blt | inst_slt | inst_slti}} & 3'b011 |
                            {3{inst_bltu | inst_sltiu | inst_sltu}} & 3'b101 |
                            {3{inst_bgeu}} & 3'b110;

    wire        res_from_compare;
    assign res_from_compare = inst_slt | inst_sltu | inst_slti | inst_sltiu;

    wire        res_from_csr;
    assign res_from_csr = inst_csrrw || inst_csrrs;

    // control signal generation
    wire [2:0] alu_op;
    assign alu_op = {3{inst_auipc | inst_jal | inst_jalr | inst_lb | inst_lbu | inst_lh |
                        inst_lhu | inst_lw | inst_sb | inst_sh | inst_sw | inst_addi |
                        inst_lui | inst_add}} & 3'b000 |
                    {3{inst_xori | inst_xor}} & 3'b111 |
                    {3{inst_or | inst_ori}} & 3'b110 |
                    {3{inst_and | inst_andi}} & 3'b101 |
                    {3{inst_sll | inst_slli}} & 3'b010 |
                    {3{inst_srl | inst_srli}} & 3'b100 |
                    {3{inst_sra | inst_srai}} & 3'b011 |
                    {3{inst_sub}} & 3'b001;

    wire src1_is_pc;
    assign src1_is_pc = deu_optype == `INST_J || deu_optype == `INST_B || inst_auipc;

    wire src2_is_imm;
    assign src2_is_imm = deu_optype == `INST_I || deu_optype == `INST_S || deu_optype == `INST_B ||
                        deu_optype == `INST_U || deu_optype == `INST_J;

    wire compare_src2_is_imm;
    assign compare_src2_is_imm = inst_sltiu || inst_slti;

    wire src2_is_csr;
    assign src2_is_csr = inst_csrrs;

    wire res_from_mem;
    assign res_from_mem = inst_lb || inst_lh || inst_lw || inst_lbu || inst_lhu;

    wire res_from_csr;
    assign res_from_csr = inst_csrrw || inst_csrrs;

    wire csr_op;
    assign csr_op = inst_csrrw;

    wire xret_flush;
    assign xret_flush = inst_mret;

    wire gr_we;
    assign gr_we = deu_optype != `INST_S && deu_optype != `INST_B && !inst_ecall && !inst_mret
                    && !inst_ebreak;

    wire csr_we;
    assign csr_we = inst_csrrw || inst_csrrs;

    wire [3:0] deu_mem_re;
    assign deu_mem_re = {4{inst_lb}} & 4'b0101 |
                        {4{inst_lh}} & 4'b0111 |
                        {4{inst_lw}} & 4'b1111 |
                        {4{inst_lbu}} & 4'b0001 |
                        {4{inst_lhu}} & 4'b0011;

    wire [3:0] deu_mem_we;
    assign deu_mem_we = {4{inst_sb}} & 4'b0001 |
                        {4{inst_sh}} & 4'b0011 |
                        {4{inst_sw}} & 4'b1111;

    wire [31:0] deu_src1;
    assign deu_src1 = src1_is_pc ? deu_pc : 32'h0;

    wire src1_from_pre;
    assign src1_from_pre = src1_is_pc || inst_lui;

    wire deu_br_taken;
    assign deu_br_taken = inst_beq || inst_bne || inst_blt || inst_bge || inst_bltu || inst_bgeu;

    wire jmp_flag;
    assign jmp_flag = inst_jal || inst_jalr;

    assign cache_flush        = inst_fence_i && valid;
    assign cache_flush_target = deu_snpc;

    assign deu_rfu_bus_o = {
      deu_pc,
      deu_rs1,
      deu_rs2,
      deu_rd,
      deu_csr_addr,
      deu_imm,
      deu_compare_fn,
      compare_src2_is_imm,
      src2_is_imm,
      src2_is_csr,
      csr_op,
      res_from_compare,
      alu_op,
      src1_from_pre,
      res_from_mem,
      res_from_csr,
      xret_flush,
      gr_we,
      csr_we,
      deu_mem_re,
      deu_mem_we,
      jmp_flag,
      deu_snpc,
      deu_src1,
      deu_br_taken
    };

    assign valid_o = valid && !branch_flush;
    assign deu_ready_o = !valid || (valid_o && rfu_ready_i);
    assign deu_excp_bus_o = {
      inst_ecall,
      inst_ebreak,
      !valid_inst,
      icu_excp_bus[1:0]
    };

    `ifdef CONFIG_TRACE_PERFORMANCE
      // performance counter
      wire is_cal_inst;
      wire is_mem_inst;
      wire is_csr_inst;
      wire is_jump_inst;
      wire is_branch_inst;
      wire is_default_inst;
      assign is_cal_inst = inst_lui | inst_auipc | inst_addi | inst_xori | inst_ori | inst_andi |
                          inst_slli | inst_srli | inst_srai | inst_add | inst_sub | inst_sll |
                          inst_xor | inst_srl | inst_sra | inst_or | inst_and;
      assign is_mem_inst = inst_lb | inst_lh | inst_lw | inst_lbu | inst_lhu | inst_sb | inst_sh |
                          inst_sw;
      assign is_csr_inst = inst_csrrw | inst_csrrs;
      assign is_jump_inst = inst_jal | inst_jalr;
      assign is_branch_inst = inst_beq | inst_bne | inst_bge | inst_bltu | inst_blt | inst_bgeu;
      assign is_default_inst = inst_ecall | inst_mret | inst_ebreak;
      import "DPI-C" function void inst_type_count(input byte mask);
      import "DPI-C" function void total_inst_count();

      always @(posedge clock)
      begin
          if (valid_o && rfu_ready_i) begin
              if (is_cal_inst) begin
                  inst_type_count(0);
              end else if (is_mem_inst) begin
                  inst_type_count(1);
              end else if (is_csr_inst) begin
                  inst_type_count(2);
              end else if (is_branch_inst) begin
                  inst_type_count(3);
              end else if (is_jump_inst) begin
                  inst_type_count(4);
              end else if (is_default_inst) begin
                  inst_type_count(6);
              end
              total_inst_count();
          end
      end
    `endif
    import "DPI-C" function void get_inst(input int inst);
    always @(posedge clock) begin
      if (icu_valid_i && deu_ready_o) begin
        get_inst(deu_inst);
      end
    end
endmodule
