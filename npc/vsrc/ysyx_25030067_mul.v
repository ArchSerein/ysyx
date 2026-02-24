/*
`include "ysyx_25030067_riscv_param.vh"
module ysyx_25030067_mul (
  input                           clock,
  input                           reset,

  input                           EN_start,
  input                           is_signed,
  input   [`DATA_WIDTH-1:0]       src1,
  input   [`DATA_WIDTH-1:0]       src2,

  input                           EN_result,
  output  [2*`DATA_WIDTH-1:0]     result,
  output                          finish
);

  // two states: idle, busy
  // when EN_start is 1, state transfer from idle to busy
  // enable counter, booth X 4, iterated 16 times
  // 2 beats for read low or high bits
  // then back to idle, and raise valid and hold one cycle
  localparam      UNIT  = 2*`DATA_WIDTH+5;

  reg   [ 4: 0]             counter;
  reg   [2*`DATA_WIDTH+4:0] p;
  reg   [2*`DATA_WIDTH+4:0] m_pos;
  reg   [2*`DATA_WIDTH+4:0] m_neg;
  wire  [ 4: 0]             next_count_val;
  wire  [2*`DATA_WIDTH+4:0] booth_add;
  wire  [2*`DATA_WIDTH+4:0] booth_sum;
  wire  [2*`DATA_WIDTH+4:0] next_p;
  wire  [ 2: 0]             pr;
  wire  [`DATA_WIDTH+1  :0] neg_src1;
  wire  [`DATA_WIDTH+1  :0] src1_ext;
  wire  [`DATA_WIDTH+1  :0] src2_ext;
  wire  [2*`DATA_WIDTH+4:0] m_pos_val;
  wire  [2*`DATA_WIDTH+4:0] m_neg_val;

  // count == 0, multiplier ready
  // count -> [1, 17] multiplier running
  // count == 18, result valid(low)
  // TODO:
  // count == 19, result valid(high),
  // when count == 19 or 0, multiplier is ready
  wire inc_en;
  wire clr_en;

  assign inc_en =
         (counter == 5'd0  && EN_start ) |
         (counter >= 5'd1  && counter <= 5'd17);

  assign clr_en =
         (counter == 5'd18 && EN_result) | reset;

  assign next_count_val =
         (counter + {4'b0, inc_en}) & {5{~clr_en}};

  always @(posedge clock) begin
    counter <= next_count_val;
  end

  assign src1_ext  = is_signed ? {{2{src1[31]}}, src1} : {2'b0, src1};
  assign src2_ext  = is_signed ? {{2{src2[31]}}, src2} : {2'b0, src2};

  assign m_pos_val = {src1_ext, 35'b0};
  always @(posedge clock) begin
    if (EN_start)
      m_pos <= m_pos_val;
  end

  assign neg_src1   = ~src1_ext + 'b1;
  assign m_neg_val  = {neg_src1, 35'b0};
  always @(posedge clock) begin
    if (EN_start)
      m_neg <= m_neg_val;
  end

  wire fire_mul_step;
  assign fire_mul_step = EN_start || (counter > 5'h0 && counter < 5'h12);
  always @(posedge clock) begin
    if (fire_mul_step)
      p <= next_p;
  end

  assign  finish    = counter[4] & counter[1];
  assign  pr        = p[2:0];
  assign  booth_add = {UNIT{(pr == 3'b001)}} & m_pos  |
                      {UNIT{(pr == 3'b010)}} & m_pos  |
                      {UNIT{(pr == 3'b101)}} & m_neg  |
                      {UNIT{(pr == 3'b110)}} & m_neg  |
                      {UNIT{(pr == 3'b011)}} & (m_pos << 1) |
                      {UNIT{(pr == 3'b100)}} & (m_neg << 1);

  assign booth_sum  = p + booth_add;
  assign next_p     = EN_start ? { 34'b0, src2_ext, 1'b0 } :
                                 {{2{booth_sum[2*`DATA_WIDTH+4]}}, booth_sum[2*`DATA_WIDTH+4:2]};
  assign result     = p[2*`DATA_WIDTH:1];
endmodule
*/
