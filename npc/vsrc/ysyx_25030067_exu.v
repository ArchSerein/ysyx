`include "autoconf.vh"
`include "ysyx_25030067_riscv_param.vh"

module ysyx_25030067_exu (
    input                               clock,
    input                               reset,

    input                               excp_flush,
    input                               mret_flush,

    input                               rfu_valid_i,
    input  [`RFU_EXU_BUS_WIDTH-1:0]     rfu_exu_bus_i,
    input  [ 4:0]                       rfu_excp_bus_i,
    output                              exu_ready_o,
    // axi read addr channel
    input                               arready_i,
    output [31:0]                       araddr_o,
    output [ 2:0]                       arsize_o,
    output                              arvalid_o,
    // axi write addr channel
    input                               awready_i,
    output [31:0]                       awaddr_o,
    output [ 2:0]                       awsize_o,
    output                              awvalid_o,
    // axi wirte data channel
    input                               wready_i,
    output [31:0]                       wdata_o,
    output [ 3:0]                       wstrb_o,
    output                              wvalid_o,

    output                              ex_br_taken_o,
    output                              branch_flush,
    output [31:0]                       branch_target,

    output                              exu_alu_forward_valid,
    output [`FORWARD_DATA_BUS_WIDTH-1:0] exu_alu_forward_data,
    output  [`FORWARD_CTRL_BUS_WIDTH-1:0]    exu_forward_ctrl,
    output  [`FORWARD_DATA_BUS_WIDTH-1:0]    exu_forward_data,

    input                               lsu_ready_i,
    output [`EXU_LSU_BUS_WIDTH-1:0]     exu_lsu_bus_o,
    output [ 6:0]                       exu_excp_bus_o,
    output                              valid_o
);

    reg valid;
    reg  [`RFU_EXU_BUS_WIDTH-1:0]     rfu_exu_bus;
    reg  [ 4:0]                       rfu_excp_bus;
    wire [ 4:0]           ex_rd;
    wire                  ex_branch;
    wire [31:0]           ex_alu_src1;
    wire [31:0]           ex_alu_src2;
    wire                  ex_res_from_mem;
    wire [31:0]           ex_final_result;
    wire [ 3:0]           ex_mem_re;
    wire [ 3:0]           ex_mem_we;
    wire                  ex_gr_we;
    wire                  ex_csr_we;
    wire [11:0]           ex_csr_addr;
    wire [31:0]           ex_csr_wdata;
    wire [ 2:0]           ex_alu_op;
    wire [ 2:0]           ex_mul_div_op;
    wire                  ex_xret_flush;
    wire                  ex_res_from_pre;
    wire [31:0]           ex_snpc;
    wire [31:0]           ex_rs2_value;
    wire [31:0]           ex_pc;

    always @ (posedge clock) begin
      if (rfu_valid_i && exu_ready_o) begin
        rfu_exu_bus <= rfu_exu_bus_i;
      end
    end
    always @ (posedge clock) begin
      if (rfu_valid_i && exu_ready_o) begin
        rfu_excp_bus <= rfu_excp_bus_i;
      end
    end

    assign {
      ex_pc,
      ex_rd,
      ex_branch,
      ex_alu_op,
      ex_mul_div_op,
      ex_alu_src1,
      ex_alu_src2,
      ex_rs2_value,
      ex_res_from_mem,
      ex_res_from_pre,
      ex_final_result,
      ex_mem_re,
      ex_mem_we,
      ex_gr_we,
      ex_csr_we,
      ex_csr_addr,
      ex_csr_wdata,
      ex_snpc,
      ex_xret_flush
    } = rfu_exu_bus;

    wire [`DATA_WIDTH-1:0] ex_alu_result;
    wire [`DATA_WIDTH-1:0] ex_mul_result;
    wire [`DATA_WIDTH-1:0] ex_div_result;
    ysyx_25030067_alu ysyx_25030067_alu_module (
        .alu_op_i       (ex_alu_op),
        .alu_a_i        (ex_alu_src1),
        .alu_b_i        (ex_alu_src2),
        .alu_result_o   (ex_alu_result)
    );

    wire                      mul_finish;
    wire                      div_finish;
    wire                      EN_start_mul;
    wire                      EN_start_div;
    wire                      is_signed;
    wire  [2*`DATA_WIDTH-1:0] temp_mul_result;
    wire  [2*`DATA_WIDTH-1:0] temp_div_result;
    ysyx_25030067_mul ysyx_25030067_mul_module (
      .clock          (clock),
      .reset          (reset),

      .EN_start       (EN_start_mul),
      .is_signed      (is_signed),
      .src1           (ex_alu_src1),
      .src2           (ex_alu_src2),

      .finish         (mul_finish),
      .result         (temp_mul_result)
    );
    ysyx_25030067_div ysyx_25030067_div_module (
      .clock          (clock),
      .reset          (reset),

      .EN_start       (EN_start_div),
      .is_signed      (is_signed),
      .dividend       (ex_alu_src1),
      .divisor        (ex_alu_src2),

      .finish         (div_finish),
      .result         (temp_div_result)
    );

    assign EN_start_mul = ~ex_mul_div_op[2] & valid &
                          (ex_mul_div_op[1] | ex_mul_div_op[0]);
    assign EN_start_div = ex_mul_div_op[2] & valid;
    assign is_signed    = ex_mul_div_op[0];
    assign ex_mul_result= ex_mul_div_op[1] ?  temp_mul_result[2*`DATA_WIDTH-1:`DATA_WIDTH] :
                                              temp_mul_result[`DATA_WIDTH-1:0];
    assign ex_div_result= ex_mul_div_op[1] ?  temp_div_result[2*`DATA_WIDTH-1:`DATA_WIDTH] :
                                              temp_div_result[`DATA_WIDTH-1:0];
    wire [ 3:0] sb_we, sh_we;
    wire [ 1:0] mem_addr_mask;

    assign mem_addr_mask = ex_alu_result[1:0];

    assign sb_we = {
                    mem_addr_mask[1] && mem_addr_mask[0],
                    mem_addr_mask[1] && !mem_addr_mask[0],
                    !mem_addr_mask[1] && mem_addr_mask[0],
                    !mem_addr_mask[1] && !mem_addr_mask[0]
                };
    assign sh_we = {
                    mem_addr_mask[1] && !mem_addr_mask[0],
                    mem_addr_mask[1] && !mem_addr_mask[0],
                    !mem_addr_mask[1] && !mem_addr_mask[0],
                    !mem_addr_mask[1] && !mem_addr_mask[0]
                };

    wire [ 3:0] mem_we_mask;
    assign mem_we_mask   =  ({4{ex_mem_we == 4'b1111}} & 4'b1111) |
                            ({4{ex_mem_we == 4'b0011}} & sh_we)   |
                            ({4{ex_mem_we == 4'b0001}} & sb_we);

    wire [31:0] mem_byte_wdata;
    assign mem_byte_wdata = {
        {8{sb_we[3]}} & ex_rs2_value[7:0],
        {8{sb_we[2]}} & ex_rs2_value[7:0],
        {8{sb_we[1]}} & ex_rs2_value[7:0],
        {8{sb_we[0]}} & ex_rs2_value[7:0]
    };

    wire [31:0] mem_half_wdata;
    assign mem_half_wdata = {
        {16{sh_we[3]}} & ex_rs2_value[15:0],
        {16{sh_we[0]}} & ex_rs2_value[15:0]
    };

    assign branch_target = ex_alu_result;
    assign branch_flush = ex_branch && (|(ex_alu_result ^ ex_snpc)) && valid;
    assign ex_br_taken_o  = ex_branch;

    wire [31:0] final_result;
    wire [1:0] res_sel;
    assign res_sel = {EN_start_mul | EN_start_div, EN_start_mul | ex_res_from_pre};
    // res_sel: 2'b00=alu, 2'b01=pre, 2'b10=div, 2'b11=mul
    wire [31:0] res_mux_low  = res_sel[0] ? ex_final_result : ex_alu_result;
    wire [31:0] res_mux_high = res_sel[0] ? ex_mul_result   : ex_div_result;
    assign final_result      = res_sel[1] ? res_mux_high    : res_mux_low;

    wire is_skip_difftest;
    assign exu_lsu_bus_o = {
        is_skip_difftest,
        ex_pc,
        ex_csr_wdata,
        ex_csr_we,
        mem_addr_mask,
        ex_mem_re,
        |ex_mem_we,
        ex_csr_addr,
        ex_res_from_mem,
        ex_gr_we,
        ex_rd,
        ex_xret_flush,
        final_result
    };
    /* 32 + 1 + 2 + 4 + 1 + 12 + 1 + 1 + 5 + 1 + 1 + 1 + 32 = 94*/

    wire    idle;
    wire    no_mem_req;
    wire    no_mul_div;
    wire    handshake_success;
    wire    has_flush_sign;
    always @(posedge clock) begin
        if (has_flush_sign) begin
            valid <= 1'b0;
        end else if (rfu_valid_i) begin
            valid <= 1'b1;
        end else if (idle && lsu_ready_i) begin
            valid <= 1'b0;
        end
    end
    assign has_flush_sign = reset || excp_flush || mret_flush;

    reg         handshake_state;
    always @ (posedge clock) begin
      if (reset || (valid_o && lsu_ready_i)) begin
          handshake_state <= 1'b0;
      end else if (valid && handshake_success) begin
          handshake_state <= 1'b1;
      end
    end

    assign arsize_o         = {{3{ex_mem_re == 4'b1111}} & 3'b010} |
                              {{3{ex_mem_re == 4'b0011 || ex_mem_re == 4'b0111}} & 3'b001} |
                              {{3{ex_mem_re == 4'b0001 || ex_mem_re == 4'b0101}} & 3'b000};
    assign araddr_o         = ex_alu_result;
    assign awaddr_o         = ex_alu_result;
    assign awsize_o         = {{3{ex_mem_we == 4'b1111}} & 3'b010} |
                              {{3{ex_mem_re == 4'b0011}} & 3'b001} |
                              {{3{ex_mem_re == 4'b0001}} & 3'b000};
    wire   request_valid    = valid && !handshake_state;
    assign arvalid_o        = (|ex_mem_re) && request_valid;
    assign awvalid_o        = (|ex_mem_we) && request_valid;

    // assign wdata_o          =   ex_rs2_value;
    assign wdata_o          =   ({32{ex_mem_we == 4'b1111}} & ex_rs2_value) |
                                ({32{ex_mem_we == 4'b0011}} & mem_half_wdata) |
                                ({32{ex_mem_we == 4'b0001}} & mem_byte_wdata);
    assign wstrb_o          = mem_we_mask;
    assign wvalid_o         = (|ex_mem_we) && request_valid;

    wire   load_addr_misalign;
    wire   store_amo_addr_misalign;

    assign load_addr_misalign      = ex_mem_re[3] ? (ex_alu_result[1] | ex_alu_result[0]) :
                                     ex_mem_re[1] ? ex_alu_result[0] :
                                     1'b0;
    assign store_amo_addr_misalign = ex_mem_we[3] ? (ex_alu_result[1] | ex_alu_result[0]) :
                                     ex_mem_we[1] ? ex_alu_result[0] :
                                     1'b0;

    assign no_mem_req        = !(arvalid_o || awvalid_o || wvalid_o);
    assign no_mul_div        = ~EN_start_mul & ~EN_start_div;
    assign handshake_success =  (arvalid_o && arready_i) ||
                                (awvalid_o && awready_i && wvalid_o && wready_i);
    assign idle              = (no_mem_req & no_mul_div) || handshake_success || handshake_state ||
                                (EN_start_mul & mul_finish) || (EN_start_div & div_finish);
    assign valid_o           = valid && idle && (~has_flush_sign);
    assign exu_ready_o       = !valid || (valid_o && lsu_ready_i);
    assign exu_excp_bus_o    = { rfu_excp_bus[4], store_amo_addr_misalign,
                                 load_addr_misalign, rfu_excp_bus[3:0]};
    wire      stall;
    wire      exu_alu_result_forward_valid;
    wire      exu_gpr_forward_valid;
    wire      exu_valid;
    assign stall                 = ex_res_from_mem && valid;
    assign exu_alu_result_forward_valid = valid_o && (ex_rd != 5'b0) && ex_gr_we &&
                                          !ex_res_from_mem && !ex_res_from_pre && no_mul_div;
    assign exu_gpr_forward_valid = valid_o && (ex_rd != 5'b0) && ex_gr_we && !ex_res_from_mem;
    assign exu_valid             = valid && ex_csr_we;
    assign exu_alu_forward_valid = exu_alu_result_forward_valid;
    assign exu_alu_forward_data  = ex_alu_result;
    assign exu_forward_ctrl      = { exu_gpr_forward_valid, exu_valid, stall,
                                     ex_rd, ex_csr_addr };
    assign exu_forward_data      = final_result;

    assign is_skip_difftest = (awvalid_o || arvalid_o) && ( ex_alu_result[31:16] == 16'h1000 ||
                                                            ex_alu_result[31:16] == 16'h0200 ||
                                                            ex_alu_result[31:24] ==  8'h21   ||
                                                            ex_alu_result[31:16] == 16'h1001);
    `ifdef CONFIG_TRACE_PERFORMANCE
        import "DPI-C" function void exu_alu_count();
        always @(valid)
        begin
            if (!ex_res_from_pre && !ex_res_from_mem && !ex_branch && valid)
                exu_alu_count();
        end
    `endif
endmodule
