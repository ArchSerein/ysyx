`include "./include/generated/autoconf.vh"
`include "riscv_param.vh"
`include "csr.vh"

module ysyx_25030067_ifu (
    input                               clock,
    input                               reset,

    input                               excp_flush,
    input                               mret_flush,
    // csr register
    input  [`CSR_DATA_WIDTH-1:0]        csr_mtvec,
    input  [`CSR_DATA_WIDTH-1:0]        csr_mepc,

    input                               branch_flush,
    input  [31:0]                       branch_target,

    output                              valid_o,
    output [`IFU_ICU_BUS_WIDTH-1:0]     ifu_icu_bus_o,
    output                              ifu_excp_bus_o,
    input                               ready_i
);

    localparam YSYXSOC_RESET_PC = 32'h30000000;

    reg  [31:0] ifu_pc;
    wire [31:0] snpc;
    assign snpc = ifu_pc + 4;

    wire [31:0] dnpc;
    assign dnpc =   excp_flush ? csr_mtvec :
                    mret_flush ? csr_mepc :
                    branch_flush ? branch_target :
                    snpc;

    wire [31:0] next_pc;
    assign next_pc = (reset) ? YSYXSOC_RESET_PC : dnpc;

    wire handshake_succ;
    reg  valid;
    always @ (posedge clock) begin
        if (handshake_succ || reset || branch_flush || excp_flush || mret_flush) begin
          ifu_pc <= next_pc;
        end
    end

    always @ (posedge clock) begin
      if (reset || branch_flush || excp_flush || mret_flush) begin
        valid <= 1'b0;
      end else if (ready_i) begin
        valid <= 1'b1;
      end else if (handshake_succ) begin
        valid <= 1'b0;
      end
    end
    assign handshake_succ = valid && valid_o && ready_i;

    assign ifu_icu_bus_o = {ifu_pc, snpc};
    assign valid_o = valid && !branch_flush && !excp_flush && !mret_flush;
    assign ifu_excp_bus_o = ifu_pc[1] || ifu_pc[0];

endmodule
