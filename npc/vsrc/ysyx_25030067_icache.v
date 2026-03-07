`include "autoconf.vh"
`include "ysyx_25030067_riscv_param.vh"

module ysyx_25030067_icache #(
  parameter TAG_WIDTH  = `DATA_WIDTH - `CONFIG_ICACHE_BLOCKS_WIDTH -
                         `CONFIG_ICACHE_SETS_WIDTH - 2,
  parameter LINE_WIDTH = `DATA_WIDTH * `CONFIG_ICACHE_BLOCKS,
  parameter WAY_WIDTH  = `CONFIG_ICACHE_ASSOCIATIVITYS_WIDTH
) (
  input                   clock,
  input                   reset,

  input                   lookup_valid_i,
  input  [31:0]           vaddr_i,
  input  [TAG_WIDTH-1:0]  ptag_i,

  input                   fill_valid_i,
  input  [`DATA_WIDTH-1:0] fill_data_i,
  input                   fill_last_i,

  input                   invalidate_i,
  input                   flush_pending_i,

  output                  hit_o,
  output [`DATA_WIDTH-1:0] rdata_o
);

  localparam SETS          = `CONFIG_ICACHE_SETS;
  localparam SETS_WIDTH    = `CONFIG_ICACHE_SETS_WIDTH;
  localparam BLOCKS_WIDTH  = `CONFIG_ICACHE_BLOCKS_WIDTH;
  localparam WAYS          = `CONFIG_ICACHE_ASSOCIATIVITYS;

  wire [SETS_WIDTH-1:0]    lookup_index;
  wire [BLOCKS_WIDTH-1:0]  lookup_offset;
  wire [WAYS-1:0]          tag_cmp_res;
  wire [WAY_WIDTH-1:0]     miss_way;
  wire [SETS_WIDTH-1:0]    fill_index;
  wire [SETS_WIDTH-1:0]    bank_addr;
  wire [LINE_WIDTH-1:0]    line_rd [0:WAYS-1];
  wire [TAG_WIDTH-1:0]     tag_rd [0:WAYS-1];
  wire [WAY_WIDTH-1:0]     hit_way;
  wire [LINE_WIDTH-1:0]    hit_line;
  wire [LINE_WIDTH-1:0]    fill_word_mask;
  wire [LINE_WIDTH-1:0]    fill_word_data;
  wire [LINE_WIDTH-1:0]    fill_line_next;
  wire                     start_fill;
  wire                     commit_valid;
  reg  [WAYS-1:0]          valid_array [0:SETS-1];
  reg  [WAY_WIDTH-1:0]     fifo_ptr [0:SETS-1];
  reg  [SETS_WIDTH-1:0]    miss_index;
  reg  [TAG_WIDTH-1:0]     miss_ptag;
  reg  [WAY_WIDTH-1:0]     fill_way;
  reg  [BLOCKS_WIDTH-1:0]  fill_ptr;
  reg                      fill_active;
  reg  [LINE_WIDTH-1:0]    fill_buffer;

  assign lookup_index = vaddr_i[`CONFIG_ICACHE_BLOCKS_WIDTH+`CONFIG_ICACHE_SETS_WIDTH+1:
                                `CONFIG_ICACHE_BLOCKS_WIDTH+2];
  assign lookup_offset = vaddr_i[`CONFIG_ICACHE_BLOCKS_WIDTH+1:2];
  assign miss_way = fifo_ptr[lookup_index];
  assign fill_index = miss_index;
  assign bank_addr = fill_valid_i ? fill_index : lookup_index;
  assign commit_valid = fill_valid_i && fill_last_i && !invalidate_i && !flush_pending_i;

  generate
    genvar m;
    for (m = 0; m < WAYS; m = m + 1) begin : g_icache_way
      localparam [WAY_WIDTH-1:0] WAY_ID = m[WAY_WIDTH-1:0];

      ysyx_25030067_bank #(
        .DATA_WIDTH (TAG_WIDTH),
        .DEPTH      (SETS)
      ) u_tag_bank (
        .clock   (clock),
        .reset   (reset),
        .wr_en   (commit_valid && (fill_way == WAY_ID)),
        .addr    (bank_addr),
        .wr_data (miss_ptag),
        .rd_data (tag_rd[m])
      );

      ysyx_25030067_bank #(
        .DATA_WIDTH (LINE_WIDTH),
        .DEPTH      (SETS)
      ) u_line_bank (
        .clock   (clock),
        .reset   (reset),
        .wr_en   (commit_valid && (fill_way == WAY_ID)),
        .addr    (bank_addr),
        .wr_data (fill_line_next),
        .rd_data (line_rd[m])
      );

      assign tag_cmp_res[m] = lookup_valid_i &&
                              valid_array[lookup_index][m] &&
                              (tag_rd[m] == ptag_i);
    end
  endgenerate

  ysyx_25030067_one_hot_to_binary #(
    .ASSOC (`CONFIG_ICACHE_ASSOCIATIVITYS),
    .WAY_W (WAY_WIDTH)
  ) u_hit_way (
    .tag_cmp_res (tag_cmp_res),
    .way         (hit_way)
  );
  assign hit_line = line_rd[hit_way];

  assign fill_word_mask = {{(LINE_WIDTH-`DATA_WIDTH){1'b0}}, {`DATA_WIDTH{1'b1}}}
                          << (`DATA_WIDTH * fill_ptr);
  assign fill_word_data = {{(LINE_WIDTH-`DATA_WIDTH){1'b0}}, fill_data_i}
                          << (`DATA_WIDTH * fill_ptr);
  assign fill_line_next = (fill_buffer & ~fill_word_mask) | fill_word_data;
  assign start_fill = lookup_valid_i && !fill_active && !hit_o;

  assign hit_o = |tag_cmp_res;
  assign rdata_o = hit_line[`DATA_WIDTH * lookup_offset +: `DATA_WIDTH];

  always @(posedge clock) begin
    if (start_fill) begin
      miss_index <= lookup_index;
    end
  end

  always @(posedge clock) begin
    if (start_fill) begin
      miss_ptag <= ptag_i;
    end
  end

  always @(posedge clock) begin
    if (start_fill) begin
      fill_way <= miss_way;
    end
  end

  always @(posedge clock) begin
    if (fill_valid_i) begin
      fill_buffer[`DATA_WIDTH * fill_ptr +: `DATA_WIDTH] <= fill_data_i;
    end
  end

  always @(posedge clock) begin
    if (reset || invalidate_i) begin
      fill_ptr <= {BLOCKS_WIDTH{1'b0}};
    end else if (start_fill || (fill_valid_i && fill_last_i)) begin
      fill_ptr <= {BLOCKS_WIDTH{1'b0}};
    end else if (fill_valid_i) begin
      fill_ptr <= fill_ptr + 1'b1;
    end
  end

  always @(posedge clock) begin
    if (reset || invalidate_i) begin
      fill_active <= 1'b0;
    end else if (start_fill) begin
      fill_active <= 1'b1;
    end else if ((fill_valid_i && fill_last_i)) begin
      fill_active <= 1'b0;
    end
  end

  generate
    genvar s;
    for (s = 0; s < SETS; s = s + 1) begin : g_icache_state
      always @(posedge clock) begin
        if (reset || invalidate_i) begin
          valid_array[s] <= {WAYS{1'b0}};
        end else if (commit_valid && (fill_index == s[SETS_WIDTH-1:0])) begin
          valid_array[s][fill_way] <= 1'b1;
        end
      end

      always @(posedge clock) begin
        if (reset || invalidate_i) begin
          fifo_ptr[s] <= {WAY_WIDTH{1'b0}};
        end else if (commit_valid && (fill_index == s[SETS_WIDTH-1:0])) begin
          fifo_ptr[s] <= fifo_ptr[s] + 1'b1;
        end
      end
    end
  endgenerate

endmodule
