module ysyx_25030067_arbiter #(
  parameter MASTER = 2 )(
  input                 clock,
  input                 reset,
  input [MASTER-1:0]    rreq_i,
  output [MASTER-1:0]   grant_o
);

  reg [MASTER-1:0]  grant;
  wire [MASTER-1:0]  next_grant;

  // one-hot encoding
  assign next_grant = reset ? {{MASTER-1{1'b0}}, 1'b1} : {grant[MASTER-2:0], grant[MASTER-1]};
  always @(posedge clock) begin
    if (|rreq_i | reset) begin
      grant <= next_grant;
    end
  end

  assign grant_o = grant & rreq_i;
endmodule
