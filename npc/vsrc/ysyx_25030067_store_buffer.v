`include "ysyx_25030067_riscv_param.vh"

module ysyx_25030067_store_buffer #(
  parameter DEPTH = 8,
  parameter PTR_WIDTH = 3
) (
  input                   clock,
  input                   reset,
  input                   has_flush_i,

  input                   exu_awvalid_i,
  output                  exu_awready_o,
  input  [31:0]           exu_awaddr_i,
  input  [2:0]            exu_awsize_i,
  input                   exu_wvalid_i,
  output                  exu_wready_o,
  input  [31:0]           exu_wdata_i,
  input  [3:0]            exu_wstrb_i,

  input                   store_commit_i,

  output                  issue_awvalid_o,
  input                   issue_awready_i,
  output [31:0]           issue_awaddr_o,
  output [2:0]            issue_awsize_o,
  output                  issue_wvalid_o,
  input                   issue_wready_i,
  output [31:0]           issue_wdata_o,
  output [3:0]            issue_wstrb_o,
  output                  store_pending_o
);

  localparam CNT_WIDTH = PTR_WIDTH + 1;

  reg [31:0] store_addr [0:DEPTH-1];
  reg [2:0]  store_size [0:DEPTH-1];
  reg [31:0] store_data [0:DEPTH-1];
  reg [3:0]  store_strb [0:DEPTH-1];

  reg [PTR_WIDTH-1:0] head_ptr;
  reg [PTR_WIDTH-1:0] tail_ptr;
  reg [CNT_WIDTH-1:0] used_cnt;
  reg [CNT_WIDTH-1:0] committed_cnt;

  wire full;
  wire empty;
  wire can_issue;
  wire enq_fire;
  wire deq_fire;
  wire commit_fire;
  wire has_uncommitted;
  wire [31:0] head_addr;
  wire [2:0]  head_size;
  wire [31:0] head_data;
  wire [3:0]  head_strb;
  wire [PTR_WIDTH-1:0] next_head_ptr;
  wire [PTR_WIDTH-1:0] next_tail_ptr;
  wire [CNT_WIDTH-1:0] next_used_cnt;
  wire [CNT_WIDTH-1:0] next_committed_cnt;

  assign full = (used_cnt == CNT_WIDTH'(DEPTH));
  assign empty = (used_cnt == {CNT_WIDTH{1'b0}});
  assign can_issue = (committed_cnt != {CNT_WIDTH{1'b0}});
  assign has_uncommitted = (used_cnt != committed_cnt);

  assign exu_awready_o = !full && !has_flush_i;
  assign exu_wready_o = !full && !has_flush_i;

  assign enq_fire = exu_awvalid_i && exu_wvalid_i && exu_awready_o && exu_wready_o;
  assign deq_fire = issue_awvalid_o && issue_awready_i && issue_wvalid_o && issue_wready_i;
  assign commit_fire = store_commit_i && (has_uncommitted || enq_fire);

  assign head_addr = store_addr[head_ptr];
  assign head_size = store_size[head_ptr];
  assign head_data = store_data[head_ptr];
  assign head_strb = store_strb[head_ptr];

  assign issue_awvalid_o = can_issue && !empty && !has_flush_i;
  assign issue_awaddr_o = head_addr;
  assign issue_awsize_o = head_size;
  assign issue_wvalid_o = can_issue && !empty && !has_flush_i;
  assign issue_wdata_o = head_data;
  assign issue_wstrb_o = head_strb;
  assign store_pending_o = ~empty;

  always @(posedge clock) begin
    if (enq_fire) begin
      store_addr[tail_ptr] <= exu_awaddr_i;
    end
  end

  always @(posedge clock) begin
    if (enq_fire) begin
      store_size[tail_ptr] <= exu_awsize_i;
    end
  end

  always @(posedge clock) begin
    if (enq_fire) begin
      store_data[tail_ptr] <= exu_wdata_i;
    end
  end

  always @(posedge clock) begin
    if (enq_fire) begin
      store_strb[tail_ptr] <= exu_wstrb_i;
    end
  end

  assign next_head_ptr = head_ptr + 1'b1;
  always @(posedge clock) begin
    if (reset || has_flush_i) begin
      head_ptr <= {PTR_WIDTH{1'b0}};
    end else if (deq_fire) begin
      head_ptr <= next_head_ptr;
    end
  end

  assign next_tail_ptr = tail_ptr + 1'b1;
  always @(posedge clock) begin
    if (reset || has_flush_i) begin
      tail_ptr <= {PTR_WIDTH{1'b0}};
    end else if (enq_fire) begin
      tail_ptr <= next_tail_ptr;
    end
  end

  assign next_used_cnt = used_cnt + CNT_WIDTH'(enq_fire) - CNT_WIDTH'(deq_fire);
  always @(posedge clock) begin
    if (reset || has_flush_i) begin
      used_cnt <= {CNT_WIDTH{1'b0}};
    end else begin
      used_cnt <= next_used_cnt;
    end
  end

  assign next_committed_cnt = committed_cnt + CNT_WIDTH'(commit_fire) - CNT_WIDTH'(deq_fire);
  always @(posedge clock) begin
    if (reset || has_flush_i) begin
      committed_cnt <= {CNT_WIDTH{1'b0}};
    end else begin
      committed_cnt <= next_committed_cnt;
    end
  end

endmodule
