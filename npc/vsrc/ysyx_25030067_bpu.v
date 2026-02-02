module ysyx_25030067_bpu (
  input                               clock,
  input                               reset,

  // from exu
  input                               exu_valid_i,
  input                               exu_br_taken_i,

  // to ifu
  output                              predict_taken_o
);

  localparam STRONGLY_TAKEN = 2'b10;
  localparam WEAKLY_TAKEN  = 2'b11;
  localparam WEAKLY_NOT_TAKEN = 2'b01;
  localparam STRONGLY_NOT_TAKEN = 2'b00;

  reg  [1:0]   saturat_counter;
  wire [1:0]   next_saturat_counter;

  always @ (posedge clock) begin
    if (reset) begin
      saturat_counter <= STRONGLY_NOT_TAKEN;
    end else if (exu_valid_i) begin
      saturat_counter <= next_saturat_counter;
    end
  end

  assign next_saturat_counter[1] = (saturat_counter[0] & exu_br_taken_i) | (saturat_counter[1] & (~saturat_counter[0]));
  assign next_saturat_counter[0] =  saturat_counter[1] ^ exu_br_taken_i;
  assign predict_taken_o         = saturat_counter[1];
endmodule
