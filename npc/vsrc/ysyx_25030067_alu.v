module ysyx_25030067_alu (
  input [2:0] alu_op_i,
  input [31:0] alu_a_i,
  input [31:0] alu_b_i,
  output [31:0] alu_result_o
);

  // Multiplexed adder: a + b (add) or a + ~b + 1 (sub)
  wire        is_sub = alu_op_i[0];
  wire [31:0] adder_b = is_sub ? ~alu_b_i : alu_b_i;
  wire [31:0] adder_res = alu_a_i + adder_b + {31'b0, is_sub};

  wire [31:0] and_res;
  wire [31:0] or_res;
  wire [31:0] xor_res;
  wire [31:0] sll_res;
  wire [31:0] srl_res;
  wire [31:0] sra_res;

  assign and_res = alu_a_i & alu_b_i;
  assign or_res = alu_a_i | alu_b_i;
  assign xor_res = alu_a_i ^ alu_b_i;
  assign sll_res = alu_a_i << alu_b_i[4:0];
  assign srl_res = alu_a_i >> alu_b_i[4:0];
  assign sra_res = $signed(alu_a_i) >>> alu_b_i[4:0];

  wire [31:0] alu_hi_hi_res;
  wire [31:0] alu_hi_lo_res;
  wire [31:0] alu_lo_hi_res;
  wire [31:0] alu_lo_lo_res;
  wire [31:0] alu_hi_res;
  wire [31:0] alu_lo_res;

  assign alu_hi_hi_res = alu_op_i[0] ? xor_res : or_res;
  assign alu_hi_lo_res = alu_op_i[0] ? and_res : srl_res;
  assign alu_lo_hi_res = alu_op_i[0] ? sra_res : sll_res;
  assign alu_lo_lo_res = adder_res;
  assign alu_hi_res = alu_op_i[1] ? alu_hi_hi_res : alu_hi_lo_res;
  assign alu_lo_res = alu_op_i[1] ? alu_lo_hi_res : alu_lo_lo_res;
  assign alu_result_o = alu_op_i[2] ? alu_hi_res : alu_lo_res;
endmodule
