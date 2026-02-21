module ysyx_25030067_one_hot_to_binary #(
  parameter integer ASSOC = 4,
  parameter integer WAY_W = 2
)(
  input   [ASSOC-1:0] tag_cmp_res,
  output  [WAY_W-1:0] way
);

  function [WAY_W-1:0] onehot_to_index;
    input [ASSOC-1:0] onehot;
    integer i;
    begin
      onehot_to_index = {WAY_W{1'b0}};
      for (i = 0; i < ASSOC; i = i + 1) begin
        if (onehot[i])
          onehot_to_index = i[WAY_W-1:0];
      end
    end
  endfunction

  assign way = onehot_to_index(tag_cmp_res);

endmodule
