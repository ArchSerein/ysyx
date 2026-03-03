`include "autoconf.vh"
`include "ysyx_25030067_riscv_param.vh"
module ysyx_25030067_dcache (
  input                           clock,
  input                           reset,

  // read channal
  input                           exu_arvalid_i,
  output                          dcache_arready_o,
  input   [ 2: 0]                 exu_arsize_i,
  input   [31: 0]                 exu_araddr_i,

  output  [`DATA_WIDTH-1:0]       dcache_rdata_o,
  output                          dcache_rvalid_o,
  output  [ 1: 0]                 dcache_rresp_o,
  input                           lsu_rready_i,
  // write channal
  input                           exu_awvalid_i,
  output                          dcache_awready_o,
  input   [31: 0]                 exu_awaddr_i,
  input   [ 2: 0]                 exu_awsize_i,

  input                           exu_wvalid_i,
  output                          dcache_wready_o,
  input   [31: 0]                 exu_wdata_i,
  input   [ 3: 0]                 exu_wstrb_i,

  output  [ 1: 0]                 dcache_bresp_o,
  output                          dcache_bvalid_o,
  input                           lsu_bready_i,

  input                           dcache_flush,
  output                          wait_cache_flush,
  // axi read channal
  input                           dcache_arready_i,
  output  [ 7:0]                  dcache_arlen_o,
  output  [ 2:0]                  dcache_arsize_o,
  output  [ 1:0]                  dcache_arburst_o,
  output                          dcache_arvalid_o,
  output  [`ADDR_WIDTH-1:0]       dcache_araddr_o,

  input                           dcache_rvalid_i,
  input   [`DATA_WIDTH-1:0]       dcache_rdata_i,
  input   [ 1:0]                  dcache_rresp_i,
  input                           dcache_rlast_i,
  output                          dcache_rready_o,

  // axi write channal
  // to memory
  input                           dcache_awready_i,
  output                          dcache_awvalid_o,
  output  [31: 0]                 dcache_awaddr_o,
  output  [ 7:0]                  dcache_awlen_o,
  output  [ 2:0]                  dcache_awsize_o,
  output  [ 1:0]                  dcache_awburst_o,

  input                           dcache_wready_i,
  output                          dcache_wvalid_o,
  output  [31: 0]                 dcache_wdata_o,
  output  [ 3: 0]                 dcache_wstrb_o,
  output                          dcache_wlast_o,


  // from memory
  input                           dcache_bvalid_i,
  output                          dcache_bready_o,
  input   [ 1: 0]                 dcache_bresp_i
);

  localparam READY             = 3'b000;
  localparam SENDFILLREQ       = 3'b001;
  localparam WRITEBACK         = 3'b010;
  localparam WAITWREQCOMPLETE  = 3'b011;
  localparam WAITWRITERESP     = 3'b100;
  localparam WAITFILLRESP      = 3'b101;
  localparam RESPONSE          = 3'b110;
  localparam WAITFLUSH         = 3'b111;
  // flush state machine
  localparam F_IDLE            = 3'b000;
  localparam F_SENDREQ         = 3'b001;
  localparam F_WAITREQCOMPLETE = 3'b010;
  localparam F_WAITRESP        = 3'b011;
  localparam F_NEXT            = 3'b100;
  localparam F_FINISH          = 3'b111;

  localparam DATA_OK           = 2'b00 ;
  localparam DATA_EXOKAY       = 2'b01 ;
  localparam DATA_SLVERR       = 2'b10 ;
  localparam DATA_DECERR       = 2'b11 ;

  localparam TAG_WIDTH         = `DATA_WIDTH - `CONFIG_DCACHE_BLOCKS_WIDTH -
                                                `CONFIG_DCACHE_SETS_WIDTH - 'h2;
  wire  [`DATA_WIDTH-1:0]                         data_rd    [0:`CONFIG_DCACHE_ASSOCIATIVITYS-1];
  wire  [TAG_WIDTH-1  :0]                         tag_rd     [0:`CONFIG_DCACHE_ASSOCIATIVITYS-1];
  wire  [`CONFIG_DCACHE_ASSOCIATIVITYS_WIDTH-1:0] wb_way_sel;
  wire  [`CONFIG_DCACHE_SETS_WIDTH-1:0]           wb_index_sel;
  wire  [`CONFIG_DCACHE_SETS_WIDTH+`CONFIG_DCACHE_BLOCKS_WIDTH-1:0] data_bank_addr;
  wire  [`DATA_WIDTH-1:0]                         data_wr_data;
  wire                                            data_fill_wr;
  wire                                            data_miss_wr;
  wire                                            data_hit_wr;
  wire                                            use_refill_ptr;
  wire  [`CONFIG_DCACHE_BLOCKS_WIDTH-1:0]         data_blk_sel;
  reg   [`CONFIG_DCACHE_ASSOCIATIVITYS-1:0]       validArray [0:`CONFIG_DCACHE_SETS-1];
  reg   [`CONFIG_DCACHE_ASSOCIATIVITYS-1:0]       dirtyArray [0:`CONFIG_DCACHE_SETS-1];
  reg   [`CONFIG_DCACHE_ASSOCIATIVITYS_WIDTH-1:0] fifo_ptr   [0:`CONFIG_DCACHE_SETS-1];

  reg   [`DATA_WIDTH-1:0]                         dcache_req_data;
  reg   [`ADDR_WIDTH-1:0]                         dcache_req_addr;
  reg   [            2:0]                         dcache_asize;
  reg   [            2:0]                         asize;
  reg   [            3:0]                         dcache_wstrb;

  reg   [`CONFIG_DCACHE_SETS_WIDTH-1  :0]         flush_index;
  reg   [`CONFIG_DCACHE_ASSOCIATIVITYS_WIDTH-1:0] flush_way;

  wire  [`CONFIG_DCACHE_SETS_WIDTH-1  :0]         index;
  wire  [`CONFIG_DCACHE_BLOCKS_WIDTH-1:0]         offset;
  wire  [TAG_WIDTH-1                  :0]         tag;
  wire  [`CONFIG_DCACHE_ASSOCIATIVITYS_WIDTH-1:0] way;

  wire  [`CONFIG_DCACHE_ASSOCIATIVITYS_WIDTH-1:0] miss_req_way;

  reg   [2                            :0]         mshr;
  reg   [2                            :0]         flush_state;
  wire  [2                            :0]         flush_next_state;
  wire  [2                            :0]         f_idle_next_state;
  wire  [2                            :0]         f_next_next_state;
  wire  [2                            :0]         f_sendreq_next_state;
  wire  [2                            :0]         f_waitreq_next_state;
  wire  [2                            :0]         f_waitresp_next_state;
  wire  [2                            :0]         f_finish_next_state;
  wire  [2                            :0]         mshr_next_state;
  wire  [2                            :0]         ready_next_state;
  wire  [2                            :0]         waitflush_next_state;
  wire  [2                            :0]         writeback_next_state;
  wire  [2                            :0]         waitwriteresp_next_state;
  wire  [2                            :0]         wait_wreq_next_state;
  wire  [2                            :0]         sendfillreq_next_state;
  wire  [2                            :0]         waitfillresp_next_state;
  wire  [2                            :0]         response_next_state;

  wire                                            fill_data_valid;
  wire                                            uncache_addr;
  wire  [`CONFIG_DCACHE_ASSOCIATIVITYS_WIDTH-1:0] next_fifo_ptr   [0:`CONFIG_DCACHE_SETS-1];

  wire                                            awaddr_handshake_succ;
  wire                                            wdata_handshake_succ;
  wire                                            wait_wreq_complete;
  // read addr channal or write addr channal and data channal
  wire                                            handshake_succ;
  wire                                            resp_succ;
  wire                                            need_write_back;

  reg                                             awaddr_handshake_done;
  reg                                             wdata_handshake_done;

  wire                                            hit;
  reg                                             valid;
  reg                                             is_write_req_reg;
  wire                                            is_write_req;
  always @(posedge clock) begin
    if (reset)
      mshr  <= READY;
    else
      mshr  <=  mshr_next_state;
  end

  always @(posedge clock) begin
    if  (reset)
      flush_state <= F_IDLE;
    else
      flush_state <= flush_next_state;
  end

  // NOTE:
  // Temporarily retained: valid
  wire        valid_next_state;
  wire        read_handshake;
  wire        awrite_hanshake;
  wire        write_hanshake;

  assign read_handshake   = exu_arvalid_i && dcache_arready_o;
  assign awrite_hanshake  = exu_awvalid_i && dcache_awready_o;
  assign write_hanshake   = exu_wvalid_i  && dcache_wready_o ;
  assign valid_next_state =
                          reset ? 1'b0 :
                          (read_handshake | awrite_hanshake &
                            write_hanshake) ? 1'b1 :
                          ((lsu_rready_i && dcache_rvalid_o) ||
                           (lsu_bready_i && dcache_bvalid_o)) ? 1'b0 :
                          valid;
  always @(posedge clock) begin
    valid <= valid_next_state;
  end

  // hit
  wire   [`DATA_WIDTH-1:0]                    req_addr;
  wire   [`CONFIG_DCACHE_ASSOCIATIVITYS-1:0]  tag_cmp_res;
  assign req_addr = exu_arvalid_i ? exu_araddr_i : exu_awaddr_i;
  assign offset   = dcache_req_addr[`CONFIG_DCACHE_BLOCKS_WIDTH+1:2];
  assign index    = dcache_req_addr[`CONFIG_DCACHE_BLOCKS_WIDTH+`CONFIG_DCACHE_SETS_WIDTH+1:
                                    `CONFIG_DCACHE_BLOCKS_WIDTH+2];
  assign tag      = dcache_req_addr[`DATA_WIDTH-1:`CONFIG_DCACHE_BLOCKS_WIDTH+`CONFIG_DCACHE_SETS_WIDTH+2];
  genvar i;
  generate
    for (i = 0; i < `CONFIG_DCACHE_ASSOCIATIVITYS; i++) begin : g_tag_cmp
      assign tag_cmp_res[i] = (tag == tag_rd[i]) && validArray[index][i];
    end
  endgenerate

  ysyx_25030067_one_hot_to_binary #(
    .ASSOC(`CONFIG_DCACHE_ASSOCIATIVITYS),
    .WAY_W(`CONFIG_DCACHE_ASSOCIATIVITYS_WIDTH)
  ) ysyx_25030067_one_hot_to_binary_module (
    .tag_cmp_res  (tag_cmp_res),
    .way          (way)
  );
  assign hit        = (|tag_cmp_res) && valid && mshr == READY;

  always @(posedge clock) begin
    if (~valid & valid_next_state)
      dcache_req_data <= exu_wdata_i;
  end

  always @(posedge clock) begin
    if (~valid & valid_next_state)
      dcache_req_addr <= req_addr;
  end

  assign  asize = exu_awvalid_i ? exu_awsize_i : exu_arsize_i;
  always @(posedge clock) begin
    if (~valid & valid_next_state)
      dcache_asize <= asize;
  end

  always @(posedge clock) begin
    if (~valid & valid_next_state)
      dcache_wstrb <= exu_wstrb_i;
  end

  always @(posedge clock) begin
    if (~valid & valid_next_state)
      is_write_req_reg <= exu_awvalid_i;
    else if (mshr == RESPONSE || hit)
      is_write_req_reg <= 1'b0;
  end

  always @(posedge clock) begin
    if (reset || mshr == WAITWRITERESP || flush_state == F_WAITRESP)
      awaddr_handshake_done <= 1'b0;
    else if (awaddr_handshake_succ)
      awaddr_handshake_done <= 1'b1;
  end

  always @(posedge clock) begin
    if (reset || mshr == WAITWRITERESP || flush_state == F_WAITRESP)
      wdata_handshake_done <= 1'b0;
    else if (wdata_handshake_succ)
      wdata_handshake_done <= 1'b1;
  end

  wire flush_line_dirty;
  wire last_way;
  wire last_set;
  wire flush_set_start;
  wire flush_way_start;
  wire flush_way_advance;
  wire flush_set_advance;
  wire [`CONFIG_DCACHE_SETS_WIDTH-1:0] next_flush_index;
  wire [`CONFIG_DCACHE_ASSOCIATIVITYS_WIDTH-1:0] next_flush_way;

  assign flush_line_dirty = dirtyArray[flush_index][flush_way] & validArray[flush_index][flush_way];

  assign last_way = (flush_way ==
                    (`CONFIG_DCACHE_ASSOCIATIVITYS_WIDTH)'(`CONFIG_DCACHE_ASSOCIATIVITYS-1));

  assign last_set = (flush_index == (`CONFIG_DCACHE_SETS_WIDTH)'(`CONFIG_DCACHE_SETS-1));

  assign next_flush_index = last_set ? flush_index : (flush_index + 1'b1);

  assign next_flush_way   = last_way ? {`CONFIG_DCACHE_ASSOCIATIVITYS_WIDTH{1'b0}} :
                                       (flush_way + 1'b1);

  assign  flush_set_start   = (mshr == WAITFLUSH) && (flush_state == F_IDLE);

  assign  flush_way_start   = flush_set_start || (last_way && dcache_bvalid_i);

  assign  flush_way_advance =
                              ((flush_state == F_WAITRESP) && dcache_bvalid_i) ||
                              ((flush_state == F_NEXT) && !flush_line_dirty);

  assign  flush_set_advance = ((flush_state == F_WAITRESP) && dcache_bvalid_i  &&  last_way) ||
                               (flush_state == F_NEXT && last_way && !flush_line_dirty);

  always @(posedge clock) begin
    if (flush_set_start) begin
      flush_index <= {`CONFIG_DCACHE_SETS_WIDTH{1'b0}};
    end else if (flush_set_advance) begin
      flush_index <= next_flush_index;
    end
  end

  always @(posedge clock) begin
    if (flush_way_start) begin
      flush_way <= {`CONFIG_DCACHE_ASSOCIATIVITYS_WIDTH{1'b0}};
    end else if (flush_way_advance) begin
      flush_way <= next_flush_way;
    end
  end

  assign need_write_back          = validArray[index][fifo_ptr[index]] &&
                                    dirtyArray[index][fifo_ptr[index]] && ~uncache_addr;

  assign handshake_succ           = dcache_arvalid_o && dcache_arready_i;

  assign awaddr_handshake_succ    = dcache_awvalid_o && dcache_awready_i;

  assign wdata_handshake_succ     = dcache_wvalid_o &&  dcache_wready_i && dcache_wlast_o;

  assign wait_wreq_complete       = (awaddr_handshake_done && wdata_handshake_succ) ||
                                    (awaddr_handshake_succ && wdata_handshake_done);

  assign resp_succ                = dcache_rlast_i && dcache_rvalid_i && dcache_rready_o;

  assign ready_next_state         = dcache_flush  ? WAITFLUSH :
                                    (valid && !hit) ? (need_write_back ||
                                                      (uncache_addr && is_write_req)  ? WRITEBACK :
                                                      SENDFILLREQ) : READY;

  assign writeback_next_state     = (awaddr_handshake_succ & wdata_handshake_succ) ?
                                      WAITWRITERESP  :
                                    (awaddr_handshake_succ | wdata_handshake_succ) ?
                                      WAITWREQCOMPLETE :
                                    WRITEBACK;
  assign wait_wreq_next_state     = wait_wreq_complete ? WAITWRITERESP : WAITWREQCOMPLETE;

  assign is_write_req             = is_write_req_reg;

  assign waitwriteresp_next_state = dcache_bvalid_i ? (is_write_req && uncache_addr ? RESPONSE
                                                        : SENDFILLREQ)  : WAITWRITERESP;

  assign sendfillreq_next_state   = handshake_succ ? WAITFILLRESP : SENDFILLREQ;

  assign waitfillresp_next_state  = resp_succ ? RESPONSE : WAITFILLRESP;

  assign waitflush_next_state     = flush_state == F_FINISH ? READY : WAITFLUSH;

  assign response_next_state      = READY;

  assign mshr_next_state          = ({3{mshr == READY}}               & ready_next_state)        |
                                    ({3{mshr == WRITEBACK}}           & writeback_next_state)    |
                                    ({3{mshr == WAITWREQCOMPLETE}}    & wait_wreq_next_state)    |
                                    ({3{mshr == WAITWRITERESP}})      & waitwriteresp_next_state |
                                    ({3{mshr == SENDFILLREQ}}         & sendfillreq_next_state)  |
                                    ({3{mshr == WAITFILLRESP}}        & waitfillresp_next_state) |
                                    ({3{mshr == WAITFLUSH}}           & waitflush_next_state)    |
                                    ({3{mshr == RESPONSE}}            & response_next_state);

  // Flush state switch
  assign  f_idle_next_state       = mshr == WAITFLUSH ? F_NEXT : F_IDLE;

  assign  f_next_next_state       = flush_line_dirty  ? F_SENDREQ :
                                    (last_set && last_way) ?  F_FINISH  :
                                    F_NEXT;

  assign  f_sendreq_next_state    = (awaddr_handshake_succ & wdata_handshake_succ)  ? F_WAITRESP  :
                                    (awaddr_handshake_succ | wdata_handshake_succ)  ?
                                    F_WAITREQCOMPLETE : F_SENDREQ;

  assign  f_waitreq_next_state    = wait_wreq_complete  ? F_WAITRESP  : F_WAITREQCOMPLETE;

  assign  f_waitresp_next_state   = dcache_bvalid_i ? F_NEXT  : F_WAITRESP;

  assign  f_finish_next_state     = F_IDLE;

  assign  flush_next_state        = ({3{flush_state == F_IDLE}})     &  f_idle_next_state     |
                                    ({3{flush_state == F_NEXT}})     &  f_next_next_state     |
                                    ({3{flush_state == F_SENDREQ}})  &  f_sendreq_next_state  |
                                    ({3{flush_state == F_WAITREQCOMPLETE}})
                                                                     &  f_waitreq_next_state  |
                                    ({3{flush_state == F_WAITRESP}}) &  f_waitresp_next_state |
                                    ({3{flush_state == F_FINISH}})   &  f_finish_next_state;
  // exu <----> dcache
  // read
  assign  dcache_arready_o        = (mshr == READY) && ~valid;

  assign  dcache_rvalid_o         = valid && (hit || mshr == RESPONSE ||
                                              (resp_succ && uncache_addr));

  assign  dcache_rdata_o          = (resp_succ && uncache_addr) ? dcache_rdata_i :
                                    data_rd[way];

  assign  dcache_rresp_o          = hit ? DATA_OK : dcache_rresp_i;

  // write
  assign  dcache_wready_o         = (mshr == READY) && ~valid;

  assign  dcache_awready_o        = (mshr == READY) && ~valid;

  assign  dcache_bvalid_o         = valid && (hit || mshr == RESPONSE || (uncache_addr && dcache_bvalid_i));

  assign  dcache_bresp_o          = DATA_OK;

  // read or write req to memory
  assign  dcache_arvalid_o        = mshr == SENDFILLREQ;

  assign  dcache_araddr_o         = uncache_addr ? dcache_req_addr :
                                    {dcache_req_addr[31:`CONFIG_DCACHE_BLOCKS_WIDTH+2],
                                      {`CONFIG_DCACHE_BLOCKS_WIDTH+2{1'b0}}};

  assign  dcache_arlen_o          = uncache_addr ? 8'b0 : 8'(`CONFIG_DCACHE_BLOCKS-1);

  assign  dcache_arburst_o        = `INCR;

  assign  dcache_arsize_o         = uncache_addr ? dcache_asize : 3'b010;

  assign  dcache_rready_o         = mshr == WAITFILLRESP;

  // read or write resp from memory
  assign  dcache_awvalid_o        = (mshr == WRITEBACK) || (mshr == WAITWREQCOMPLETE &&
                                                            ~awaddr_handshake_done) ||
                                    (flush_state == F_SENDREQ) ||
                                    (flush_state == F_WAITREQCOMPLETE && ~awaddr_handshake_done);

  assign  dcache_awburst_o        = `INCR;

  assign  dcache_awsize_o         = uncache_addr ? dcache_asize : 3'b010;

  assign  dcache_awlen_o          = uncache_addr ? 8'b0 : 8'(`CONFIG_DCACHE_BLOCKS-1);

  assign  dcache_awaddr_o         = uncache_addr ? dcache_req_addr :
                                    {tag_rd[wb_way_sel], wb_index_sel,
                                      {`CONFIG_DCACHE_BLOCKS_WIDTH+2{1'b0}}};

  assign  dcache_wdata_o          = uncache_addr ? dcache_req_data :
                                    data_rd[wb_way_sel];

  assign  dcache_wvalid_o         = (mshr == WRITEBACK) ||
                                    (mshr == WAITWREQCOMPLETE && ~wdata_handshake_done) ||
                                    (flush_state == F_SENDREQ) ||
                                    (flush_state == F_WAITREQCOMPLETE && ~wdata_handshake_done);

  assign  dcache_wstrb_o          = uncache_addr ? dcache_wstrb  : 4'b1111;

  assign  dcache_wlast_o          = uncache_addr ?  1'b1  :
                                    mshr == WAITFLUSH ? next_refill_ptr ==
                                                        {`CONFIG_DCACHE_BLOCKS_WIDTH{1'b0}}  :
                                    {`CONFIG_DCACHE_BLOCKS_WIDTH{1'b0}} == next_refill_ptr;

  assign  dcache_bready_o         = mshr == WAITWRITERESP || flush_state == F_WAITRESP;

  assign  miss_req_way            = fifo_ptr[index];

  assign  fill_data_valid         = dcache_rvalid_i && mshr == WAITFILLRESP && (~dcache_rresp_i[1]);

  assign  uncache_addr            = (!(dcache_req_addr[31:28] == 4'h3 ||
                                       dcache_req_addr[31:28] == 4'h8 ||
                                       dcache_req_addr[31:28] == 4'ha)) && ~wait_cache_flush;

  // refill cache
  wire     update_cond;
  wire     dirty_update_cond;
  wire     miss_dirty_update;
  wire     fifo_ptr_update_cond;
  wire     flush_cond;
  assign   flush_cond               = flush_state == F_WAITRESP && dcache_bvalid_i;
  assign   fifo_ptr_update_cond     = mshr == RESPONSE && !uncache_addr;
  assign   update_cond              = dcache_rlast_i && fill_data_valid && ~uncache_addr;
  assign   dirty_update_cond        = valid && hit && is_write_req;
  assign   miss_dirty_update        = mshr == RESPONSE && ~uncache_addr;
  genvar k;
  generate
    for (k = 0; k < `CONFIG_DCACHE_SETS; k++) begin : g_dcache
      // validArray
      always @(posedge clock) begin
        if (reset) begin
          validArray[k] <= {`CONFIG_DCACHE_ASSOCIATIVITYS{1'b0}};
        end else if (index == k && update_cond) begin
          validArray[k][miss_req_way] <= 1'b1;
        end
      end
      // dirtyArray
      // when write hit update dirty
      // when flush or reset clear dirty
      always @(posedge clock) begin
        if (reset) begin
          dirtyArray[k] <= {`CONFIG_DCACHE_ASSOCIATIVITYS{1'b0}};
        end else if (flush_cond && flush_index == k)  begin
          dirtyArray[k][flush_way] <= 1'b0;
        end else if (index == k && dirty_update_cond) begin
          dirtyArray[k][way] <= 1'b1;
        end else if (index == k && miss_dirty_update) begin
          // if ((index == 'h4) && (dcache_req_addr[31:28] == 'h8))
          //   $display("req addr %h dirty %h tag %h", dcache_req_addr, is_write_req, tag);
          dirtyArray[k][miss_req_way] <= is_write_req;
        end
      end
      // fifo_ptr
      // select way(FIFO or lsu)
      assign next_fifo_ptr[k] = fifo_ptr[k] + 'b1;
      always @(posedge clock) begin
        if (reset) begin
          fifo_ptr[k] <= {`CONFIG_DCACHE_ASSOCIATIVITYS_WIDTH{1'b0}};
        end else if (index == k && fifo_ptr_update_cond) begin
          fifo_ptr[k] <= next_fifo_ptr[k];
        end
      end
    end

  endgenerate

  // dataArray
  reg   [`CONFIG_DCACHE_BLOCKS_WIDTH-1:0] refill_ptr;
  wire  [`CONFIG_DCACHE_BLOCKS_WIDTH-1:0] next_refill_ptr;
  wire                                    refill_ptr_update;
  wire                                    refill_ptr_reset;

  // finish write back then reset refill_ptr for read request
  // but write or read address how to match witch refill_ptr
  assign  refill_ptr_reset  = (valid && !hit && mshr == READY) || mshr == WAITWRITERESP;
  assign  refill_ptr_update = fill_data_valid || (dcache_wvalid_o && dcache_wready_i &&
                                                  !uncache_addr);

  wire    [`DATA_WIDTH-1:0] mask;
  wire    [`DATA_WIDTH-1:0] miss_mask_data;
  wire    [`DATA_WIDTH-1:0] hit_mask_data;
  assign mask = {{8{dcache_wstrb[3]}}, {8{dcache_wstrb[2]}},
                {8{dcache_wstrb[1]}}, {8{dcache_wstrb[0]}}};
  assign miss_mask_data = (data_rd[miss_req_way] & ~mask) | (dcache_req_data & mask);
  assign hit_mask_data  = (data_rd[way] & ~mask) | (dcache_req_data & mask);

  assign  wb_way_sel     = (mshr == WAITFLUSH) ? flush_way : miss_req_way;
  assign  wb_index_sel   = (mshr == WAITFLUSH) ? flush_index : index;
  assign  data_fill_wr   = fill_data_valid & ~uncache_addr;
  assign  data_miss_wr   = valid & is_write_req & (mshr == RESPONSE) & ~uncache_addr;
  assign  data_hit_wr    = valid & hit & is_write_req & ~uncache_addr;
  assign  use_refill_ptr = (mshr == WRITEBACK) | (mshr == WAITWREQCOMPLETE) |
                           (mshr == WAITFILLRESP) | (mshr == WAITFLUSH);
  assign  data_blk_sel   = use_refill_ptr ? refill_ptr : offset;
  assign  data_bank_addr = {wb_index_sel, data_blk_sel};
  assign  data_wr_data   = ({`DATA_WIDTH{data_fill_wr}} & dcache_rdata_i) |
                           ({`DATA_WIDTH{data_miss_wr}} & miss_mask_data) |
                           ({`DATA_WIDTH{data_hit_wr}}  & hit_mask_data);

  genvar m;
  generate
    for (m = 0; m < `CONFIG_DCACHE_ASSOCIATIVITYS; m = m + 1) begin : g_tag_bank
      ysyx_25030067_bank #(
        .DATA_WIDTH (TAG_WIDTH),
        .DEPTH      (`CONFIG_DCACHE_SETS)
      ) tag_bank (
        .clock   (clock),
        .reset   (reset),
        .wr_en   (update_cond & (miss_req_way == m)),
        .addr    (wb_index_sel),
        .wr_data (tag),
        .rd_data (tag_rd[m])
      );
    end
  endgenerate

  generate
    for (m = 0; m < `CONFIG_DCACHE_ASSOCIATIVITYS; m = m + 1) begin : g_data_bank
      ysyx_25030067_bank #(
        .DATA_WIDTH (`DATA_WIDTH),
        .DEPTH      (`CONFIG_DCACHE_SETS * `CONFIG_DCACHE_BLOCKS)
      ) data_bank (
        .clock   (clock),
        .reset   (reset),
        .wr_en   (((data_fill_wr | data_miss_wr) & (miss_req_way == m)) |
                   (data_hit_wr & (way == m))),
        .addr    (data_bank_addr),
        .wr_data (data_wr_data),
        .rd_data (data_rd[m])
      );
    end
  endgenerate

  always @(posedge clock) begin
    if (flush_way_start || refill_ptr_reset)
      refill_ptr <= 'b0;
    else if (refill_ptr_update)
      refill_ptr <= next_refill_ptr;
  end
  assign next_refill_ptr = refill_ptr + 'b1;

  assign wait_cache_flush = flush_state != F_IDLE;

  `ifdef CONFIG_TRACE_PERFORMANCE
    import "DPI-C"  function  void  dcache_hit_count();
    import "DPI-C"  function  void  dcache_miss_count();
    import "DPI-C"  function  void  dcache_req_count();
    import "DPI-C"  function  void  dcache_penalty_count();
    reg trace_valid;
    always @ (posedge clock)
    begin
      if (hit && trace_valid) begin
        dcache_hit_count();
      end
      if (!hit && trace_valid) begin
        dcache_miss_count();
      end
      if (mshr != READY) begin
        dcache_penalty_count();
      end
    end
    always @(posedge clock) begin
      if (reset) begin
        trace_valid <= 1'b0;
      end else if (!valid && valid_next_state) begin
        dcache_req_count();
        trace_valid <= 1'b1;
      end else begin
        trace_valid <= 1'b0;
      end
    end
  `endif
endmodule
