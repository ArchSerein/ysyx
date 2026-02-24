`include "ysyx_25030067_csr.vh"
`include "ysyx_25030067_riscv_param.vh"

module ysyx_25030067_core (
    input                       clock,
    input                       reset,

    input                       icache_arready,
    output                      icache_arvalid,
    output  [31:0]              icache_araddr,
    output  [ 1:0]              icache_arburst,
    output  [ 7:0]              icache_arlen,
    output  [ 2:0]              icache_arsize,

    input                       icache_rlast,
    output                      icache_rready,
    input                       icache_rvalid,
    input   [31:0]              icache_rdata,
    input   [ 1:0]              icache_rresp,

    input                       dcache_arready,
    output  [ 7:0]              dcache_arlen,
    output  [ 2:0]              dcache_arsize,
    output  [ 1:0]              dcache_arburst,
    output                      dcache_arvalid,
    output  [`ADDR_WIDTH-1:0]   dcache_araddr,

    input                       dcache_rvalid,
    input   [`DATA_WIDTH-1:0]   dcache_rdata,
    input   [ 1:0]              dcache_rresp,
    input                       dcache_rlast,
    output                      dcache_rready,

    // axi write channal
    // to memory
    input                       dcache_awready,
    output                      dcache_awvalid,
    output  [31: 0]             dcache_awaddr,
    output  [ 7:0]              dcache_awlen,
    output  [ 2:0]              dcache_awsize,
    output  [ 1:0]              dcache_awburst,

    input                       dcache_wready,
    output                      dcache_wvalid,
    output  [31: 0]             dcache_wdata,
    output  [ 3: 0]             dcache_wstrb,
    output                      dcache_wlast,

    // from memory
    input                       dcache_bvalid,
    output                      dcache_bready,
    input   [ 1: 0]             dcache_bresp
);

    wire [`IFU_ICU_BUS_WIDTH-1:0]    ifu_icu_bus;
    wire                             ifu_valid;

    wire [`CSR_DATA_WIDTH-1:0]       csr_mtvec;
    wire [`CSR_DATA_WIDTH-1:0]       csr_mepc;
    wire [`CSR_DATA_WIDTH-1:0]       csr_mepc_w;
    wire [`CSR_DATA_WIDTH-1:0]       csr_mcause_w;

    wire                             cache_flush;
    wire                             icache_ready;

    wire                             rfu_ready;

    wire                             branch_flush;
    wire [31:0]                      branch_target;
    wire [31:0]                      cache_flush_target;

    wire                             excp_flush;
    wire                             mret_flush;
    wire                             wait_cache_flush;

    wire                             ifu_excp_bus;
    wire [ 1:0]                      icu_excp_bus;
    wire [ 4:0]                      deu_excp_bus;
    wire [ 4:0]                      rfu_excp_bus;
    wire [ 6:0]                      exu_excp_bus;
    wire [ 8:0]                      lsu_excp_bus;

    wire [`ICU_DEU_BUS_WIDTH-1:0]    icu_deu_bus;
    wire                             icache_valid;
    wire deu_ready;

    wire [`DEU_RFU_BUS_WIDTH-1:0] deu_rfu_bus;
    wire deu_valid;
    wire exu_ready;

    wire [ 4:0] rs1;
    wire [ 4:0] rs2;
    wire [31:0] rs1_value;
    wire [31:0] rs2_value;

    wire [11:0] csr_raddr;
    wire [31:0] csr_value;

    wire [`RFU_EXU_BUS_WIDTH-1:0] rfu_exu_bus;
    wire rfu_valid;
    wire [`FORWARD_BUS_WIDTH-1:0] exu_forward_bus;
    wire [`FORWARD_BUS_WIDTH-1:0] lsu_forward_bus;
    wire [`FORWARD_BUS_WIDTH-1:0] wbu_forward_bus;

    wire [`EXU_LSU_BUS_WIDTH-1:0] exu_lsu_bus;
    wire exu_valid;
    wire lsu_ready;

    // wire [31:0] mem_rdata;
    wire [`LSU_WBU_BUS_WIDTH-1:0] lsu_wbu_bus;
    wire lsu_valid;
    wire wbu_ready;

    wire          exu_arvalid;
    wire          exu_awvalid;
    wire          exu_wvalid;
    wire          exu_arready;
    wire          exu_awready;
    wire          exu_wready;
    wire          lsu_rvalid;
    wire          lsu_bvalid;
    wire          lsu_rready;
    wire          lsu_bready;
    wire  [31: 0] exu_araddr;
    wire  [31: 0] exu_awaddr;
    wire  [31: 0] exu_wdata;
    wire  [31: 0] lsu_rdata;
    wire  [ 2: 0] exu_arsize;
    wire  [ 2: 0] exu_awsize;
    wire  [ 3: 0] exu_wstrb;
    wire  [ 1: 0] lsu_rresp;
    wire  [ 1: 0] lsu_bresp;

    wire          rf_we;
    wire          csr_we;
    wire [31: 0]  rf_wdata;
    wire [ 4: 0]  rd;
    wire [31: 0]  csr_wdata;
    wire [11: 0]  csr_waddr;

    wire          btb_valid;
    wire          predict_taken;
    wire          exu_br_taken;
    wire [31: 0]  predict_pc;

    ysyx_25030067_bpu ysyx_25030067_bpu_module (
      .clock              (clock),
      .reset              (reset),

      .exu_valid_i        (exu_valid),
      .exu_br_taken_i     (exu_br_taken),

      .predict_taken_o    (predict_taken)
    );

    ysyx_25030067_btb ysyx_25030067_btb_module (
      .clock          (clock),
      .reset          (reset),

      .ifu_pc_i       (ifu_icu_bus[`IFU_ICU_BUS_PC]),
      .btb_valid_o    (btb_valid),
      .predict_pc_o   (predict_pc),

      .exu_valid_i    (exu_valid),
      .exu_pc_i       (exu_lsu_bus[`EXU_LSU_BUS_PC]),
      .exu_br_taken_i (branch_flush),
      .exu_target_i   (branch_target)
    );

    ysyx_25030067_ifu ysyx_25030067_ifu_module (
        .clock          (clock),
        .reset          (reset),

        .cache_flush    (cache_flush),
        .cache_flush_target
                        (cache_flush_target),
        .excp_flush     (excp_flush),
        .mret_flush     (mret_flush),
        .wait_cache_flush
                        (wait_cache_flush),

        // branch prefictor
        .btb_valid_i    (btb_valid),
        .predict_taken_i(predict_taken),
        .predict_pc_i   (predict_pc),

        // csr register
        .csr_mtvec      (csr_mtvec),
        .csr_mepc       (csr_mepc),

        .ifu_icu_bus_o  (ifu_icu_bus),
        .ifu_excp_bus_o (ifu_excp_bus),

        .branch_flush   (branch_flush),
        .branch_target  (branch_target),

        .ready_i        (icache_ready),
        .valid_o        (ifu_valid)
    );

    ysyx_25030067_icache ysyx_25030067_icache_module (
      .clock            (clock),
      .reset            (reset),

      .excp_flush       (excp_flush),
      .mret_flush       (mret_flush),

      .ready_o          (icache_ready),
      .ifu_valid_i      (ifu_valid),
      .ifu_icu_bus_i    (ifu_icu_bus),
      .ifu_excp_bus_i   (ifu_excp_bus),

      .wait_cache_flush (wait_cache_flush),
      .branch_flush     (branch_flush),
      .icache_flush     (cache_flush),

      .valid_o          (icache_valid),
      .icu_deu_bus_o    (icu_deu_bus),
      .icu_excp_bus_o   (icu_excp_bus),
      .deu_ready_i      (deu_ready),

      .icache_arready_i (icache_arready),
      .icache_arvalid_o (icache_arvalid),
      .icache_araddr_o  (icache_araddr),
      .icache_arburst_o (icache_arburst),
      .icache_arlen_o   (icache_arlen),
      .icache_arsize_o  (icache_arsize),

      .icache_rlast_i   (icache_rlast),
      .icache_rvalid_i  (icache_rvalid),
      .icache_rdata_i   (icache_rdata),
      .icache_rresp_i   (icache_rresp),
      .icache_rready_o  (icache_rready)
    );

    ysyx_25030067_deu ysyx_25030067_deu_module (
        .clock          (clock),
        .reset          (reset),

        .excp_flush     (excp_flush),
        .mret_flush     (mret_flush),

        .icu_valid_i    (icache_valid),
        .icu_deu_bus_i  (icu_deu_bus),
        .icu_excp_bus_i (icu_excp_bus),

        .deu_ready_o    (deu_ready),
        .deu_rfu_bus_o  (deu_rfu_bus),
        .deu_excp_bus_o (deu_excp_bus),

        .cache_flush_target
                        (cache_flush_target),
        .cache_flush    (cache_flush),
        .branch_flush   (branch_flush),
        .wait_cache_flush
                        (wait_cache_flush),

        .rfu_ready_i    (rfu_ready),
        .valid_o        (deu_valid)
    );

    ysyx_25030067_rfu ysyx_25030067_rfu_module (
        .clock          (clock),
        .reset          (reset),

        .excp_flush     (excp_flush),
        .mret_flush     (mret_flush),
        .wait_cache_flush
                        (wait_cache_flush),

        .deu_valid_i    (deu_valid),
        .exu_ready_i    (exu_ready),
        .deu_rfu_bus_i  (deu_rfu_bus),
        .deu_excp_bus_i (deu_excp_bus),

        // regfile
        .rfu_rs1_o      (rs1),
        .rfu_rs2_o      (rs2),
        .rfu_rs1_value_i(rs1_value),
        .rfu_rs2_value_i(rs2_value),

        // csr register
        .rfu_csr_addr_o (csr_raddr),
        .rfu_csr_value_i(csr_value),

        .branch_flush   (branch_flush),

        .rfu_exu_bus_o  (rfu_exu_bus),
        .rfu_excp_bus_o (rfu_excp_bus),

        .exu_forward_bus(exu_forward_bus),
        .lsu_forward_bus(lsu_forward_bus),
        .wbu_forward_bus(wbu_forward_bus),

        .rfu_ready_o    (rfu_ready),
        .valid_o        (rfu_valid)
    );

    ysyx_25030067_exu ysyx_25030067_exu_module (
        .clock          (clock),
        .reset          (reset),

        .excp_flush     (excp_flush),
        .mret_flush     (mret_flush),

        .rfu_valid_i    (rfu_valid),
        .lsu_ready_i    (lsu_ready),
        .rfu_exu_bus_i  (rfu_exu_bus),
        .rfu_excp_bus_i (rfu_excp_bus),

        .arready_i      (exu_arready),
        .araddr_o       (exu_araddr),
        .arsize_o       (exu_arsize),
        .arvalid_o      (exu_arvalid),

        .awready_i      (exu_awready),
        .awaddr_o       (exu_awaddr),
        .awsize_o       (exu_awsize),
        .awvalid_o      (exu_awvalid),

        .wready_i       (exu_wready),
        .wdata_o        (exu_wdata),
        .wstrb_o        (exu_wstrb),
        .wvalid_o       (exu_wvalid),

        .ex_br_taken_o  (exu_br_taken),
        .branch_flush   (branch_flush),
        .branch_target  (branch_target),

        .exu_forward_bus(exu_forward_bus),

        .exu_excp_bus_o (exu_excp_bus),
        .exu_lsu_bus_o  (exu_lsu_bus),
        .exu_ready_o    (exu_ready),
        .valid_o        (exu_valid)
    );

    ysyx_25030067_dcache ysyx_25030067_dcache_module (
        .clock                (clock),
        .reset                (reset),

        // NOTE:
        // exu <--- dcache ---> lsu
        .exu_arvalid_i        (exu_arvalid),
        .dcache_arready_o     (exu_arready),
        .exu_arsize_i         (exu_arsize),
        .exu_araddr_i         (exu_araddr),

        .dcache_rdata_o       (lsu_rdata),
        .dcache_rvalid_o      (lsu_rvalid),
        .dcache_rresp_o       (lsu_rresp),
        .lsu_rready_i         (lsu_rready),

        .exu_awvalid_i        (exu_awvalid),
        .dcache_awready_o     (exu_awready),
        .exu_awaddr_i         (exu_awaddr),
        .exu_awsize_i         (exu_awsize),

        .exu_wvalid_i         (exu_wvalid),
        .dcache_wready_o      (exu_wready),
        .exu_wdata_i          (exu_wdata),
        .exu_wstrb_i          (exu_wstrb),

        .dcache_bresp_o       (lsu_bresp),
        .dcache_bvalid_o      (lsu_bvalid),
        .lsu_bready_i         (lsu_bready),

        .dcache_flush         (cache_flush),
        .wait_cache_flush     (wait_cache_flush),

        // NOTE:
        // dcache <----> memory
        .dcache_arready_i     (dcache_arready),
        .dcache_arlen_o       (dcache_arlen),
        .dcache_arsize_o      (dcache_arsize),
        .dcache_arburst_o     (dcache_arburst),
        .dcache_arvalid_o     (dcache_arvalid),
        .dcache_araddr_o      (dcache_araddr),

        .dcache_rvalid_i      (dcache_rvalid),
        .dcache_rdata_i       (dcache_rdata),
        .dcache_rresp_i       (dcache_rresp),
        .dcache_rlast_i       (dcache_rlast),
        .dcache_rready_o      (dcache_rready),

        .dcache_awready_i     (dcache_awready),
        .dcache_awvalid_o     (dcache_awvalid),
        .dcache_awaddr_o      (dcache_awaddr),
        .dcache_awlen_o       (dcache_awlen),
        .dcache_awsize_o      (dcache_awsize),
        .dcache_awburst_o     (dcache_awburst),

        .dcache_wready_i      (dcache_wready),
        .dcache_wvalid_o      (dcache_wvalid),
        .dcache_wdata_o       (dcache_wdata),
        .dcache_wstrb_o       (dcache_wstrb),
        .dcache_wlast_o       (dcache_wlast),

        .dcache_bvalid_i      (dcache_bvalid),
        .dcache_bready_o      (dcache_bready),
        .dcache_bresp_i       (dcache_bresp)
    );

    ysyx_25030067_lsu ysyx_25030067_lsu_module (
        .clock          (clock),
        .reset          (reset),

        .excp_flush     (excp_flush),
        .mret_flush     (mret_flush),

        .exu_valid_i    (exu_valid),
        .wbu_ready_i    (wbu_ready),
        .exu_lsu_bus_i  (exu_lsu_bus),
        .exu_excp_bus_i (exu_excp_bus),

        .rdata_i        (lsu_rdata),
        .rresp_i        (lsu_rresp),
        .rvalid_i       (lsu_rvalid),
        .rready_o       (lsu_rready),

        .bresp_i        (lsu_bresp),
        .bvalid_i       (lsu_bvalid),
        .bready_o       (lsu_bready),

        .lsu_forward_bus(lsu_forward_bus),

        .lsu_excp_bus_o (lsu_excp_bus),
        .lsu_wbu_bus_o  (lsu_wbu_bus),
        .lsu_ready_o    (lsu_ready),
        .valid_o        (lsu_valid)
    );

    ysyx_25030067_wbu ysyx_25030067_wbu_module (
        .clock          (clock),
        .reset          (reset),
        .lsu_valid_i    (lsu_valid),
        .lsu_wbu_bus_i  (lsu_wbu_bus),
        .lsu_excp_bus_i (lsu_excp_bus),
        // register file
        .rf_rd_o        (rd),
        .rf_wdata_o     (rf_wdata),
        .rf_we_o        (rf_we),
        // csr register
        .csr_addr_o     (csr_waddr),
        .csr_wdata_o    (csr_wdata),
        .csr_we_o       (csr_we),

        .excp_flush     (excp_flush),
        .mret_flush     (mret_flush),
        .csr_mcause_o   (csr_mcause_w),
        .csr_mepc_o     (csr_mepc_w),

        .wbu_forward_bus(wbu_forward_bus),

        .wbu_ready_o    (wbu_ready)
    );

    // regfile
    ysyx_25030067_regfile ysyx_25030067_regfile_module (
        .clock          (clock),
        .reset          (reset),
        .reg_src1_i     (rs1),
        .reg_src2_i     (rs2),
        .reg_dst_i      (rd),
        .reg_wen_i      (rf_we),
        .reg_wdata_i    (rf_wdata),
        .reg_rdata1_o   (rs1_value),
        .reg_rdata2_o   (rs2_value)
    );

    // csr register
    ysyx_25030067_csr ysyx_25030067_csr_module (
        .clock          (clock),
        .reset          (reset),
        .csr_we_i       (csr_we),
        .csr_raddr_i    (csr_raddr),
        .csr_waddr_i    (csr_waddr),
        .csr_wdata_i    (csr_wdata),
        // ifu
        .csr_mtvec_o    (csr_mtvec),
        .csr_mepc_o     (csr_mepc),

        .excp_flush     (excp_flush),
        .csr_mepc_i     (csr_mepc_w),
        .csr_mcause_i   (csr_mcause_w),

        .csr_rdata_o    (csr_value)
    );

endmodule
