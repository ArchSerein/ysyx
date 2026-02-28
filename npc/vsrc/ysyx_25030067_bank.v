module ysyx_25030067_bank #(
  parameter DATA_WIDTH = 32,
  parameter DEPTH = 16,
  parameter ADDR_WIDTH = $clog2(DEPTH),
  parameter SLICE_WIDTH = 32
)(
  input                    clock,
  input                    reset,
  input                    wr_en,
  input   [ADDR_WIDTH-1:0] addr,
  input   [DATA_WIDTH-1:0] wr_data,
  output  [DATA_WIDTH-1:0] rd_data
);

  // Split one wide memory into multiple narrower slices. This keeps interface
  // and behavior unchanged while reducing width-related timing/power pressure.
  localparam BANK_NUM = (DATA_WIDTH + SLICE_WIDTH - 1) / SLICE_WIDTH;
  wire _unused_reset = reset;

  genvar i;
  generate
    for (i = 0; i < BANK_NUM; i = i + 1) begin : g_mem_bank
      localparam integer LSB = i * SLICE_WIDTH;
      localparam integer BANK_WIDTH = (LSB + SLICE_WIDTH <= DATA_WIDTH) ?
                                      SLICE_WIDTH : (DATA_WIDTH - LSB);

      reg [BANK_WIDTH-1:0] mem[0:DEPTH-1];

      assign rd_data[LSB +: BANK_WIDTH] = mem[addr];

      always @(posedge clock) begin
        if (wr_en) begin
          mem[addr] <= wr_data[LSB +: BANK_WIDTH];
        end
      end
    end
  endgenerate
endmodule
