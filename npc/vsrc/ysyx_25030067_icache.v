`include "autoconf.vh"
`include "ysyx_25030067_riscv_param.vh"
module ysyx_25030067_icache (
  input                           clock,
  input                           reset,

  input                           excp_flush,
  input                           mret_flush,
  input                           wait_cache_flush,

  output                          ready_o,
  input                           ifu_valid_i,
  input [`IFU_ICU_BUS_WIDTH-1:0]  ifu_icu_bus_i,
  input                           ifu_excp_bus_i,

  output [`ICU_DEU_BUS_WIDTH-1:0] icu_deu_bus_o,
  output [1:0]                    icu_excp_bus_o,
  output                          valid_o,
  input                           deu_ready_i,

  input                           branch_flush,
  input                           icache_flush,

  input                           icache_arready_i,
  output  [ 7:0]                  icache_arlen_o,
  output  [ 2:0]                  icache_arsize_o,
  output  [ 1:0]                  icache_arburst_o,
  output                          icache_arvalid_o,
  output  [`DATA_WIDTH-1:0]       icache_araddr_o,

  input                           icache_rvalid_i,
  input   [`DATA_WIDTH-1:0]       icache_rdata_i,
  input   [ 1:0]                  icache_rresp_i,
  input                           icache_rlast_i,
  output                          icache_rready_o
);

  localparam  OFFSET_WIDTH      = 2;
  localparam  INDEX_WIDTH       = 2;
  localparam  LINE_WORDS        = (1 << OFFSET_WIDTH);
  localparam  LINE_DATA_WIDTH   = `DATA_WIDTH * LINE_WORDS;
  localparam  TAG_WIDTH         = `DATA_WIDTH - INDEX_WIDTH - OFFSET_WIDTH - 2;
  localparam  BANK_DATA_WIDTH   = TAG_WIDTH + LINE_DATA_WIDTH;
  localparam  BLOCK             = (1 << INDEX_WIDTH);
  localparam  [7:0] CACHE_ARLEN = LINE_WORDS - 1;

  localparam  INST_OK      = 2'b00;
  localparam  INST_EXOKAY  = 2'b01;
  localparam  INST_SLVERR  = 2'b10;
  localparam  INST_DECERR  = 2'b11;

  localparam  READY         = 2'b00;
  localparam  SENDFILLREQ   = 2'b01;
  localparam  WAITFILLRESP  = 2'b10;
  localparam  RESPONSE      = 2'b11;

  wire  [`DATA_WIDTH-1:0]        raddr;
  wire  [`DATA_WIDTH-1:0]        icu_snpc;
  reg   [`IFU_ICU_BUS_WIDTH-1:0] ifu_icu_bus;
  reg                            ifu_excp_bus;
  reg                            valid;
  reg   [BLOCK-1:0]              validArray;
  reg   [`DATA_WIDTH-1:0]        miss_req_addr;
  reg   [1:0]                    mshr;
  reg   [OFFSET_WIDTH-1:0]       fill_data_ptr;

  wire                           has_flush_sign;
  wire  [TAG_WIDTH-1:0]          tag;
  wire  [INDEX_WIDTH-1:0]        index;
  wire  [OFFSET_WIDTH-1:0]       offset;
  wire  [TAG_WIDTH-1:0]          miss_req_tag;
  wire  [INDEX_WIDTH-1:0]        miss_req_index;
  wire  [OFFSET_WIDTH-1:0]       miss_req_offset;
  wire  [INDEX_WIDTH-1:0]        access_index;
  wire                           hit;
  wire  [`DATA_WIDTH-1:0]        hit_data;
  wire  [`DATA_WIDTH-1:0]        miss_line_word;
  wire  [`DATA_WIDTH-1:0]        rdata;

  wire  [ 1:0]  mshr_next_state;
  wire  [ 1:0]  ready_next_state;
  wire  [ 1:0]  sendfillreq_next_state;
  wire  [ 1:0]  waitfillresp_next_state;
  wire  [ 1:0]  response_next_state;
  wire          fill_data_valid;
  wire          uncache_addr;
  wire          access_data_fault;
  wire  [`IFU_ICU_BUS_WIDTH-1:0] ifu_icu_bus_next;
  wire                           ifu_excp_bus_next;
  wire                           valid_next;
  wire  [`DATA_WIDTH-1:0]        miss_req_addr_next;
  wire  [OFFSET_WIDTH-1:0]       fill_data_ptr_next;
  wire  [BLOCK-1:0]              validArray_next;
  wire  [BLOCK-1:0]              validArray_set_mask;
  wire                           miss_start;
  wire                           fill_advance;
  wire                           keep_fill_ptr;
  wire                           sel_uncache_rdata;
  wire                           sel_response_data;
  wire                           sel_hit_data;

  wire  [BANK_DATA_WIDTH-1:0] bank_rd_data;
  wire  [TAG_WIDTH-1:0]       bank_tag;
  wire  [LINE_DATA_WIDTH-1:0] bank_line;
  wire  [LINE_DATA_WIDTH-1:0] bank_line_next;
  wire                        bank_wr_en;
  wire  [BANK_DATA_WIDTH-1:0] bank_wr_data;
  wire  [LINE_DATA_WIDTH-1:0] fill_word;
  wire  [LINE_DATA_WIDTH-1:0] fill_mask;

  assign {raddr, icu_snpc}          = ifu_icu_bus;
  assign has_flush_sign             = branch_flush || excp_flush || mret_flush ||
                                      reset || wait_cache_flush;

  assign tag                        = raddr[`DATA_WIDTH-1: INDEX_WIDTH+OFFSET_WIDTH+2];
  assign index                      = raddr[INDEX_WIDTH+OFFSET_WIDTH+1: OFFSET_WIDTH+2];
  assign offset                     = raddr[OFFSET_WIDTH+1: 2];
  assign miss_req_tag               = miss_req_addr[`DATA_WIDTH-1: INDEX_WIDTH+OFFSET_WIDTH+2];
  assign miss_req_index             = miss_req_addr[INDEX_WIDTH+OFFSET_WIDTH+1: OFFSET_WIDTH+2];
  assign miss_req_offset            = miss_req_addr[OFFSET_WIDTH+1: 2];

  assign access_index               = (mshr == SENDFILLREQ || mshr == WAITFILLRESP
                                        || mshr == RESPONSE) ? miss_req_index : index;

  ysyx_25030067_bank #(
    .DATA_WIDTH (BANK_DATA_WIDTH),
    .DEPTH      (BLOCK)
  ) u_bank (
    .clock   (clock),
    .reset   (reset),
    .wr_en   (bank_wr_en),
    .addr    (access_index),
    .wr_data (bank_wr_data),
    .rd_data (bank_rd_data)
  );

  assign {bank_tag, bank_line}      = bank_rd_data;
  assign fill_word                  = {{(LINE_DATA_WIDTH-`DATA_WIDTH){1'b0}}, icache_rdata_i}
                                        << (`DATA_WIDTH * fill_data_ptr);
  assign fill_mask                  = {{(LINE_DATA_WIDTH-`DATA_WIDTH){1'b0}}, {`DATA_WIDTH{1'b1}}}
                                        << (`DATA_WIDTH * fill_data_ptr);
  assign bank_line_next             = (bank_line & ~fill_mask) | fill_word;
  assign bank_wr_en                 = fill_data_valid && !uncache_addr;
  assign bank_wr_data               = {miss_req_tag, bank_line_next};

  assign hit                        = (bank_tag == tag) && validArray[index] && valid;
  assign hit_data                   = bank_line[`DATA_WIDTH * offset +: `DATA_WIDTH];
  assign miss_line_word             = bank_line[`DATA_WIDTH * miss_req_offset +: `DATA_WIDTH];

  assign ready_next_state           = (valid && !hit) ? SENDFILLREQ : READY;
  assign sendfillreq_next_state     = icache_arready_i ? WAITFILLRESP : SENDFILLREQ;
  assign waitfillresp_next_state    = (icache_rlast_i && icache_rvalid_i) ? RESPONSE : WAITFILLRESP;
  assign response_next_state        = READY;
  assign mshr_next_state            = {2{(mshr == READY)       }} & ready_next_state |
                                      {2{(mshr == SENDFILLREQ) }} & sendfillreq_next_state |
                                      {2{(mshr == WAITFILLRESP)}} & waitfillresp_next_state |
                                      {2{(mshr == RESPONSE)    }} & response_next_state;
  assign ifu_icu_bus_next           = (ifu_valid_i && ready_o) ? ifu_icu_bus_i : ifu_icu_bus;
  assign ifu_excp_bus_next          = (ifu_valid_i && ready_o) ? ifu_excp_bus_i : ifu_excp_bus;
  assign valid_next                 = !has_flush_sign &&
                                      ((ifu_valid_i && ready_o) ||
                                       (valid && !(valid_o && deu_ready_i)));
  assign miss_req_addr_next         = (!hit && valid && (mshr == READY)) ? raddr : miss_req_addr;
  assign miss_start                 = (!hit && valid && (mshr == READY));
  assign fill_advance               = !miss_start && fill_data_valid;
  assign keep_fill_ptr              = !miss_start && !fill_data_valid;
  assign fill_data_ptr_next         = ({OFFSET_WIDTH{miss_start}} & offset) |
                                      ({OFFSET_WIDTH{fill_advance}} & (fill_data_ptr +
                                                                        {{(OFFSET_WIDTH-1){1'b0}}, 1'b1})) |
                                      ({OFFSET_WIDTH{keep_fill_ptr}} & fill_data_ptr);
  assign validArray_set_mask        = {{(BLOCK-1){1'b0}}, 1'b1} << miss_req_index;
  assign validArray_next            = (icache_rlast_i && fill_data_valid && !uncache_addr) ?
                                      (validArray | validArray_set_mask) : validArray;

  assign fill_data_valid            = (mshr == WAITFILLRESP) && icache_rvalid_i &&
                                      ((icache_rresp_i == INST_OK) ||
                                       (icache_rresp_i == INST_EXOKAY));
  assign uncache_addr               = (miss_req_addr[31:16] == 16'h0f00);
  assign access_data_fault          = (mshr == WAITFILLRESP) && icache_rvalid_i &&
                                      ((icache_rresp_i == INST_DECERR) ||
                                       (icache_rresp_i == INST_SLVERR));
  assign sel_uncache_rdata          = icache_rvalid_i && uncache_addr;
  assign sel_response_data          = !sel_uncache_rdata && (mshr == RESPONSE);
  assign sel_hit_data               = !sel_uncache_rdata && (mshr != RESPONSE);
  assign rdata                      = ({`DATA_WIDTH{sel_uncache_rdata}} & icache_rdata_i) |
                                      ({`DATA_WIDTH{sel_response_data}} & miss_line_word) |
                                      ({`DATA_WIDTH{sel_hit_data}} & hit_data);

  assign icu_excp_bus_o             = {access_data_fault, ifu_excp_bus};
  assign icache_rready_o            = (mshr == WAITFILLRESP);
  assign icache_araddr_o            = miss_req_addr;
  assign icache_arvalid_o           = (mshr == SENDFILLREQ);
  assign icache_arsize_o            = 3'b010;
  assign icache_arburst_o           = 2'b10;
  assign icache_arlen_o             = uncache_addr ? 8'd0 : CACHE_ARLEN;

  assign icu_deu_bus_o = {
    raddr,
    icu_snpc,
    rdata
  };
  assign ready_o                  = (!valid || (valid_o && deu_ready_i)) &&
                                    ((mshr == READY) || (mshr == RESPONSE));
  assign valid_o                  = (hit || ((mshr == RESPONSE) && !uncache_addr) ||
                                            (uncache_addr && icache_rvalid_i)) &&
                                    valid && !has_flush_sign;

  always @(posedge clock) begin
    ifu_icu_bus <= ifu_icu_bus_next;
  end

  always @(posedge clock) begin
    ifu_excp_bus <= ifu_excp_bus_next;
  end

  always @(posedge clock) begin
    if (reset) begin
      valid <= 1'b0;
    end else begin
      valid <= valid_next;
    end
  end

  always @(posedge clock) begin
    if (reset) begin
      mshr <= READY;
    end else begin
      mshr <= mshr_next_state;
    end
  end

  always @(posedge clock) begin
    miss_req_addr <= miss_req_addr_next;
  end

  always @(posedge clock) begin
    fill_data_ptr <= fill_data_ptr_next;
  end

  always @(posedge clock) begin
    if (reset || icache_flush) begin
      validArray <= {BLOCK{1'b0}};
    end else begin
      validArray <= validArray_next;
    end
  end

  `ifdef CONFIG_TRACE_PERFORMANCE
    import "DPI-C"  function  void  hit_cnt();
    import "DPI-C"  function  void  miss_count();
    import "DPI-C" function void ifu_inst_count();
    import "DPI-C"  function  void  penalty_count();
    reg trace_valid;
    always @ (posedge clock)
    begin
      if (hit && trace_valid) begin
        hit_cnt();
      end
      if (!hit && trace_valid) begin
        miss_count();
      end
      if (reset) begin
        trace_valid <= 1'b0;
      end else if (ifu_valid_i && ready_o) begin
        ifu_inst_count();
        trace_valid <= 1'b1;
      end else begin
        trace_valid <= 1'b0;
      end
    end
    always @ (posedge clock) begin
      if (mshr != READY) begin
        penalty_count();
      end
    end
  `endif
endmodule
