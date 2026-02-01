module ysyx_25030067_alu (
  input [2:0] alu_op_i,
  input [31:0] alu_a_i,
  input [31:0] alu_b_i,
  output [31:0] alu_result_o
);

  wire [31:0] add_res;
  wire [31:0] sub_res;
  wire [31:0] and_res;
  wire [31:0] or_res;
  wire [31:0] xor_res;
  wire [31:0] sll_res;
  wire [31:0] srl_res;
  wire [31:0] sra_res;

  assign add_res = alu_a_i + alu_b_i;
  assign sub_res = alu_a_i - alu_b_i;
  assign and_res = alu_a_i & alu_b_i;
  assign or_res = alu_a_i | alu_b_i;
  assign xor_res = alu_a_i ^ alu_b_i;
  assign sll_res = alu_a_i << alu_b_i[4:0];
  assign srl_res = alu_a_i >> alu_b_i[4:0];
  assign sra_res = $signed(alu_a_i) >>> alu_b_i[4:0];

  assign alu_result_o = alu_op_i[2] ? (alu_op_i[1] ?  (alu_op_i[0] ? xor_res : or_res)  :
                                                      (alu_op_i[0] ? and_res : srl_res)) :
                                      (alu_op_i[1] ?  (alu_op_i[0] ? sra_res : sll_res) :
                                                      (alu_op_i[0] ? sub_res : add_res));
endmodule
