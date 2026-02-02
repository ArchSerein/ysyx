module ysyx_25030067_btb (
  input                 clock,
  input                 reset,
  // predict
  input  [31:0]         ifu_pc_i,
  output                btb_valid_o,
  output [31:0]         predict_pc_o,
  // update
  input                 exu_valid_i,
  input                 exu_br_taken_i,
  input  [31:0]         exu_pc_i,
  input  [31:0]         exu_target_i
);

  localparam BTB_SET    = 16;
  localparam BTB_WAY    = 1;
  localparam BTB_BLOCK  = 1;
  localparam DATA_WIDTH = 32;
  localparam TAG_WIDTH  = 32 - 2 - 4;
  localparam INDEX_WIDTH = 4;

  reg [DATA_WIDTH-1:0]  btb_data  [BTB_SET-1:0];
  reg [TAG_WIDTH-1:0]   btb_tag   [BTB_SET-1:0];
  reg [BTB_SET-1:0]     btb_valid;

  wire [INDEX_WIDTH-1:0] index;
  wire [TAG_WIDTH-1:0]   tag;

  assign index = ifu_pc_i[2+INDEX_WIDTH-1:2];
  assign tag   = ifu_pc_i[31:2+INDEX_WIDTH];

  wire [INDEX_WIDTH-1:0] update_index;
  wire [TAG_WIDTH-1:0]   update_tag;
  wire                   update;
  assign update_index = exu_pc_i[2+INDEX_WIDTH-1:2];
  assign update_tag   = exu_pc_i[31:2+INDEX_WIDTH];
  assign update       = exu_valid_i && exu_br_taken_i;
  always @(posedge clock) begin
    if (update) begin
      btb_data[update_index] <= exu_target_i;
    end
  end
  always @(posedge clock) begin
    if (update) begin
      btb_tag[update_index] <= update_tag;
    end
  end
  always @(posedge clock) begin
    if (reset) begin
      btb_valid <= {BTB_SET{1'b0}};
    end if (update) begin
      btb_valid[index] <= 1'b1;
    end
  end


  assign btb_valid_o  = btb_valid[index] && (|(btb_tag[index] ^ tag));
  assign predict_pc_o = btb_data[index];
endmodule
