/*
`include "ysyx_25030067_riscv_param.vh"
module ysyx_25030067_div (
  input                           clock,
  input                           reset,

  input                           EN_start,
  input                           is_signed,
  input   [`DATA_WIDTH-1:0]       dividend,
  input   [`DATA_WIDTH-1:0]       divisor,

  input                           EN_result,
  output  [2*`DATA_WIDTH-1:0]     result,
  output                          finish
);

  // counter -> 0 idle
  // counter -> [1, 33] running
  // counter -> 34  result(quotient, remainder) ready
  reg   [`DATA_WIDTH  :0] partial_rem;
  reg   [`DATA_WIDTH-1:0] div_pos;
  reg   [`DATA_WIDTH-1:0] div_neg;
  reg   [`DATA_WIDTH-1:0] quotient;
  reg   [`DATA_WIDTH-1:0] remainder;
  wire  [`DATA_WIDTH-1:0] quotient_val;
  wire  [`DATA_WIDTH  :0] partial_rem_val;
  wire  [`DATA_WIDTH  :0] partial_rem_add;
  wire  [`DATA_WIDTH-1:0] next_quotient;
  wire  [`DATA_WIDTH  :0] next_partial_rem;
  wire  [`DATA_WIDTH-1:0] dvd_abs;
  wire  [`DATA_WIDTH-1:0] div_abs;
  wire  [`DATA_WIDTH-1:0] neg_div_abs;
  wire  [`DATA_WIDTH-1:0] final_q;
  wire  [`DATA_WIDTH-1:0] final_r;
  wire  [`DATA_WIDTH:0]   rem_fix;

  reg   [ 5: 0]           counter;
  wire  [ 5: 0]           next_count_val;
  wire                    inc_en;
  wire                    clr_en;
  wire                    dividend_sign;
  wire                    divisor_sign;
  wire                    quotient_sign;

  reg                     sign_q;
  reg                     sign_r;

  assign  inc_en =  (counter == 6'h0 && EN_start) ||
                    (counter >= 6'h1 && counter <= 6'h21);

  assign  clr_en =  (counter == 6'h22 && EN_result) | reset;

  assign  next_count_val =  (counter + {5'b0, inc_en}) & {6{~clr_en}};

  always @(posedge clock) begin
    counter <= next_count_val;
  end

  wire  sign_q_val;
  assign sign_q_val = is_signed ? (dividend_sign ^ divisor_sign) : 1'b0;
  always @(posedge clock) begin
    if (EN_start)
      sign_q        <= sign_q_val;
  end

  wire  sign_r_val;
  assign sign_r_val = is_signed ? dividend_sign : 1'b0;
  always @(posedge clock) begin
    if (EN_start)
      sign_r        <= sign_r_val;
  end

  assign  dividend_sign = dividend[`DATA_WIDTH-1];
  assign  divisor_sign  = divisor[`DATA_WIDTH-1];

  assign  quotient_sign =
          is_signed ? (dividend_sign ^ divisor_sign) : 1'b0;

  assign  dvd_abs      =
          (is_signed && dividend_sign) ?
          (~dividend + 1'b1) : dividend;

  assign  div_abs       =
          (is_signed && divisor_sign) ?
          (~divisor + 1'b1) : divisor;

  wire fire_div_step;
  wire is_last_fix;

  assign is_last_fix     = (counter == 6'h21);

  assign rem_fix         = partial_rem[`DATA_WIDTH] ? {1'b0, div_pos} : 'b0;

  assign fire_div_step   = EN_start || (counter > 6'h0 && counter < 6'h21);

  assign partial_rem_val = { partial_rem[`DATA_WIDTH-1:0],quotient[`DATA_WIDTH-1] };

  assign partial_rem_add = ~partial_rem[`DATA_WIDTH] ? { 1'b1, div_neg } : { 1'b0, div_pos };

  assign next_partial_rem=  EN_start ? 'b0 :
                            is_last_fix ? (partial_rem[`DATA_WIDTH] ? partial_rem + {1'b0, div_pos} :
                                                                      partial_rem) :
                            (partial_rem_val + partial_rem_add);

  assign quotient_val    = { quotient[`DATA_WIDTH-2:0], 1'b0 };

  assign next_quotient   =  EN_start ? dvd_abs :
                            { quotient_val[`DATA_WIDTH-1:1], ~next_partial_rem[`DATA_WIDTH] };


  always @(posedge clock) begin
    if (fire_div_step | is_last_fix)
      partial_rem  <= next_partial_rem;
  end

  always @(posedge clock) begin
    if (fire_div_step)
      quotient     <= next_quotient;
  end

  always @(posedge clock) begin
    if (EN_start)
      div_pos <= div_abs;
  end

  assign neg_div_abs = ~div_abs + 'b1;

  always @(posedge clock) begin
    if (EN_start)
      div_neg <= neg_div_abs;
  end

  assign finish  = counter[5] & counter[1];

  assign final_q = sign_q ? (~quotient + 1'b1) : quotient;

  assign final_r = sign_r ? (~partial_rem[`DATA_WIDTH-1:0] + 1'b1) : partial_rem[`DATA_WIDTH-1:0];

  assign result  = { final_q, final_r };

endmodule
*/
