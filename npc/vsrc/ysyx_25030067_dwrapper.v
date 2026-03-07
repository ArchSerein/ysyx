`include "autoconf.vh"
`include "ysyx_25030067_riscv_param.vh"

module ysyx_25030067_dwrapper (
  input                   clock,
  input                   reset,

  input                   exu_arvalid_i,
  output                  dcache_arready_o,
  input  [2:0]            exu_arsize_i,
  input  [31:0]           exu_araddr_i,
  output [31:0]           dcache_rdata_o,
  output                  dcache_rvalid_o,
  output [1:0]            dcache_rresp_o,
  input                   lsu_rready_i,

  input                   exu_awvalid_i,
  output                  dcache_awready_o,
  input  [31:0]           exu_awaddr_i,
  input  [2:0]            exu_awsize_i,
  input                   exu_wvalid_i,
  output                  dcache_wready_o,
  input  [31:0]           exu_wdata_i,
  input  [3:0]            exu_wstrb_i,
  output [1:0]            dcache_bresp_o,
  output                  dcache_bvalid_o,
  input                   lsu_bready_i,

  input                   dcache_flush,
  output                  wait_cache_flush,

  output                  d_ptw_req_valid_o,
  input                   d_ptw_req_ready_i,
  output [31:0]           d_ptw_req_vaddr_o,
  output [1:0]            d_ptw_req_type_o,
  input                   d_ptw_resp_valid_i,
  input  [21:0]           d_ptw_resp_ppn_i,
  input  [6:0]            d_ptw_resp_perm_i,
  input                   d_ptw_resp_level_i,
  input                   d_ptw_page_fault_i,
  input                   d_ptw_access_fault_i,

  input  [31:0]           satp_i,
  input  [31:0]           mstatus_i,
  input  [1:0]            priv_mode_i,
  input                   sfence_vma_i,

  output                  arvalid_o,
  input                   arready_i,
  output [31:0]           araddr_o,
  output [7:0]            arlen_o,
  output [2:0]            arsize_o,
  output [1:0]            arburst_o,

  input                   rvalid_i,
  input  [31:0]           rdata_i,
  input  [1:0]            rresp_i,
  input                   rlast_i,
  output                  rready_o,

  output                  awvalid_o,
  input                   awready_i,
  output [31:0]           awaddr_o,
  output [7:0]            awlen_o,
  output [2:0]            awsize_o,
  output [1:0]            awburst_o,

  output                  wvalid_o,
  input                   wready_i,
  output [31:0]           wdata_o,
  output [3:0]            wstrb_o,
  output                  wlast_o,

  input                   bvalid_i,
  output                  bready_o,
  input  [1:0]            bresp_i
);

  localparam READY             = 3'b000;
  localparam WAITTLB           = 3'b001;
  localparam WRITEBACK         = 3'b010;
  localparam WAITWREQCOMPLETE  = 3'b011;
  localparam WAITWRITERESP     = 3'b100;
  localparam SENDFILLREQ       = 3'b101;
  localparam WAITFILLRESP      = 3'b110;
  localparam WAITFLUSH         = 3'b111;

  localparam F_IDLE            = 3'b000;
  localparam F_NEXT            = 3'b001;
  localparam F_SENDREQ         = 3'b010;
  localparam F_WAITREQCOMPLETE = 3'b011;
  localparam F_WAITRESP        = 3'b100;
  localparam F_FINISH          = 3'b101;

  localparam ACCESS_LOAD       = 2'b01;
  localparam ACCESS_STORE      = 2'b10;
  localparam DATA_OK           = 2'b00;
  localparam DATA_SLVERR       = 2'b10;
  localparam PRIV_U            = 2'b00;
  localparam PRIV_S            = 2'b01;
  localparam PRIV_M            = 2'b11;
  localparam TAG_WIDTH         = `DATA_WIDTH - `CONFIG_DCACHE_BLOCKS_WIDTH -
                                 `CONFIG_DCACHE_SETS_WIDTH - 2;
  localparam LINE_WIDTH        = `DATA_WIDTH * `CONFIG_DCACHE_BLOCKS;
  localparam WAY_WIDTH         = `CONFIG_DCACHE_ASSOCIATIVITYS_WIDTH;
  localparam SETS_WIDTH        = `CONFIG_DCACHE_SETS_WIDTH;
  localparam BLOCKS_WIDTH      = `CONFIG_DCACHE_BLOCKS_WIDTH;
  localparam LINE_LAST         = `CONFIG_DCACHE_BLOCKS - 1;

  reg                          valid;
  reg  [2:0]                   state;
  reg  [2:0]                   flush_state;
  reg  [31:0]                  req_vaddr;
  reg  [2:0]                   req_size;
  reg                          req_is_write;
  reg  [31:0]                  req_wdata;
  reg  [3:0]                   req_wstrb;
  reg  [33:0]                  miss_paddr;
  reg                          miss_uncache;
  reg  [31:0]                  miss_vaddr;
  reg  [TAG_WIDTH-1:0]         wb_tag_reg;
  reg  [LINE_WIDTH-1:0]        wb_line_reg;
  reg  [SETS_WIDTH-1:0]        wb_index_reg;
  reg  [TAG_WIDTH-1:0]         flush_wb_tag_reg;
  reg  [LINE_WIDTH-1:0]        flush_wb_line_reg;
  reg                          awaddr_handshake_done;
  reg                          wdata_handshake_done;
  reg  [BLOCKS_WIDTH-1:0]      wb_ptr;
  reg  [SETS_WIDTH-1:0]        flush_index;
  reg  [WAY_WIDTH-1:0]         flush_way;
  reg                          uncache_rvalid;
  reg                          uncache_bvalid;
  reg  [31:0]                  uncache_rdata;
  reg  [1:0]                   uncache_rresp;
  reg  [1:0]                   uncache_bresp;
  reg                          fault_resp_valid;
  reg                          fault_is_write;
  reg  [1:0]                   fault_resp_code;
  reg                          dcache_flush_pending;

  wire                         request_read_fire;
  wire                         request_write_fire;
  wire                         consume_resp;
  wire                         hold_valid;
  wire                         valid_next;
  wire                         has_flush_sign;
  wire [8:0]                   satp_asid;
  wire                         mstatus_mxr;
  wire                         mstatus_sum;
  wire                         mstatus_mprv;
  wire [1:0]                   mstatus_mpp;
  wire [1:0]                   eff_priv;
  wire                         vm_en;
  wire                         tlb_lookup_valid;
  wire                         tlb_hit;
  wire [21:0]                  tlb_ppn;
  wire [6:0]                   tlb_perm;
  wire                         tlb_write_valid;
  wire [33:0]                  direct_paddr;
  wire [33:0]                  tlb_paddr;
  wire [33:0]                  lookup_paddr;
  wire [33:0]                  ptw_paddr;
  wire [TAG_WIDTH-1:0]         lookup_ptag;
  wire [TAG_WIDTH-1:0]         ptw_ptag;
  wire                         lookup_use_ptw;
  wire                         lookup_uncache;
  wire                         curr_uncache;
  wire                         curr_fault;
  wire                         tlb_miss;
  wire                         tlb_r;
  wire                         tlb_w;
  wire                         tlb_u;
  wire                         tlb_a;
  wire                         tlb_d;
  wire                         tlb_type_ok;
  wire                         tlb_priv_ok;
  wire                         tlb_perm_ok;
  wire                         cache_lookup_valid;
  wire                         cache_hit;
  wire [31:0]                  cache_rdata;
  wire                         cache_line_dirty;
  wire [WAY_WIDTH-1:0]         cache_miss_way;
  wire [TAG_WIDTH-1:0]         cache_wb_tag;
  wire [LINE_WIDTH-1:0]        cache_wb_data;
  wire                         probe_valid;
  wire                         probe_invalidate;
  wire [31:0]                  wb_word_data;
  wire [31:0]                  fill_wb_word_data;
  wire                         active_flush_writeback;
  wire                         active_main_writeback;
  wire                         active_writeback;
  wire                         active_uncache_write;
  wire                         aw_handshake;
  wire                         w_handshake;
  wire                         write_req_complete;
  wire                         fill_data_valid;
  wire                         fill_done;
  wire                         waittlb_resp_ok;
  wire                         waittlb_cache_miss;
  wire [2:0]                   ready_next_state;
  wire [2:0]                   waittlb_next_state;
  wire [2:0]                   writeback_next_state;
  wire [2:0]                   waitwreq_next_state;
  wire [2:0]                   waitwriteresp_next_state;
  wire [2:0]                   sendfillreq_next_state;
  wire [2:0]                   waitfillresp_next_state;
  wire [2:0]                   waitflush_next_state;
  wire [2:0]                   state_next;
  wire                         start_main_writeback;
  wire                         start_flush_writeback;
  wire                         flush_line_dirty;
  wire                         flush_line_last_way;
  wire                         flush_line_last_set;
  wire                         flush_way_advance;
  wire                         flush_set_advance;
  wire [WAY_WIDTH-1:0]         next_flush_way;
  wire [SETS_WIDTH-1:0]        next_flush_index;
  wire [2:0]                   f_idle_next_state;
  wire [2:0]                   f_next_next_state;
  wire [2:0]                   f_sendreq_next_state;
  wire [2:0]                   f_waitreq_next_state;
  wire [2:0]                   f_waitresp_next_state;
  wire [2:0]                   f_finish_next_state;
  wire [2:0]                   flush_state_next;
  wire                         hit_read_resp;
  wire                         hit_write_resp;
  wire                         dcache_flush_req;
  wire                         dcache_flush_start;

  assign request_read_fire = exu_arvalid_i && dcache_arready_o;
  assign request_write_fire = exu_awvalid_i && dcache_awready_o &&
                              exu_wvalid_i && dcache_wready_o;
  assign consume_resp = (dcache_rvalid_o && lsu_rready_i) ||
                        (dcache_bvalid_o && lsu_bready_i);
  assign hold_valid = valid && !consume_resp;
  assign valid_next = (request_read_fire | request_write_fire) |
                      (~(request_read_fire | request_write_fire) & hold_valid);
  assign has_flush_sign = reset;
  assign dcache_flush_req = dcache_flush || dcache_flush_pending;
  assign dcache_flush_start = (state == READY) && !valid && dcache_flush_req;

  assign satp_asid = satp_i[30:22];
  assign mstatus_mxr = mstatus_i[19];
  assign mstatus_sum = mstatus_i[18];
  assign mstatus_mprv = mstatus_i[17];
  assign mstatus_mpp = mstatus_i[12:11];
  assign eff_priv = ({2{priv_mode_i == PRIV_M && mstatus_mprv}} & mstatus_mpp) |
                    ({2{!(priv_mode_i == PRIV_M && mstatus_mprv)}} & priv_mode_i);
  assign vm_en = satp_i[31] && (eff_priv != PRIV_M);

  assign direct_paddr = {2'b00, req_vaddr};
  assign tlb_paddr = {tlb_ppn, req_vaddr[11:0]};
  assign ptw_paddr = {d_ptw_resp_ppn_i, miss_vaddr[11:0]};
  assign lookup_use_ptw = (state == WAITTLB) && waittlb_resp_ok;
  assign lookup_paddr = ({34{lookup_use_ptw}} & ptw_paddr) |
                        ({34{!lookup_use_ptw && vm_en}} & tlb_paddr) |
                        ({34{!lookup_use_ptw && !vm_en}} & direct_paddr);
  assign lookup_ptag = lookup_paddr[`DATA_WIDTH-1:`CONFIG_DCACHE_BLOCKS_WIDTH+`CONFIG_DCACHE_SETS_WIDTH+2];
  assign ptw_ptag = ptw_paddr[`DATA_WIDTH-1:`CONFIG_DCACHE_BLOCKS_WIDTH+`CONFIG_DCACHE_SETS_WIDTH+2];
  assign curr_uncache = !((lookup_paddr[31:28] == 4'h3) ||
                          (lookup_paddr[31:28] == 4'h8) ||
                          (lookup_paddr[31:28] == 4'ha));
  assign lookup_uncache = curr_uncache;

  assign tlb_lookup_valid = valid && (state == READY) && vm_en;
  assign tlb_write_valid = d_ptw_resp_valid_i && !d_ptw_page_fault_i && !d_ptw_access_fault_i;

  ysyx_25030067_tlb u_dtlb (
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
    .write_ppn_i        (d_ptw_resp_ppn_i),
    .write_perm_i       (d_ptw_resp_perm_i),
    .write_page_level_i (d_ptw_resp_level_i),
    .flush_all_i        (sfence_vma_i),
    .flush_vma_i        (1'b0),
    .flush_asid_valid_i (1'b0),
    .flush_asid_i       (9'b0),
    .flush_vpn_valid_i  (1'b0),
    .flush_vpn_i        (20'b0)
  );

  assign tlb_r = tlb_perm[0];
  assign tlb_w = tlb_perm[1];
  assign tlb_u = tlb_perm[3];
  assign tlb_a = tlb_perm[5];
  assign tlb_d = tlb_perm[6];
  assign tlb_type_ok = ({1{!req_is_write}} & (tlb_r || (mstatus_mxr && tlb_perm[2]))) |
                       ({1{req_is_write}} & tlb_w);
  assign tlb_priv_ok = ({1{eff_priv == PRIV_U}} & tlb_u) |
                       ({1{eff_priv == PRIV_S}} & (!tlb_u || mstatus_sum)) |
                       ({1{eff_priv == PRIV_M}} & 1'b1);
  assign tlb_perm_ok = tlb_type_ok && tlb_priv_ok && tlb_a &&
                       (!req_is_write || tlb_d);

  assign tlb_miss = vm_en && !tlb_hit;
  assign curr_fault = vm_en && tlb_hit && !tlb_perm_ok;

  assign waittlb_resp_ok = d_ptw_resp_valid_i &&
                           !d_ptw_page_fault_i &&
                           !d_ptw_access_fault_i;

  assign cache_lookup_valid = valid && !lookup_uncache &&
                              ((state == READY && (!vm_en || tlb_hit)) ||
                               (state == WAITTLB && waittlb_resp_ok));
  assign probe_valid = (state == WAITFLUSH);

  ysyx_25030067_dcache u_dcache (
    .clock            (clock),
    .reset            (reset),
    .lookup_valid_i   (cache_lookup_valid),
    .vaddr_i          (lookup_use_ptw ? miss_vaddr : req_vaddr),
    .ptag_i           (lookup_use_ptw ? ptw_ptag : lookup_ptag),
    .is_write_i       ((state == READY) && req_is_write),
    .wdata_i          (req_wdata),
    .wstrb_i          (req_wstrb),
    .fill_valid_i     (fill_data_valid),
    .fill_data_i      (rdata_i),
    .fill_last_i      (rlast_i),
    .wb_tag_o         (cache_wb_tag),
    .wb_data_o        (cache_wb_data),
    .invalidate_i     (1'b0),
    .probe_valid_i    (probe_valid),
    .probe_index_i    (flush_index),
    .probe_way_i      (flush_way),
    .probe_invalidate_i(probe_invalidate),
    .hit_o            (cache_hit),
    .rdata_o          (cache_rdata),
    .line_dirty_o     (cache_line_dirty),
    .miss_way_o       (cache_miss_way)
  );

  assign waittlb_cache_miss = waittlb_resp_ok && (lookup_uncache || !cache_hit);

  wire [2:0] ready_next_state_no_flush;
  wire [2:0] ready_next_state_no_tlb;
  wire [2:0] ready_next_state_uncache;
  wire [2:0] ready_next_state_cache_miss;
  wire [2:0] ready_next_state_cache;
  wire [2:0] waittlb_next_state_resp;
  wire [2:0] waittlb_next_state_no_fault;
  wire [2:0] waittlb_next_state_cache_miss;
  wire [2:0] waittlb_next_state_cache;
  wire [2:0] writeback_next_state_partial;
  wire [2:0] waitwriteresp_next_state_resp;
  wire [2:0] f_next_next_state_no_finish;
  wire [2:0] f_sendreq_next_state_partial;
  assign ready_next_state_cache_miss = cache_line_dirty ? WRITEBACK : SENDFILLREQ;
  assign ready_next_state_uncache = req_is_write ? WRITEBACK : SENDFILLREQ;
  assign ready_next_state_cache = (valid && !consume_resp && !curr_fault && !tlb_miss && !lookup_uncache && !cache_hit) ? ready_next_state_cache_miss :
                                  READY;
  assign ready_next_state_no_tlb = (valid && !consume_resp && !curr_fault && !tlb_miss && lookup_uncache) ? ready_next_state_uncache :
                                   ready_next_state_cache;
  assign ready_next_state_no_flush = (valid && !consume_resp && tlb_miss) ? WAITTLB : ready_next_state_no_tlb;
  assign ready_next_state = dcache_flush_start ? WAITFLUSH :
                            ready_next_state_no_flush;
  assign waittlb_next_state_cache_miss = cache_line_dirty ? WRITEBACK : SENDFILLREQ;
  assign waittlb_next_state_cache = waittlb_cache_miss ? waittlb_next_state_cache_miss : READY;
  assign waittlb_next_state_no_fault = (lookup_uncache && req_is_write) ? WRITEBACK :
                                       waittlb_next_state_cache;
  assign waittlb_next_state_resp = (d_ptw_page_fault_i || d_ptw_access_fault_i) ? READY :
                                   waittlb_next_state_no_fault;
  assign waittlb_next_state = d_ptw_resp_valid_i ?
                              waittlb_next_state_resp :
                              WAITTLB;
  assign writeback_next_state_partial = (aw_handshake || (w_handshake && wlast_o)) ? WAITWREQCOMPLETE :
                                        WRITEBACK;
  assign writeback_next_state = (aw_handshake && w_handshake && wlast_o) ? WAITWRITERESP :
                                writeback_next_state_partial;
  assign waitwreq_next_state = write_req_complete ? WAITWRITERESP : WAITWREQCOMPLETE;
  assign waitwriteresp_next_state_resp = miss_uncache ? READY : SENDFILLREQ;
  assign waitwriteresp_next_state = bvalid_i ?
                                    waitwriteresp_next_state_resp :
                                    WAITWRITERESP;
  assign sendfillreq_next_state = arready_i ? WAITFILLRESP : SENDFILLREQ;
  assign waitfillresp_next_state = fill_done ? READY : WAITFILLRESP;
  assign waitflush_next_state = (flush_state == F_FINISH) ? READY : WAITFLUSH;
  assign state_next = ({3{state == READY}} & ready_next_state) |
                      ({3{state == WAITTLB}} & waittlb_next_state) |
                      ({3{state == WRITEBACK}} & writeback_next_state) |
                      ({3{state == WAITWREQCOMPLETE}} & waitwreq_next_state) |
                      ({3{state == WAITWRITERESP}} & waitwriteresp_next_state) |
                      ({3{state == SENDFILLREQ}} & sendfillreq_next_state) |
                      ({3{state == WAITFILLRESP}} & waitfillresp_next_state) |
                      ({3{state == WAITFLUSH}} & waitflush_next_state);

  assign flush_line_dirty = cache_line_dirty;
  assign flush_line_last_way = (flush_way == WAY_WIDTH'(`CONFIG_DCACHE_ASSOCIATIVITYS - 1));
  assign flush_line_last_set = (flush_index == SETS_WIDTH'(`CONFIG_DCACHE_SETS - 1));
  assign next_flush_way = flush_line_last_way ? {WAY_WIDTH{1'b0}} :
                          (flush_way + 1'b1);
  assign next_flush_index = flush_line_last_set ? flush_index :
                            (flush_index + 1'b1);
  assign f_idle_next_state = (state == WAITFLUSH) ? F_NEXT : F_IDLE;
  assign f_next_next_state_no_finish = (flush_line_last_way && flush_line_last_set) ? F_FINISH :
                                       F_NEXT;
  assign f_next_next_state = flush_line_dirty ? F_SENDREQ :
                             f_next_next_state_no_finish;
  assign f_sendreq_next_state_partial = (aw_handshake || (w_handshake && wlast_o)) ? F_WAITREQCOMPLETE :
                                        F_SENDREQ;
  assign f_sendreq_next_state = (aw_handshake && w_handshake && wlast_o) ? F_WAITRESP :
                                f_sendreq_next_state_partial;
  assign f_waitreq_next_state = write_req_complete ? F_WAITRESP : F_WAITREQCOMPLETE;
  assign f_waitresp_next_state = bvalid_i ? F_NEXT : F_WAITRESP;
  assign f_finish_next_state = F_IDLE;
  assign flush_state_next = ({3{flush_state == F_IDLE}} & f_idle_next_state) |
                            ({3{flush_state == F_NEXT}} & f_next_next_state) |
                            ({3{flush_state == F_SENDREQ}} & f_sendreq_next_state) |
                            ({3{flush_state == F_WAITREQCOMPLETE}} & f_waitreq_next_state) |
                            ({3{flush_state == F_WAITRESP}} & f_waitresp_next_state) |
                            ({3{flush_state == F_FINISH}} & f_finish_next_state);

  assign start_main_writeback = ((state == READY) && (ready_next_state == WRITEBACK)) ||
                                ((state == WAITTLB) && (waittlb_next_state == WRITEBACK));
  assign start_flush_writeback = (state == WAITFLUSH) &&
                                 (flush_state == F_NEXT) &&
                                 flush_line_dirty;
  assign active_main_writeback = (state == WRITEBACK) || (state == WAITWREQCOMPLETE);
  assign active_flush_writeback = (state == WAITFLUSH) &&
                                  ((flush_state == F_SENDREQ) ||
                                   (flush_state == F_WAITREQCOMPLETE));
  assign active_writeback = active_main_writeback || active_flush_writeback;
  assign active_uncache_write = active_main_writeback && miss_uncache;

  assign wb_word_data = wb_line_reg[`DATA_WIDTH * wb_ptr +: `DATA_WIDTH];
  assign fill_wb_word_data = flush_wb_line_reg[`DATA_WIDTH * wb_ptr +: `DATA_WIDTH];

  assign aw_handshake = awvalid_o && awready_i;
  assign w_handshake = wvalid_o && wready_i;
  assign write_req_complete = awaddr_handshake_done && wdata_handshake_done;
  assign fill_data_valid = (state == WAITFILLRESP) && rvalid_i && !miss_uncache &&
                           !rresp_i[1];
  assign fill_done = (state == WAITFILLRESP) && rvalid_i && rlast_i;

  assign hit_read_resp = valid && (state == READY) && !req_is_write &&
                         !curr_fault && !lookup_uncache && cache_hit;
  assign hit_write_resp = valid && (state == READY) && req_is_write &&
                          !curr_fault && !lookup_uncache && cache_hit;

  assign dcache_arready_o = (state == READY) && !valid;
  assign dcache_awready_o = (state == READY) && !valid;
  assign dcache_wready_o = (state == READY) && !valid;

  assign dcache_rvalid_o = hit_read_resp || uncache_rvalid ||
                           (fault_resp_valid && !fault_is_write);
  assign dcache_rdata_o = uncache_rvalid ? uncache_rdata : cache_rdata;
  assign dcache_rresp_o = ({2{uncache_rvalid}} & uncache_rresp) |
                          ({2{!uncache_rvalid && fault_resp_valid && !fault_is_write}} & fault_resp_code) |
                          ({2{!uncache_rvalid && !(fault_resp_valid && !fault_is_write)}} & DATA_OK);

  assign dcache_bvalid_o = hit_write_resp || uncache_bvalid ||
                           (fault_resp_valid && fault_is_write);
  assign dcache_bresp_o = ({2{uncache_bvalid}} & uncache_bresp) |
                          ({2{!uncache_bvalid && fault_resp_valid && fault_is_write}} & fault_resp_code) |
                          ({2{!uncache_bvalid && !(fault_resp_valid && fault_is_write)}} & DATA_OK);

  assign d_ptw_req_valid_o = (state == WAITTLB) && !d_ptw_resp_valid_i;
  assign d_ptw_req_vaddr_o = miss_vaddr;
  assign d_ptw_req_type_o = {req_is_write, ~req_is_write};

  assign arvalid_o = (state == SENDFILLREQ);
  assign araddr_o = miss_uncache ? miss_paddr[31:0] :
                     {miss_paddr[31:`CONFIG_DCACHE_BLOCKS_WIDTH+2],
                      {`CONFIG_DCACHE_BLOCKS_WIDTH+2{1'b0}}};
  assign arlen_o = miss_uncache ? 8'b0  : 8'(LINE_LAST);
  assign arsize_o = miss_uncache ? req_size : 3'b010;
  assign arburst_o = `INCR;
  assign rready_o = (state == WAITFILLRESP);

  assign awvalid_o = (state == WRITEBACK) ||
                     (state == WAITWREQCOMPLETE && !awaddr_handshake_done) ||
                     ((state == WAITFLUSH) &&
                      ((flush_state == F_SENDREQ) ||
                       (flush_state == F_WAITREQCOMPLETE && !awaddr_handshake_done)));
  assign awaddr_o = ({32{active_flush_writeback}} &
                     {flush_wb_tag_reg, flush_index, {`CONFIG_DCACHE_BLOCKS_WIDTH+2{1'b0}}}) |
                    ({32{active_main_writeback && miss_uncache}} & miss_paddr[31:0]) |
                    ({32{active_main_writeback && !miss_uncache}} &
                     {wb_tag_reg, wb_index_reg, {`CONFIG_DCACHE_BLOCKS_WIDTH+2{1'b0}}});
  assign awlen_o = active_uncache_write ? 8'b0 : 8'(LINE_LAST);
  assign awsize_o = active_uncache_write ? req_size : 3'b010;
  assign awburst_o = `INCR;

  assign wvalid_o = (state == WRITEBACK) ||
                    (state == WAITWREQCOMPLETE && !wdata_handshake_done) ||
                    ((state == WAITFLUSH) &&
                     ((flush_state == F_SENDREQ) ||
                      (flush_state == F_WAITREQCOMPLETE && !wdata_handshake_done)));
  assign wdata_o = ({32{active_flush_writeback}} & fill_wb_word_data) |
                   ({32{active_main_writeback && miss_uncache}} & req_wdata) |
                   ({32{active_main_writeback && !miss_uncache}} & wb_word_data);
  assign wstrb_o = ({4{active_flush_writeback}} & 4'b1111) |
                   ({4{active_main_writeback && miss_uncache}} & req_wstrb) |
                   ({4{active_main_writeback && !miss_uncache}} & 4'b1111);
  assign wlast_o = active_uncache_write ? 1'b1 :
                   (wb_ptr == BLOCKS_WIDTH'(LINE_LAST));
  assign bready_o = (state == WAITWRITERESP) ||
                    ((state == WAITFLUSH) && (flush_state == F_WAITRESP));

  assign probe_invalidate = ((state == WAITFLUSH) && (flush_state == F_NEXT) && !flush_line_dirty) ||
                            ((state == WAITFLUSH) && (flush_state == F_WAITRESP) && bvalid_i);
  assign wait_cache_flush = dcache_flush_req || (state == WAITFLUSH);

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
    if (reset) begin
      flush_state <= F_IDLE;
    end else begin
      flush_state <= flush_state_next;
    end
  end

  always @(posedge clock) begin
    if (reset) begin
      dcache_flush_pending <= 1'b0;
    end else if (dcache_flush_start) begin
      dcache_flush_pending <= 1'b0;
    end else if (dcache_flush && !dcache_flush_start) begin
      dcache_flush_pending <= 1'b1;
    end
  end

  always @(posedge clock) begin
    if (request_read_fire) begin
      req_vaddr <= exu_araddr_i;
    end else if (request_write_fire) begin
      req_vaddr <= exu_awaddr_i;
    end
  end

  always @(posedge clock) begin
    if (request_read_fire) begin
      req_size <= exu_arsize_i;
    end else if (request_write_fire) begin
      req_size <= exu_awsize_i;
    end
  end

  always @(posedge clock) begin
    if (request_read_fire) begin
      req_is_write <= 1'b0;
    end else if (request_write_fire) begin
      req_is_write <= 1'b1;
    end
  end

  always @(posedge clock) begin
    if (request_write_fire) begin
      req_wdata <= exu_wdata_i;
    end
  end

  always @(posedge clock) begin
    if (request_write_fire) begin
      req_wstrb <= exu_wstrb_i;
    end
  end

  always @(posedge clock) begin
    if (start_main_writeback || (valid && (state == READY) && tlb_miss)) begin
      miss_vaddr <= req_vaddr;
    end
  end

  always @(posedge clock) begin
    if (start_main_writeback || ((state == READY) && (ready_next_state == SENDFILLREQ))) begin
      miss_paddr <= lookup_paddr;
    end else if (waittlb_resp_ok) begin
      miss_paddr <= ptw_paddr;
    end
  end

  always @(posedge clock) begin
    if ((state == READY) && ((ready_next_state == WRITEBACK) || (ready_next_state == SENDFILLREQ))) begin
      miss_uncache <= lookup_uncache;
    end else if (waittlb_resp_ok) begin
      miss_uncache <= !((ptw_paddr[31:28] == 4'h3) ||
                        (ptw_paddr[31:28] == 4'h8) ||
                        (ptw_paddr[31:28] == 4'ha));
    end
  end

  always @(posedge clock) begin
    if (start_main_writeback) begin
      wb_tag_reg <= cache_wb_tag;
    end
  end

  always @(posedge clock) begin
    if (start_main_writeback) begin
      wb_line_reg <= cache_wb_data;
    end
  end

  always @(posedge clock) begin
    if (start_main_writeback) begin
      wb_index_reg <= req_vaddr[`CONFIG_DCACHE_BLOCKS_WIDTH+`CONFIG_DCACHE_SETS_WIDTH+1:
                                `CONFIG_DCACHE_BLOCKS_WIDTH+2];
    end
  end

  always @(posedge clock) begin
    if (start_flush_writeback) begin
      flush_wb_tag_reg <= cache_wb_tag;
    end
  end

  always @(posedge clock) begin
    if (start_flush_writeback) begin
      flush_wb_line_reg <= cache_wb_data;
    end
  end

  always @(posedge clock) begin
    if (reset || start_main_writeback || start_flush_writeback ||
        ((state == WAITWRITERESP) && bvalid_i) ||
        ((state == WAITFLUSH) && (flush_state == F_WAITRESP) && bvalid_i)) begin
      awaddr_handshake_done <= 1'b0;
    end else if (aw_handshake) begin
      awaddr_handshake_done <= 1'b1;
    end
  end

  always @(posedge clock) begin
    if (reset || start_main_writeback || start_flush_writeback ||
        ((state == WAITWRITERESP) && bvalid_i) ||
        ((state == WAITFLUSH) && (flush_state == F_WAITRESP) && bvalid_i)) begin
      wdata_handshake_done <= 1'b0;
    end else if (w_handshake && wlast_o) begin
      wdata_handshake_done <= 1'b1;
    end
  end

  always @(posedge clock) begin
    if (reset || start_main_writeback || start_flush_writeback) begin
      wb_ptr <= {BLOCKS_WIDTH{1'b0}};
    end else if (w_handshake && !wlast_o && active_writeback) begin
      wb_ptr <= wb_ptr + 1'b1;
    end
  end

  always @(posedge clock) begin
    if ((state == WAITFLUSH) && (flush_state == F_IDLE)) begin
      flush_index <= {SETS_WIDTH{1'b0}};
    end else if (flush_set_advance) begin
      flush_index <= next_flush_index;
    end
  end

  always @(posedge clock) begin
    if ((state == WAITFLUSH) && (flush_state == F_IDLE)) begin
      flush_way <= {WAY_WIDTH{1'b0}};
    end else if (flush_way_advance) begin
      flush_way <= next_flush_way;
    end
  end

  assign flush_way_advance = (((state == WAITFLUSH) && (flush_state == F_NEXT) && !flush_line_dirty) ||
                              ((state == WAITFLUSH) && (flush_state == F_WAITRESP) && bvalid_i));
  assign flush_set_advance = (((state == WAITFLUSH) && (flush_state == F_NEXT) && !flush_line_dirty && flush_line_last_way) ||
                              ((state == WAITFLUSH) && (flush_state == F_WAITRESP) && bvalid_i && flush_line_last_way));

  always @(posedge clock) begin
    if (reset) begin
      uncache_rvalid <= 1'b0;
    end else if (consume_resp) begin
      uncache_rvalid <= 1'b0;
    end else if (fill_done && miss_uncache && !rresp_i[1]) begin
      uncache_rvalid <= 1'b1;
    end
  end

  always @(posedge clock) begin
    if (fill_done && miss_uncache) begin
      uncache_rdata <= rdata_i;
    end
  end

  always @(posedge clock) begin
    if (fill_done && miss_uncache) begin
      uncache_rresp <= rresp_i;
    end
  end

  always @(posedge clock) begin
    if (reset) begin
      uncache_bvalid <= 1'b0;
    end else if (consume_resp) begin
      uncache_bvalid <= 1'b0;
    end else if ((state == WAITWRITERESP) && bvalid_i && miss_uncache) begin
      uncache_bvalid <= 1'b1;
    end
  end

  always @(posedge clock) begin
    if ((state == WAITWRITERESP) && bvalid_i && miss_uncache) begin
      uncache_bresp <= bresp_i;
    end
  end

  wire fault_set;
  assign fault_set = ((state == WAITTLB) && d_ptw_resp_valid_i &&
                      (d_ptw_page_fault_i || d_ptw_access_fault_i)) ||
                     ((state == READY) && curr_fault) ||
                     (fill_done && rresp_i[1]) ||
                     ((state == WAITWRITERESP) && bvalid_i && !miss_uncache && bresp_i[1]);

  always @(posedge clock) begin
    if (reset) begin
      fault_resp_valid <= 1'b0;
    end else if (consume_resp) begin
      fault_resp_valid <= 1'b0;
    end else if (fault_set) begin
      fault_resp_valid <= 1'b1;
    end
  end

  always @(posedge clock) begin
    if (fault_set) begin
      fault_is_write <= ({1{(state == WAITTLB) || ((state == READY) && curr_fault)}} & req_is_write) |
                        ({1{fill_done && rresp_i[1]}} & 1'b0) |
                        ({1{(state == WAITWRITERESP) && bvalid_i && !miss_uncache && bresp_i[1]}} & 1'b1);
    end
  end

  always @(posedge clock) begin
    if (fault_set) begin
      fault_resp_code <= ({2{(state == WAITTLB) || ((state == READY) && curr_fault)}} & DATA_SLVERR) |
                         ({2{fill_done && rresp_i[1]}} & rresp_i) |
                         ({2{(state == WAITWRITERESP) && bvalid_i && !miss_uncache && bresp_i[1]}} & bresp_i);
    end
  end

endmodule
