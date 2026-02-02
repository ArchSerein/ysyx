`include "./include/generated/autoconf.vh"
`include "riscv_param.vh"
module ysyx_25030067_lsu (
    input                               clock,
    input                               reset,

    input                               excp_flush,
    input                               mret_flush,

    input                               exu_valid_i,
    input                               wbu_ready_i,
    input  [`EXU_LSU_BUS_WIDTH-1:0]     exu_lsu_bus_i,
    input  [ 6:0]                       exu_excp_bus_i,
    // read data channel
    input  [31:0]                       rdata_i,
    input  [ 1:0]                       rresp_i,
    input                               rvalid_i,
    output                              rready_o,

    // wirte response channel
    input  [ 1:0]                       bresp_i,
    input                               bvalid_i,
    output                              bready_o,

    output [`FORWARD_BUS_WIDTH-1:0]     lsu_forward_bus,

    output [`LSU_WBU_BUS_WIDTH-1:0]     lsu_wbu_bus_o,
    output [ 8:0]                       lsu_excp_bus_o,
    output                              lsu_ready_o,
    output                              valid_o
);

    localparam INST_OK      = 2'b00;
    localparam INST_EXOKAY  = 2'b01;
    localparam INST_SLVERR  = 2'b10;
    localparam INST_DECERR  = 2'b11;

    reg valid;
    reg  [`EXU_LSU_BUS_WIDTH-1:0] exu_lsu_bus;
    reg  [ 6:0] exu_excp_bus;
    wire [31:0] ms_csr_value;
    wire [31:0] ms_csr_wdata;
    wire        ms_res_from_mem;
    wire        ms_gr_we;
    wire [ 4:0] ms_rd;
    wire [ 3:0] ms_mem_re;
    wire        ms_mem_we;
    wire [11:0] ms_csr_addr;
    wire        ms_xret_flush;
    wire [ 1:0] ms_mem_addr_mask;
    wire [ 3:0] ms_mem_re;
    wire        ms_csr_we;
    wire [31:0] ms_final_result;
    wire [31:0] ms_pc;
    wire        is_skip_difftest;
    
    assign {
        is_skip_difftest,
        ms_pc,
        ms_csr_wdata,
        ms_csr_we,
        ms_mem_addr_mask,
        ms_mem_re,
        ms_mem_we,
        ms_csr_addr,
        ms_res_from_mem,
        ms_gr_we,
        ms_rd,
        ms_xret_flush,
        ms_final_result
    } = exu_lsu_bus;

    wire [ 7:0] ms_byteload;
    wire [15:0] ms_halfload;
    wire [31:0] ms_wordload;
    wire [31:0] ms_result;
    wire [31:0] final_result;

    assign ms_byteload =   {8{ms_mem_addr_mask == 2'b00}} & rdata_i[7:0] |
                           {8{ms_mem_addr_mask == 2'b01}} & rdata_i[15:8] |
                           {8{ms_mem_addr_mask == 2'b10}} & rdata_i[23:16] |
                           {8{ms_mem_addr_mask == 2'b11}} & rdata_i[31:24];

    assign ms_halfload =   {16{ms_mem_addr_mask == 2'b00}} & rdata_i[15:0] |
                           {16{ms_mem_addr_mask == 2'b10}} & rdata_i[31:16];

    assign ms_wordload =   rdata_i;

    assign ms_result   =    {32{ms_mem_re == 4'b1111}} & ms_wordload |
                            {32{ms_mem_re == 4'b0111}} & {{16{ms_halfload[15]}}, ms_halfload} |
                            {32{ms_mem_re == 4'b0011}} & {{16'b0}, ms_halfload} |
                            {32{ms_mem_re == 4'b0101}} & {{24{ms_byteload[7]}}, ms_byteload} |
                            {32{ms_mem_re == 4'b0001}} & {{24'b0}, ms_byteload};

    assign final_result = ms_res_from_mem ? ms_result : ms_final_result;

    always @(posedge clock) begin
        if (exu_valid_i && lsu_ready_o) begin
            exu_lsu_bus <= exu_lsu_bus_i;
        end
    end
    always @(posedge clock) begin
      if (exu_valid_i && lsu_ready_o) begin
          exu_excp_bus <= exu_excp_bus_i;
      end
    end

    `ifdef CONFIG_TRACE_PERFORMANCE
        import "DPI-C" function void lsu_load_store_count();
        import "DPI-C" function void mem_cycle_count();
        always @ (posedge clock) begin
          if (resp_handshake_succ) begin
            lsu_load_store_count();
          end
          if (bready_o || rready_o) begin
            mem_cycle_count();
          end
        end
    `endif

    wire resp_handshake_succ;
    wire no_mem_resp;
    wire condition;
    wire has_flush_sign;
    always @(posedge clock) begin
      if (has_flush_sign) begin
        valid <= 1'b0;
      end else if (exu_valid_i) begin
        valid <= 1'b1;
      end else if (condition) begin
        valid <= 1'b0;
      end
    end
    assign resp_handshake_succ = (bvalid_i && bready_o) || (rvalid_i && rready_o);
    assign no_mem_resp = !(bready_o || rready_o);
    assign has_flush_sign = reset || excp_flush || mret_flush;
    assign condition = (resp_handshake_succ || no_mem_resp) && valid;

    assign lsu_wbu_bus_o = {
        is_skip_difftest,
        ms_pc,
        ms_csr_we,
        final_result,
        ms_gr_we,
        ms_rd,
        ms_csr_addr,
        ms_csr_wdata,
        ms_xret_flush
    };
    /* 1 + 32 + 1 + 5 + 12 + 32 + 1 + 1 + 1 = 86*/

    assign lsu_excp_bus_o = {
      exu_excp_bus[6],
      bvalid_i && bresp_i[1],
      exu_excp_bus[5],
      rvalid_i && rresp_i[1],
      exu_excp_bus[4:0]
    };
    assign bready_o = ms_mem_we && valid;
    assign rready_o = |ms_mem_re && valid;

    wire stall;
    assign stall = !resp_handshake_succ && !no_mem_resp;
    wire lsu_gpr_forward_valid;
    wire lsu_valid;
    assign lsu_gpr_forward_valid = valid && (ms_rd != 5'b0) && ms_gr_we;
    assign lsu_valid = valid && ms_csr_we;

    assign valid_o = condition;
    assign lsu_ready_o = !valid || (condition && wbu_ready_i);
    assign lsu_forward_bus = { lsu_gpr_forward_valid, lsu_valid, stall, ms_rd, ms_csr_addr, final_result };
endmodule
