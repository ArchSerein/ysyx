`include "autoconf.vh"
`include "ysyx_25030067_riscv_param.vh"

module ysyx_25030067_iwrapper (
  input                           clock,
  input                           reset,

  input                           ifu_valid_i,
  input  [`IFU_ICU_BUS_WIDTH-1:0] ifu_icu_bus_i,
  input                           ifu_excp_bus_i,
  output                          ready_o,
  output [`ICU_DEU_BUS_WIDTH-1:0] icu_deu_bus_o,
  output [1:0]                    icu_excp_bus_o,
  output                          valid_o,
  input                           deu_ready_i,

  input                           excp_flush,
  input                           mret_flush,
  input                           branch_flush,
  input                           icache_flush,
  output                          wait_cache_flush,

  output                          i_ptw_req_valid_o,
  input                           i_ptw_req_ready_i,
  output [31:0]                   i_ptw_req_vaddr_o,
  input                           i_ptw_resp_valid_i,
  input  [21:0]                   i_ptw_resp_ppn_i,
  input  [6:0]                    i_ptw_resp_perm_i,
  input                           i_ptw_resp_level_i,
  input                           i_ptw_page_fault_i,
  input                           i_ptw_access_fault_i,

  input  [31:0]                   satp_i,
  input  [31:0]                   mstatus_i,
  input  [1:0]                    priv_mode_i,
  input                           sfence_vma_i,

  output                          arvalid_o,
  input                           arready_i,
  output [31:0]                   araddr_o,
  output [7:0]                    arlen_o,
  output [2:0]                    arsize_o,
  output [1:0]                    arburst_o,

  input                           rvalid_i,
  input  [31:0]                   rdata_i,
  input  [1:0]                    rresp_i,
  input                           rlast_i,
  output                          rready_o
);

  localparam READY        = 2'b00;
  localparam WAITTLB      = 2'b01;
  localparam SENDFILLREQ  = 2'b10;
  localparam WAITFILLRESP = 2'b11;

  localparam PRIV_U       = 2'b00;
  localparam PRIV_S       = 2'b01;
  localparam PRIV_M       = 2'b11;
  localparam TAG_WIDTH    = `DATA_WIDTH - `CONFIG_ICACHE_BLOCKS_WIDTH -
                            `CONFIG_ICACHE_SETS_WIDTH - 2;
  localparam BLOCKS_WIDTH = `CONFIG_ICACHE_BLOCKS_WIDTH;
  localparam LINE_LAST    = `CONFIG_ICACHE_BLOCKS - 1;

  reg  [`IFU_ICU_BUS_WIDTH-1:0] ifu_icu_bus;
  reg                           ifu_excp_bus;
  reg                           valid;
  reg  [1:0]                    state;
  reg  [31:0]                   miss_vaddr;
  reg  [33:0]                   miss_paddr;
  reg                           miss_uncache;
  reg  [BLOCKS_WIDTH-1:0]       fill_ptr;
  reg                           uncache_resp_valid;
  reg                           fault_resp_valid;
  reg  [31:0]                   uncache_rdata;
  reg                           uncache_fault;

  wire [31:0]                   req_vaddr;
  wire [31:0]                   req_snpc;
  wire [33:0]                   direct_paddr;
  wire [33:0]                   tlb_paddr;
  wire [33:0]                   lookup_paddr;
  wire [33:0]                   ptw_paddr;
  wire [TAG_WIDTH-1:0]          lookup_ptag;
  wire [TAG_WIDTH-1:0]          ptw_ptag;
  wire                          vm_en;
  wire [8:0]                    satp_asid;
  wire                          tlb_lookup_valid;
  wire                          tlb_hit;
  wire [21:0]                   tlb_ppn;
  wire [6:0]                    tlb_perm;
  wire                          tlb_write_valid;
  wire                          tlb_perm_ok;
  wire                          lookup_use_ptw;
  wire                          cache_lookup_valid;
  wire                          cache_hit;
  wire [31:0]                   cache_rdata;
  wire                          curr_fault;
  wire                          has_flush_sign;
  wire                          issue_miss;
  wire                          tlb_miss;
  wire                          waittlb_resp_ok;
  wire                          waittlb_cache_miss;
  wire                          fill_data_valid;
  wire                          fill_done;
  wire [1:0]                    ready_next_state;
  wire [1:0]                    waittlb_next_state;
  wire [1:0]                    sendfillreq_next_state;
  wire [1:0]                    waitfillresp_next_state;
  wire [1:0]                    state_next;
  wire                          valid_next;
  wire                          consume_resp;
  wire [31:0]                   inst_data;
  wire                          resp_valid;
  wire                          fetch_fault;
  wire                          tlb_u;
  wire                          tlb_x;
  wire                          tlb_a;
  wire                          tlb_priv_ok;
  wire                          tlb_type_ok;
  wire                          lookup_hit_ready;
  wire                          _unused_ok;
  wire [31:0]                   cache_vaddr_unused;
  wire [31:0]                   cache_snpc_unused;

  assign {req_vaddr, req_snpc} = ifu_icu_bus;
  assign satp_asid = satp_i[30:22];
  assign vm_en = satp_i[31] && (priv_mode_i != PRIV_M);

  assign direct_paddr = {2'b00, req_vaddr};
  assign tlb_paddr = {tlb_ppn, req_vaddr[11:0]};
  assign ptw_paddr = {i_ptw_resp_ppn_i, miss_vaddr[11:0]};

  assign lookup_use_ptw = (state == WAITTLB) && waittlb_resp_ok;
  assign lookup_paddr = ({34{lookup_use_ptw}} & ptw_paddr) |
                        ({34{!lookup_use_ptw && vm_en}} & tlb_paddr) |
                        ({34{!lookup_use_ptw && !vm_en}} & direct_paddr);
  assign lookup_ptag = lookup_paddr[`DATA_WIDTH-1:`CONFIG_ICACHE_BLOCKS_WIDTH+`CONFIG_ICACHE_SETS_WIDTH+2];
  assign ptw_ptag = ptw_paddr[`DATA_WIDTH-1:`CONFIG_ICACHE_BLOCKS_WIDTH+`CONFIG_ICACHE_SETS_WIDTH+2];
  assign tlb_lookup_valid = valid && (state == READY) && vm_en;
  assign tlb_write_valid = i_ptw_resp_valid_i && !i_ptw_page_fault_i && !i_ptw_access_fault_i;

  ysyx_25030067_tlb u_itlb (
    .clock              (clock),
    .reset              (reset),
    .lookup_valid_i     (tlb_lookup_valid),
    .lookup_vpn_i       (req_vaddr[31:12]),
    .lookup_asid_i      (satp_asid),
    .lookup_hit_o       (tlb_hit),
    .lookup_ppn_o       (tlb_ppn),
    .lookup_perm_o      (tlb_perm),
    .write_valid_i      (tlb_write_valid),
    .write_vpn_i        (miss_vaddr[31:12]),
    .write_asid_i       (satp_asid),
    .write_ppn_i        (i_ptw_resp_ppn_i),
    .write_perm_i       (i_ptw_resp_perm_i),
    .write_page_level_i (i_ptw_resp_level_i),
    .flush_all_i        (sfence_vma_i),
    .flush_vma_i        (1'b0),
    .flush_asid_valid_i (1'b0),
    .flush_asid_i       (9'b0),
    .flush_vpn_valid_i  (1'b0),
    .flush_vpn_i        (20'b0)
  );

  assign tlb_u = tlb_perm[3];
  assign tlb_x = tlb_perm[2];
  assign tlb_a = tlb_perm[5];
  assign tlb_type_ok = tlb_x;
  assign tlb_priv_ok = ({1{priv_mode_i == PRIV_U}} & tlb_u) |
                       ({1{priv_mode_i == PRIV_S}} & !tlb_u) |
                       ({1{priv_mode_i == PRIV_M}} & 1'b1);
  assign tlb_perm_ok = tlb_type_ok && tlb_priv_ok && tlb_a;

  assign tlb_miss = vm_en && !tlb_hit;
  assign curr_fault = (vm_en && tlb_hit && !tlb_perm_ok);

  assign cache_lookup_valid = valid &&
                              ((state == READY && (!vm_en || tlb_hit)) ||
                               (state == WAITTLB && waittlb_resp_ok));

  ysyx_25030067_icache u_icache (
    .clock          (clock),
    .reset          (reset),
    .lookup_valid_i (cache_lookup_valid),
    .vaddr_i        (lookup_use_ptw ? miss_vaddr : req_vaddr),
    .ptag_i         (lookup_use_ptw ? ptw_ptag : lookup_ptag),
    .fill_valid_i   (fill_data_valid),
    .fill_data_i    (rdata_i),
    .fill_last_i    (rlast_i),
    .invalidate_i   (icache_flush),
    .hit_o          (cache_hit),
    .rdata_o        (cache_rdata),
    .vaddr_o        (cache_vaddr_unused),
    .snpc_o         (cache_snpc_unused)
  );

  assign has_flush_sign = reset || excp_flush || mret_flush || branch_flush;
  assign issue_miss = valid && (state == READY) && !curr_fault &&
                      ((!vm_en && !cache_hit) || (vm_en && tlb_hit && !cache_hit));

  assign waittlb_resp_ok = i_ptw_resp_valid_i && !i_ptw_page_fault_i && !i_ptw_access_fault_i;
  assign waittlb_cache_miss = waittlb_resp_ok && !cache_hit;
  assign fill_data_valid = (state == WAITFILLRESP) && rvalid_i && !miss_uncache &&
                           !rresp_i[1] && !has_flush_sign;
  assign fill_done = (state == WAITFILLRESP) && rvalid_i && rlast_i;

  wire [1:0] ready_next_state_no_tlb;
  wire [1:0] waittlb_next_state_resp;
  assign ready_next_state_no_tlb = issue_miss ? SENDFILLREQ : READY;
  assign ready_next_state = tlb_miss ? WAITTLB :
                            ready_next_state_no_tlb;
  assign waittlb_next_state_resp = waittlb_cache_miss ? SENDFILLREQ : READY;
  assign waittlb_next_state = i_ptw_resp_valid_i ?
                              waittlb_next_state_resp :
                              WAITTLB;
  assign sendfillreq_next_state = arready_i ? WAITFILLRESP : SENDFILLREQ;
  assign waitfillresp_next_state = fill_done ? READY : WAITFILLRESP;
  assign state_next = ({2{state == READY}} & ready_next_state) |
                      ({2{state == WAITTLB}} & waittlb_next_state) |
                      ({2{state == SENDFILLREQ}} & sendfillreq_next_state) |
                      ({2{state == WAITFILLRESP}} & waitfillresp_next_state);

  assign lookup_hit_ready = valid && (state == READY) && !curr_fault &&
                            ((!vm_en && cache_hit) || (vm_en && tlb_hit && cache_hit));
  assign fetch_fault = fault_resp_valid || curr_fault || uncache_fault;
  assign resp_valid = lookup_hit_ready || uncache_resp_valid || fault_resp_valid || curr_fault;
  assign valid_o = resp_valid && valid && !has_flush_sign;
  assign ready_o = (!valid || (valid_o && deu_ready_i)) && (state == READY);
  assign consume_resp = valid_o && deu_ready_i;

  assign valid_next = ({1{!has_flush_sign && ifu_valid_i && ready_o}} & 1'b1) |
                      ({1{!has_flush_sign && !(ifu_valid_i && ready_o) && valid && !consume_resp}} & 1'b1);

  assign inst_data = ({32{uncache_resp_valid}} & uncache_rdata) |
                     ({32{!uncache_resp_valid}} & cache_rdata);
  assign icu_deu_bus_o = {req_vaddr, req_snpc, inst_data};
  assign icu_excp_bus_o = {fetch_fault, ifu_excp_bus};

  assign i_ptw_req_valid_o = (state == WAITTLB) && !i_ptw_resp_valid_i;
  assign i_ptw_req_vaddr_o = miss_vaddr;

  assign arvalid_o = (state == SENDFILLREQ);
  assign araddr_o = ({32{miss_uncache}} & miss_paddr[31:0]) |
                    ({32{!miss_uncache}} &
                     {miss_paddr[31:`CONFIG_ICACHE_BLOCKS_WIDTH+2],
                      {`CONFIG_ICACHE_BLOCKS_WIDTH+2{1'b0}}});
  assign arlen_o = ({8{miss_uncache}} & 8'b0) |
                   ({8{!miss_uncache}} & 8'(LINE_LAST));
  assign arsize_o = 3'b010;
  assign arburst_o = `INCR;
  assign rready_o = (state == WAITFILLRESP);

  assign _unused_ok = &{
    1'b0,
    satp_i[21:0],
    mstatus_i,
    rresp_i[0],
    miss_paddr[33:32],
    tlb_perm[6],
    tlb_perm[4],
    tlb_perm[1:0],
    i_ptw_req_ready_i,
    cache_vaddr_unused,
    cache_snpc_unused
  };

  always @(posedge clock) begin
    if (ifu_valid_i && ready_o) begin
      ifu_icu_bus <= ifu_icu_bus_i;
    end
  end

  always @(posedge clock) begin
    if (ifu_valid_i && ready_o) begin
      ifu_excp_bus <= ifu_excp_bus_i;
    end
  end

  always @(posedge clock) begin
    if (has_flush_sign) begin
      valid <= 1'b0;
    end else begin
      valid <= valid_next;
    end
  end

  always @(posedge clock) begin
    if (has_flush_sign) begin
      state <= READY;
    end else begin
      state <= state_next;
    end
  end

  always @(posedge clock) begin
    if (has_flush_sign) begin
      miss_vaddr <= 32'b0;
    end else if (issue_miss) begin
      miss_vaddr <= req_vaddr;
    end
  end

  always @(posedge clock) begin
    if (has_flush_sign) begin
      miss_paddr <= 34'b0;
    end else if (issue_miss) begin
      miss_paddr <= lookup_paddr;
    end else if (waittlb_resp_ok) begin
      miss_paddr <= ptw_paddr;
    end
  end

  always @(posedge clock) begin
    if (has_flush_sign) begin
      miss_uncache <= 1'b0;
    end else if (issue_miss) begin
      miss_uncache <= (lookup_paddr[31:16] == 16'h0f00);
    end else if (waittlb_resp_ok) begin
      miss_uncache <= (ptw_paddr[31:16] == 16'h0f00);
    end
  end

  always @(posedge clock) begin
    if (has_flush_sign) begin
      fill_ptr <= {BLOCKS_WIDTH{1'b0}};
    end else if (state == SENDFILLREQ && arready_i) begin
      fill_ptr <= {BLOCKS_WIDTH{1'b0}};
    end else if (fill_data_valid) begin
      fill_ptr <= fill_ptr + 1'b1;
    end
  end

  always @(posedge clock) begin
    if (has_flush_sign) begin
      uncache_resp_valid <= 1'b0;
    end else if (consume_resp) begin
      uncache_resp_valid <= 1'b0;
    end else if (fill_done && miss_uncache && !rresp_i[1]) begin
      uncache_resp_valid <= 1'b1;
    end
  end

  always @(posedge clock) begin
    if (fill_done && miss_uncache) begin
      uncache_rdata <= rdata_i;
    end
  end

  always @(posedge clock) begin
    if (has_flush_sign) begin
      uncache_fault <= 1'b0;
    end else if (consume_resp) begin
      uncache_fault <= 1'b0;
    end else if (fill_done && miss_uncache) begin
      uncache_fault <= rresp_i[1];
    end
  end

  always @(posedge clock) begin
    if (has_flush_sign) begin
      fault_resp_valid <= 1'b0;
    end else if (consume_resp) begin
      fault_resp_valid <= 1'b0;
    end else if ((state == WAITTLB) && i_ptw_resp_valid_i &&
                 (i_ptw_page_fault_i || i_ptw_access_fault_i)) begin
      fault_resp_valid <= 1'b1;
    end else if (fill_done && !miss_uncache && rresp_i[1]) begin
      fault_resp_valid <= 1'b1;
    end
  end

  assign wait_cache_flush = 1'b0;

endmodule
