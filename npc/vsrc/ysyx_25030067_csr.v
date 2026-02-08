`include "ysyx_25030067_csr.vh"

 module ysyx_25030067_csr (
    input                           clock,
    input                           reset,
    input                           csr_we_i,
    input  [`CSR_ADDR_WIDTH-1:0]    csr_waddr_i,
    input  [`CSR_ADDR_WIDTH-1:0]    csr_raddr_i,
    input  [`CSR_DATA_WIDTH-1:0]    csr_wdata_i,

    input                           excp_flush,
    input  [`CSR_DATA_WIDTH-1:0]    csr_mcause_i,
    input  [`CSR_DATA_WIDTH-1:0]    csr_mepc_i,
    // ifu
    output [`CSR_DATA_WIDTH-1:0]    csr_mtvec_o,
    output [`CSR_DATA_WIDTH-1:0]    csr_mepc_o,

    output [`CSR_DATA_WIDTH-1:0]    csr_rdata_o
 );

    reg     [`CSR_DATA_WIDTH-1:0]    MCAUSE;
    reg     [`CSR_DATA_WIDTH-1:0]    MSTATUS;
    reg     [`CSR_DATA_WIDTH-1:0]    MTVEC;
    reg     [`CSR_DATA_WIDTH-1:0]    MEPC;
    reg     [`CSR_DATA_WIDTH-1:0]    MVENDORID;
    reg     [`CSR_DATA_WIDTH-1:0]    MARCHID;

    wire                    csr_mcause_we;
    wire                    csr_mstatus_we;
    wire                    csr_mtvec_we;
    wire                    csr_mepc_we;

    assign csr_mcause_we = excp_flush;
    assign csr_mstatus_we = csr_we_i && (csr_waddr_i == `CSR_ADDR_MSTATUS);
    assign csr_mtvec_we = csr_we_i && (csr_waddr_i == `CSR_ADDR_MTVEC);
    assign csr_mepc_we = excp_flush || (csr_we_i && (csr_waddr_i == `CSR_ADDR_MEPC));

    always @(posedge clock) begin
        if (reset) begin
            MCAUSE <= 0;
        end
        else if (csr_mcause_we) begin
            MCAUSE <= csr_mcause_i;
        end
    end

    always @(posedge clock) begin
        if (reset) begin
            MSTATUS <= 0;
        end
        else if (csr_mstatus_we) begin
            MSTATUS <= csr_wdata_i;
        end
    end

    always @(posedge clock) begin
        if (reset) begin
            MTVEC <= 0;
        end
        else if (csr_mtvec_we) begin
            MTVEC <= csr_wdata_i;
        end
    end

    wire    [`CSR_DATA_WIDTH-1:0] csr_mepc_w;
    always @(posedge clock) begin
        if (reset) begin
            MEPC <= 0;
        end
        else if (csr_mepc_we) begin
            MEPC <= csr_mepc_w;
        end
    end
    assign csr_mepc_w = excp_flush ? csr_mepc_i : csr_wdata_i;

    always @(posedge clock) begin
        if (reset) begin
            MVENDORID <= 32'h78797379;
        end
    end

    always @(posedge clock) begin
        if (reset) begin
            MARCHID <= 32'h17dc6a3;
        end
    end

    assign csr_rdata_o = {32{csr_raddr_i == `CSR_ADDR_MCAUSE}} & MCAUSE |
                         {32{csr_raddr_i == `CSR_ADDR_MSTATUS}} & MSTATUS |
                         {32{csr_raddr_i == `CSR_ADDR_MTVEC}} & MTVEC |
                         {32{csr_raddr_i == `CSR_ADDR_MEPC}} & MEPC |
                         {32{csr_raddr_i == `CSR_ADDR_MVENDORID}} & MVENDORID |
                         {32{csr_raddr_i == `CSR_ADDR_MARCHID}} & MARCHID;
    assign csr_mtvec_o = MTVEC;
    assign csr_mepc_o = MEPC;

 endmodule
