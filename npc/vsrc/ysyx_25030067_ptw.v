`include "ysyx_25030067_riscv_param.vh"

module ysyx_25030067_ptw (
  input                   clock,
  input                   reset,

  input                   ptw_req_valid_i,
  output                  ptw_req_ready_o,
  input  [31:0]           ptw_req_vaddr_i,
  input  [1:0]            ptw_req_type_i,
  input                   ptw_req_source_i,

  output                  ptw_resp_valid_o,
  output [21:0]           ptw_resp_ppn_o,
  output [6:0]            ptw_resp_perm_o,
  output                  ptw_resp_level_o,
  output                  ptw_page_fault_o,
  output                  ptw_access_fault_o,

  input  [31:0]           satp_i,
  input  [31:0]           mstatus_i,
  input  [1:0]            priv_mode_i,

  output                  arvalid_o,
  input                   arready_i,
  output [31:0]           araddr_o,
  output [2:0]            arsize_o,
  output [7:0]            arlen_o,
  output [1:0]            arburst_o,

  input                   rvalid_i,
  input  [31:0]           rdata_i,
  input  [1:0]            rresp_i,
  input                   rlast_i,
  output                  rready_o
);

  localparam ACCESS_FETCH = 2'b00;
  localparam ACCESS_LOAD  = 2'b01;
  localparam ACCESS_STORE = 2'b10;

  localparam PRIV_U       = 2'b00;
  localparam PRIV_S       = 2'b01;
  localparam PRIV_M       = 2'b11;

  localparam IDLE         = 3'd0;
  localparam L1_REQ       = 3'd1;
  localparam L1_WAIT      = 3'd2;
  localparam L2_REQ       = 3'd3;
  localparam L2_WAIT      = 3'd4;
  localparam DONE         = 3'd5;
  localparam FAULT        = 3'd6;

  wire [21:0] satp_ppn;
  wire        mstatus_mxr;
  wire        mstatus_sum;
  wire        mstatus_mprv;
  wire [1:0]  mstatus_mpp;
  wire [1:0]  eff_priv;
  wire        start_walk;
  wire        mem_resp_fire;
  wire [33:0] l1_addr;
  wire [33:0] l2_addr;
  wire        pte_v;
  wire        pte_r;
  wire        pte_w;
  wire        pte_x;
  wire        pte_u;
  wire        pte_g;
  wire        pte_a;
  wire        pte_d;
  wire        pte_leaf;
  wire        pte_invalid;
  wire        resp_access_fault;
  wire        req_fetch;
  wire        req_load;
  wire        req_store;
  wire        pte_read_ok;
  wire        pte_priv_ok;
  wire        pte_ad_ok;
  wire        pte_superpage_ok;
  wire        pte_perm_ok;
  wire [21:0] resp_ppn;
  wire [2:0]  idle_next_state;
  wire [2:0]  l1_req_next_state;
  wire [2:0]  l1_wait_next_state;
  wire [2:0]  l2_req_next_state;
  wire [2:0]  l2_wait_next_state;
  wire [2:0]  state_next;
  wire [31:0] araddr_l1;
  wire [31:0] araddr_l2;
  wire        l1_walk_fault;
  wire        l1_walk_done;
  wire        l2_walk_fault;
  reg  [2:0]  state;
  reg  [31:0] req_vaddr;
  reg  [1:0]  req_type;
  reg         req_source;
  reg  [1:0]  req_priv;
  reg  [31:0] walk_pte;
  reg         walk_superpage;
  reg         walk_access_fault;
  wire        _unused_ok;

  assign satp_ppn = satp_i[21:0];
  assign mstatus_mxr = mstatus_i[19];
  assign mstatus_sum = mstatus_i[18];
  assign mstatus_mprv = mstatus_i[17];
  assign mstatus_mpp = mstatus_i[12:11];

  assign eff_priv = (priv_mode_i == PRIV_M) &&
                    mstatus_mprv &&
                    (ptw_req_type_i != ACCESS_FETCH) ?
                    mstatus_mpp : priv_mode_i;

  assign start_walk = ptw_req_valid_i && ptw_req_ready_o;
  assign mem_resp_fire = rvalid_i && rready_o && rlast_i;

  assign l1_addr = {satp_ppn, 12'b0} + {22'b0, req_vaddr[31:22], 2'b0};
  assign l2_addr = {walk_pte[31:10], 12'b0} + {22'b0, req_vaddr[21:12], 2'b0};

  assign pte_v = rdata_i[0];
  assign pte_r = rdata_i[1];
  assign pte_w = rdata_i[2];
  assign pte_x = rdata_i[3];
  assign pte_u = walk_pte[4];
  assign pte_g = walk_pte[5];
  assign pte_a = walk_pte[6];
  assign pte_d = walk_pte[7];
  assign pte_leaf = pte_r || pte_x;
  assign pte_invalid = !pte_v || (!pte_r && pte_w);
  assign resp_access_fault = rresp_i[1];

  assign req_fetch = (req_type == ACCESS_FETCH);
  assign req_load = (req_type == ACCESS_LOAD);
  assign req_store = (req_type == ACCESS_STORE);

  assign pte_read_ok = ({1{req_fetch}} & walk_pte[3]) |
                       ({1{req_load}} & (walk_pte[1] || (mstatus_mxr && walk_pte[3]))) |
                       ({1{req_store}} & walk_pte[2]);
  assign pte_priv_ok = ({1{req_priv == PRIV_U}} & pte_u) |
                       ({1{req_priv == PRIV_S}} & (!pte_u || mstatus_sum)) |
                       ({1{req_priv == PRIV_M}} & 1'b1);
  assign pte_ad_ok = pte_a && (!req_store || pte_d);
  assign pte_superpage_ok = !walk_superpage || (walk_pte[19:10] == 10'b0);
  assign pte_perm_ok = pte_read_ok && pte_priv_ok && pte_ad_ok && pte_superpage_ok;
  assign resp_ppn = walk_superpage ? {walk_pte[31:20], req_vaddr[21:12]} :
                                     walk_pte[31:10];
  assign araddr_l1 = l1_addr[31:0];
  assign araddr_l2 = l2_addr[31:0];
  assign l1_walk_fault = resp_access_fault || pte_invalid;
  assign l1_walk_done = pte_leaf;
  assign l2_walk_fault = resp_access_fault || pte_invalid || !pte_leaf;
  assign _unused_ok = &{
    1'b0,
    satp_i[31:22],
    mstatus_i[31:20],
    mstatus_i[16:13],
    mstatus_i[10:0],
    rresp_i[0],
    l1_addr[33:32],
    l2_addr[33:32],
    req_vaddr[11:0],
    req_source,
    walk_pte[9:8],
    walk_pte[0]
  };

  assign idle_next_state = start_walk ? L1_REQ : IDLE;
  assign l1_req_next_state = arready_i ? L1_WAIT : L1_REQ;
  wire [2:0] l1_wait_next_fault_state;
  wire [2:0] l1_wait_next_done_state;
  wire [2:0] l2_wait_next_state_resp;
  assign l1_wait_next_done_state = l1_walk_done ? DONE : L2_REQ;
  assign l1_wait_next_fault_state = l1_walk_fault ? FAULT :
                                    l1_wait_next_done_state;
  assign l1_wait_next_state = !mem_resp_fire ? L1_WAIT :
                              l1_wait_next_fault_state;
  assign l2_req_next_state = arready_i ? L2_WAIT : L2_REQ;
  assign l2_wait_next_state_resp = l2_walk_fault ? FAULT : DONE;
  assign l2_wait_next_state = !mem_resp_fire ? L2_WAIT :
                              l2_wait_next_state_resp;

  assign state_next = ({3{state == IDLE}} & idle_next_state) |
                      ({3{state == L1_REQ}} & l1_req_next_state) |
                      ({3{state == L1_WAIT}} & l1_wait_next_state) |
                      ({3{state == L2_REQ}} & l2_req_next_state) |
                      ({3{state == L2_WAIT}} & l2_wait_next_state) |
                      ({3{state == DONE}} & IDLE) |
                      ({3{state == FAULT}} & IDLE);

  always @(posedge clock) begin
    if (reset) begin
      state <= IDLE;
    end else begin
      state <= state_next;
    end
  end

  always @(posedge clock) begin
    if (start_walk) begin
      req_vaddr <= ptw_req_vaddr_i;
    end
  end

  always @(posedge clock) begin
    if (start_walk) begin
      req_type <= ptw_req_type_i;
    end
  end

  always @(posedge clock) begin
    if (start_walk) begin
      req_source <= ptw_req_source_i;
    end
  end

  always @(posedge clock) begin
    if (start_walk) begin
      req_priv <= eff_priv;
    end
  end

  always @(posedge clock) begin
    if ((state == L1_WAIT || state == L2_WAIT) && mem_resp_fire) begin
      walk_pte <= rdata_i;
    end
  end

  always @(posedge clock) begin
    if (reset) begin
      walk_superpage <= 1'b0;
    end else if (start_walk) begin
      walk_superpage <= 1'b0;
    end else if (state == L1_WAIT && mem_resp_fire && !resp_access_fault && !pte_invalid) begin
      walk_superpage <= pte_leaf;
    end else if (state == L2_WAIT && mem_resp_fire) begin
      walk_superpage <= 1'b0;
    end
  end

  always @(posedge clock) begin
    if (reset) begin
      walk_access_fault <= 1'b0;
    end else if (start_walk) begin
      walk_access_fault <= 1'b0;
    end else if ((state == L1_WAIT || state == L2_WAIT) && mem_resp_fire && resp_access_fault) begin
      walk_access_fault <= 1'b1;
    end
  end

  assign ptw_req_ready_o = (state == IDLE);
  assign ptw_resp_valid_o = (state == DONE) || (state == FAULT);
  assign ptw_resp_ppn_o = resp_ppn;
  assign ptw_resp_perm_o = {walk_pte[7], pte_a, pte_g, pte_u, walk_pte[3], walk_pte[2], walk_pte[1]};
  assign ptw_resp_level_o = walk_superpage;
  assign ptw_page_fault_o = (state == DONE && !pte_perm_ok) ||
                            (state == FAULT && !walk_access_fault);
  assign ptw_access_fault_o = (state == FAULT && walk_access_fault);

  assign arvalid_o = (state == L1_REQ) || (state == L2_REQ);
  assign araddr_o = ({32{state == L1_REQ}} & araddr_l1) |
                    ({32{state == L2_REQ}} & araddr_l2);
  assign arsize_o = 3'b010;
  assign arlen_o = 8'b0;
  assign arburst_o = `FIXED;
  assign rready_o = (state == L1_WAIT) || (state == L2_WAIT);

endmodule
