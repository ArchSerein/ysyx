`include "./include/generated/autoconf.vh"
`include "riscv_param.vh"
module ysyx_25030067_icache (
  input                           clock,
  input                           reset,

  input                           excp_flush,
  input                           mret_flush,

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
  output  [WIDTH-1:0]             icache_araddr_o,

  input                           icache_rvalid_i,
  input   [WIDTH-1:0]             icache_rdata_i,
  input   [ 1:0]                  icache_rresp_i,
  input                           icache_rlast_i,
  output                          icache_rready_o
);

  parameter   WIDTH       = 32;
  parameter   OFFSET      = 4;
  parameter   INDEX       = 2;
  parameter   BLOCK       = 4;
  parameter   TAG         = WIDTH - OFFSET - INDEX;

  wire      [WIDTH-1:0]     raddr;
  wire      [WIDTH-1:0]     icu_snpc;
  reg [`IFU_ICU_BUS_WIDTH-1:0] ifu_icu_bus;
  reg                          ifu_excp_bus;
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
  assign {
    raddr,
    icu_snpc
  } = ifu_icu_bus;

  reg valid;
  wire has_flush_sign;
  always @(posedge clock) begin
    if (has_flush_sign) begin
      valid <= 1'b0;
    end else if (ifu_valid_i && ready_o) begin
      valid <= 1'b1;
    end else if (valid_o && deu_ready_i) begin
      valid <= 1'b0;
    end
  end
  assign has_flush_sign = branch_flush || excp_flush || mret_flush || reset;

  reg [WIDTH-1:0]          dataArray[BLOCK-1:0][OFFSET-1:0];
  reg [TAG-1:0]            tagArray[BLOCK-1:0];
  reg [BLOCK-1:0]          validArray;
  reg [WIDTH-1:0]          miss_req_addr;
  wire  [INDEX-1:0]        index;
  wire  [OFFSET-3:0]       offset;
  wire  [TAG-1:0]          tag;
  wire  [INDEX-1:0]        miss_req_index;
  wire  [TAG-1:0]          miss_req_tag;
  wire  [OFFSET-3:0]       miss_req_offset;
  wire                     hit;
  wire  [WIDTH-1:0]        hit_data;

  assign tag    = raddr[ WIDTH-1: OFFSET+INDEX];
  assign index  = raddr[ OFFSET+INDEX-1: OFFSET];
  assign offset = raddr[ OFFSET-1: 2];

  localparam INST_OK      = 2'b00;
  localparam INST_EXOKAY  = 2'b01;
  localparam INST_SLVERR  = 2'b10;
  localparam INST_DECERR  = 2'b11;

  reg [ 1:0]  mshr;
  localparam  READY         = 2'b00;
  localparam  SENDFILLREQ   = 2'b01;
  localparam  WAITFILLRESP  = 2'b10;
  localparam  RESPONSE      = 2'b11;

  wire  [ 1:0]  mshr_next_state;
  wire  [ 1:0]  ready_next_state;
  wire  [ 1:0]  sendfillreq_next_state;
  wire  [ 1:0]  waitfillresp_next_state;
  wire  [ 1:0]  response_next_state;
  wire          fill_data_valid;
  wire          uncache_addr;
  wire          access_data_fault;

  wire  [WIDTH-1:0]  rdata;

  always @(posedge clock) begin
    if (reset)
      mshr <= READY;
    else
      mshr <= mshr_next_state;
  end

  assign ready_next_state         = valid && !hit  ? SENDFILLREQ : READY;
  assign sendfillreq_next_state   = icache_arready_i ? WAITFILLRESP : SENDFILLREQ;
  assign waitfillresp_next_state  = icache_rlast_i && icache_rvalid_i ? RESPONSE : WAITFILLRESP;
  assign response_next_state      = READY;
  assign mshr_next_state          = {2{mshr == READY}} & ready_next_state |
                                    {2{mshr == SENDFILLREQ}} & sendfillreq_next_state |
                                    {2{mshr == WAITFILLRESP}} & waitfillresp_next_state |
                                    {2{mshr == RESPONSE}} & response_next_state;

  assign                      hit = tagArray[index] == tag && validArray[index] && valid;

  always @ (posedge clock) begin
    if (!hit && valid && mshr == READY) begin
      miss_req_addr <= raddr;
    end
  end

  reg  [ 1:0]      fill_data_ptr;
  wire [ 1:0]      next_fill_data_ptr;
  assign next_fill_data_ptr = fill_data_ptr + 2'b01;
  always @ (posedge clock) begin
    if (!hit && valid && mshr == READY) begin
      fill_data_ptr <= offset;
    end else if (fill_data_valid) begin
      fill_data_ptr <= next_fill_data_ptr;
    end
  end
  always @ (posedge clock) begin
    if (fill_data_valid && !uncache_addr) begin
      dataArray[miss_req_index][fill_data_ptr]  <= icache_rdata_i;
    end
  end
  always @ (posedge clock) begin
    if (icache_rlast_i && fill_data_valid && !uncache_addr) begin
      tagArray[miss_req_index]   <= miss_req_tag;
    end
  end
  always @ (posedge clock) begin
    if (icache_flush) begin
      validArray                 <= {BLOCK{1'b0}};
    end else if (icache_rlast_i && fill_data_valid && !uncache_addr) begin
      validArray[miss_req_index] <= 1'b1;
    end
  end

  assign icu_excp_bus_o = {access_data_fault, ifu_excp_bus};

  assign miss_req_tag             = miss_req_addr[WIDTH-1: OFFSET+INDEX];
  assign miss_req_index           = miss_req_addr[OFFSET+INDEX-1: OFFSET]; 
  assign miss_req_offset          = miss_req_addr[OFFSET-1: 2];
  assign fill_data_valid          = mshr == WAITFILLRESP && icache_rvalid_i && (icache_rresp_i == INST_OK || icache_rresp_i == INST_EXOKAY);
  assign uncache_addr             = miss_req_addr[31:16] == 16'h0f00;
  assign access_data_fault        = mshr == WAITFILLRESP && icache_rvalid_i && (icache_rresp_i == INST_DECERR || icache_rresp_i == INST_SLVERR);
  assign rdata                    = (icache_rvalid_i && uncache_addr) ? icache_rdata_i :
                                    (mshr == RESPONSE) ? dataArray[miss_req_index][miss_req_offset] :
                                                         dataArray[index][offset];

  assign icache_rready_o          = mshr == WAITFILLRESP;
  assign icache_araddr_o          = miss_req_addr;
  assign icache_arvalid_o         = mshr == SENDFILLREQ;
  assign icache_arsize_o          = 3'b010;
  assign icache_arburst_o         = 2'b10;
  assign icache_arlen_o           = (uncache_addr) ? 0 : 3;

  assign icu_deu_bus_o = {
    raddr,
    icu_snpc,
    rdata
  };
  assign ready_o                  = (!valid || (valid_o && deu_ready_i)) && (mshr == READY || mshr == RESPONSE);
  assign valid_o                  = (hit || (mshr == RESPONSE && !uncache_addr) || (uncache_addr && icache_rvalid_i)) && valid;

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
