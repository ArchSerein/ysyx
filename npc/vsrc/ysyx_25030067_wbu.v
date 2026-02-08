`include "ysyx_25030067_riscv_param.vh"

module ysyx_25030067_wbu (
    input                           clock,
    input                           reset,
    input                           lsu_valid_i,
    input  [`LSU_WBU_BUS_WIDTH-1:0] lsu_wbu_bus_i,
    input  [ 8:0]                   lsu_excp_bus_i,

    output                          mret_flush,
    output                          excp_flush,
    // register file
    output [ 4:0]                   rf_rd_o,
    output [31:0]                   rf_wdata_o,
    output                          rf_we_o,
    // csr register
    output [11:0]                   csr_addr_o,
    output [31:0]                   csr_wdata_o,
    output                          csr_we_o,

    output [31:0]                   csr_mcause_o,
    output [31:0]                   csr_mepc_o,

    output [`FORWARD_BUS_WIDTH-1:0] wbu_forward_bus,

    output                          wbu_ready_o
);

    reg valid;
    reg [`LSU_WBU_BUS_WIDTH-1:0] lsu_wbu_bus;
    reg [ 8:0] lsu_excp_bus;

    wire [31:0] wbu_final_result;
    wire [31:0] wbu_csr_wdata;
    wire        wbu_gr_we;
    wire [ 4:0] wbu_rd;
    wire [11:0] wbu_csr_addr;
    wire        wbu_xret_flush;
    wire        wbu_csr_we;
    wire [31:0] wbu_pc;
    wire        is_skip_difftest;

    assign {
        is_skip_difftest,
        wbu_pc,
        wbu_csr_we,
        wbu_final_result,
        wbu_gr_we,
        wbu_rd,
        wbu_csr_addr,
        wbu_csr_wdata,
        wbu_xret_flush
    } = lsu_wbu_bus;

    assign rf_we_o = wbu_gr_we && valid;
    assign rf_rd_o = wbu_rd;
    assign rf_wdata_o = wbu_final_result;
    assign csr_we_o = wbu_csr_we && valid;
    assign csr_addr_o = wbu_csr_addr;
    assign csr_wdata_o = wbu_csr_wdata;

    wire has_flush_sign;
    always @(posedge clock) begin
        if (has_flush_sign) begin
            valid <= 1'b0;
        end if (lsu_valid_i) begin
            valid <= 1'b1;
        end else begin
            valid <= 1'b0;
        end
    end
    always @ (posedge clock) begin
      if (lsu_valid_i && wbu_ready_o) begin
        lsu_wbu_bus <= lsu_wbu_bus_i;
      end
    end
    always @ (posedge clock) begin
      if (lsu_valid_i && wbu_ready_o) begin
        lsu_excp_bus <= lsu_excp_bus_i;
      end
    end
    assign has_flush_sign = has_excp || reset || wbu_xret_flush;

    wire        has_excp;
    assign has_excp =   lsu_excp_bus[0] || lsu_excp_bus[1] || lsu_excp_bus[2] ||
                        lsu_excp_bus[3] || lsu_excp_bus[4] || lsu_excp_bus[5] ||
                        lsu_excp_bus[6] || lsu_excp_bus[7] || lsu_excp_bus[8];
                        // lsu_excp_bus[9] || lsu_excp_bus[11] || lsu_excp_bus[12] ||
                        // lsu_excp_bus[13] || lsu_excp_bus[15];
    assign csr_mepc_o = wbu_pc;
    assign csr_mcause_o = lsu_excp_bus[0] ? `INST_ADDR_MISALIGNED :
                          lsu_excp_bus[1] ? `INST_ACCESS_FAULT :
                          lsu_excp_bus[2] ? `ILLEGAL_INST :
                          lsu_excp_bus[3] ? `BREAKPOINT :
                          lsu_excp_bus[4] ? `LOAD_ADDR_MISALIGNED :
                          lsu_excp_bus[5] ? `LOAD_ACCESS_FAULT :
                          lsu_excp_bus[6] ? `STORE_AMO_ADDR_MISALIGNED :
                          lsu_excp_bus[7] ? `STORE_AMO_ACCESS_FAULT :
                          lsu_excp_bus[8] ? `ECALL_FROM_M_MODE :
                          32'h0;
                          // lsu_excp_bus[8] ? `ECALL_FROM_U_MODE :
                          // lsu_excp_bus[9] ? `ECALL_FROM_S_MODE :
                          // lsu_excp_bus[12] ? `INST_PAGE_FAULT :
                          // lsu_excp_bus[13] ? `LOAD_PAGE_FAULT :
                          // lsu_excp_bus[15] ? `STORE_AMO_PAGE_FAULT :

    assign wbu_ready_o = 1'b1;
    assign mret_flush = wbu_xret_flush && valid;
    assign excp_flush = has_excp && valid;

    wire wbu_gpr_forward_valid;
    wire wbu_valid;
    assign wbu_gpr_forward_valid = valid && (wbu_rd != 5'b0) && rf_we_o;
    assign wbu_valid = valid && csr_we_o;
    assign wbu_forward_bus = { wbu_gpr_forward_valid, wbu_valid, 1'b0, wbu_rd, wbu_csr_addr, wbu_final_result };

    reg [31:0]  cnt;
    always @(posedge clock) begin
      if (reset) begin
          cnt <= 32'b0;
      end else if (!valid) begin
          cnt <= cnt + 1;
      end else begin
          cnt <= 32'b0;
      end
    end

    import "DPI-C" function void ending(input int num);
    // break signal
    always @(*) begin
        if (lsu_excp_bus[3]) begin
            ending(1);
          end else if (cnt >= 32'h20000) begin
            ending(2);
          end
    end

    `ifdef CONFIG_DIFFTEST
        import "DPI-C" function void is_difftest(input byte difftest, input int pc, input byte skip);
        reg [ 7:0] difftest;
        always @(posedge clock) begin
            if (reset) begin
                difftest <= 8'b0;
            end else if (lsu_valid_i) begin
                difftest <= 8'b1;
            end else begin
                difftest <= 8'b0;
            end
            is_difftest(difftest, wbu_pc, {is_skip_difftest, has_excp, csr_mcause_o[5:0]});
        end
    `endif
    `ifdef CONFIG_TRACE_PERFORMANCE
        import "DPI-C" function void inst_count();
        always @(posedge clock)
        begin
            if (!reset && valid)
                inst_count();
        end
    `endif

endmodule
