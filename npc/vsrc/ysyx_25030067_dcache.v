`include "autoconf.vh"
`include "ysyx_25030067_riscv_param.vh"

module ysyx_25030067_dcache #(
  parameter TAG_WIDTH  = `DATA_WIDTH - `CONFIG_DCACHE_BLOCKS_WIDTH -
                         `CONFIG_DCACHE_SETS_WIDTH - 2,
  parameter LINE_WIDTH = `DATA_WIDTH * `CONFIG_DCACHE_BLOCKS,
  parameter WAY_WIDTH  = `CONFIG_DCACHE_ASSOCIATIVITYS_WIDTH
) (
  input                    clock,
  input                    reset,

  input                    lookup_valid_i,
  input  [31:0]            vaddr_i,
  input  [TAG_WIDTH-1:0]   ptag_i,
  input                    is_write_i,

  input  [`DATA_WIDTH-1:0] wdata_i,
  input  [3:0]             wstrb_i,

  input                    fill_valid_i,
  input  [`DATA_WIDTH-1:0] fill_data_i,
  input                    fill_last_i,

  output [TAG_WIDTH-1:0]   wb_tag_o,
  output [LINE_WIDTH-1:0]  wb_data_o,

  input                    invalidate_i,
  input                    probe_valid_i,
  input  [`CONFIG_DCACHE_SETS_WIDTH-1:0]  probe_index_i,
  input  [WAY_WIDTH-1:0]   probe_way_i,
  input                    probe_invalidate_i,

  output                   hit_o,
  output [`DATA_WIDTH-1:0] rdata_o,
  output                   line_dirty_o,
  output [WAY_WIDTH-1:0]   miss_way_o
);

  localparam SETS          = `CONFIG_DCACHE_SETS;
  localparam SETS_WIDTH    = `CONFIG_DCACHE_SETS_WIDTH;
  localparam BLOCKS_WIDTH  = `CONFIG_DCACHE_BLOCKS_WIDTH;
  localparam WAYS          = `CONFIG_DCACHE_ASSOCIATIVITYS;

  wire [SETS_WIDTH-1:0]    lookup_index;
  wire [BLOCKS_WIDTH-1:0]  lookup_offset;
  wire [SETS_WIDTH-1:0]    fill_index;
  wire [WAY_WIDTH-1:0]     fill_way_sel;
  wire [WAY_WIDTH-1:0]     miss_way_cur;
  wire [SETS_WIDTH-1:0]    bank_addr;
  wire [WAYS-1:0]          tag_cmp_res;
  wire [WAY_WIDTH-1:0]     hit_way;
  wire [TAG_WIDTH-1:0]     tag_rd [0:WAYS-1];
  wire [LINE_WIDTH-1:0]    line_rd [0:WAYS-1];
  reg  [WAYS-1:0]          valid_array [0:SETS-1];
  reg  [WAYS-1:0]          dirty_array [0:SETS-1];
  reg  [WAY_WIDTH-1:0]     fifo_ptr [0:SETS-1];
  wire [LINE_WIDTH-1:0]    hit_line;
  wire [LINE_WIDTH-1:0]    fill_line;
  wire [TAG_WIDTH-1:0]     victim_tag_cur;
  wire [LINE_WIDTH-1:0]    victim_line_cur;
  wire [TAG_WIDTH-1:0]     probe_tag_cur;
  wire [LINE_WIDTH-1:0]    probe_line_cur;
  reg  [SETS_WIDTH-1:0]    miss_index;
  reg  [BLOCKS_WIDTH-1:0]  miss_offset;
  reg  [TAG_WIDTH-1:0]     miss_ptag;
  reg  [WAY_WIDTH-1:0]     miss_way_reg;
  reg  [TAG_WIDTH-1:0]     wb_tag_reg;
  reg  [LINE_WIDTH-1:0]    wb_line_reg;
  reg                      wb_dirty_reg;
  reg                      miss_is_write;
  reg  [`DATA_WIDTH-1:0]   miss_wdata;
  reg  [3:0]               miss_wstrb;
  reg  [BLOCKS_WIDTH-1:0]  fill_ptr;
  reg                      fill_active;
  wire                     write_hit;
  wire                     start_fill;
  wire [LINE_WIDTH-1:0]    write_hit_mask;
  wire [LINE_WIDTH-1:0]    write_hit_data;
  wire [LINE_WIDTH-1:0]    write_hit_line_next;
  wire [`DATA_WIDTH-1:0]   write_hit_word;
  wire [`DATA_WIDTH-1:0]   write_hit_word_old;
  wire [`DATA_WIDTH-1:0]   write_hit_byte_mask;
  wire [LINE_WIDTH-1:0]    fill_word_mask;
  wire [LINE_WIDTH-1:0]    fill_word_data;
  wire [LINE_WIDTH-1:0]    fill_line_next;
  wire [`DATA_WIDTH-1:0]   fill_word_next;
  wire [`DATA_WIDTH-1:0]   fill_word_old;
  wire [`DATA_WIDTH-1:0]   fill_byte_mask;
  wire                     _unused_ok;

  assign lookup_index = vaddr_i[`CONFIG_DCACHE_BLOCKS_WIDTH+`CONFIG_DCACHE_SETS_WIDTH+1:
                                `CONFIG_DCACHE_BLOCKS_WIDTH+2];
  assign lookup_offset = vaddr_i[`CONFIG_DCACHE_BLOCKS_WIDTH+1:2];
  assign miss_way_cur = fifo_ptr[lookup_index];
  assign fill_index = miss_index;
  assign fill_way_sel = fill_active ? miss_way_reg : miss_way_cur;
  assign bank_addr = ({SETS_WIDTH{fill_valid_i}} & fill_index) |
                     ({SETS_WIDTH{!fill_valid_i && probe_valid_i}} & probe_index_i) |
                     ({SETS_WIDTH{!fill_valid_i && !probe_valid_i}} & lookup_index);
  assign _unused_ok = &{1'b0, vaddr_i[31:`CONFIG_DCACHE_BLOCKS_WIDTH+`CONFIG_DCACHE_SETS_WIDTH+2], vaddr_i[1:0]};

  generate
    genvar m;
    for (m = 0; m < WAYS; m = m + 1) begin : g_dcache_way
      localparam [WAY_WIDTH-1:0] WAY_ID = m[WAY_WIDTH-1:0];
      wire line_wr_en;
      wire [LINE_WIDTH-1:0] line_wr_data;

      assign line_wr_en = (fill_valid_i && (miss_way_reg == WAY_ID)) ||
                          (write_hit && (hit_way == WAY_ID));
      assign line_wr_data = fill_valid_i ? fill_line_next : write_hit_line_next;

      ysyx_25030067_bank #(
        .DATA_WIDTH (TAG_WIDTH),
        .DEPTH      (SETS)
      ) u_tag_bank (
        .clock   (clock),
        .reset   (reset),
        .wr_en   (fill_valid_i && fill_last_i && (miss_way_reg == WAY_ID)),
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
        .wr_en   (line_wr_en),
        .addr    (bank_addr),
        .wr_data (line_wr_data),
        .rd_data (line_rd[m])
      );

      assign tag_cmp_res[m] = lookup_valid_i &&
                              !fill_active &&
                              valid_array[lookup_index][m] &&
                              (tag_rd[m] == ptag_i);
    end
  endgenerate

  ysyx_25030067_one_hot_to_binary #(
    .ASSOC (`CONFIG_DCACHE_ASSOCIATIVITYS),
    .WAY_W (WAY_WIDTH)
  ) u_hit_way (
    .tag_cmp_res (tag_cmp_res),
    .way         (hit_way)
  );

  assign hit_line        = line_rd[hit_way];
  assign fill_line       = line_rd[miss_way_reg];
  assign victim_tag_cur  = tag_rd[miss_way_cur];
  assign victim_line_cur = line_rd[miss_way_cur];
  assign probe_tag_cur   = tag_rd[probe_way_i];
  assign probe_line_cur  = line_rd[probe_way_i];

  assign hit_o = |tag_cmp_res;
  assign write_hit = hit_o && lookup_valid_i && is_write_i;
  assign start_fill = lookup_valid_i && !fill_active && !hit_o;
  assign miss_way_o = fill_way_sel;
  assign line_dirty_o = ({1{probe_valid_i}} &
                         (valid_array[probe_index_i][probe_way_i] &&
                          dirty_array[probe_index_i][probe_way_i])) |
                        ({1{!probe_valid_i && fill_active}} & wb_dirty_reg) |
                        ({1{!probe_valid_i && !fill_active}} &
                         (valid_array[lookup_index][miss_way_cur] &&
                          dirty_array[lookup_index][miss_way_cur]));
  assign wb_tag_o = ({TAG_WIDTH{probe_valid_i}} & probe_tag_cur) |
                    ({TAG_WIDTH{!probe_valid_i && fill_active}} & wb_tag_reg) |
                    ({TAG_WIDTH{!probe_valid_i && !fill_active}} & victim_tag_cur);
  assign wb_data_o = ({LINE_WIDTH{probe_valid_i}} & probe_line_cur) |
                     ({LINE_WIDTH{!probe_valid_i && fill_active}} & wb_line_reg) |
                     ({LINE_WIDTH{!probe_valid_i && !fill_active}} & victim_line_cur);
  assign rdata_o = hit_line[`DATA_WIDTH * lookup_offset +: `DATA_WIDTH];

  assign write_hit_word_old = hit_line[`DATA_WIDTH * lookup_offset +: `DATA_WIDTH];
  assign write_hit_byte_mask = {{8{wstrb_i[3]}}, {8{wstrb_i[2]}},
                                {8{wstrb_i[1]}}, {8{wstrb_i[0]}}};
  assign write_hit_word = (write_hit_word_old & ~write_hit_byte_mask) |
                          (wdata_i & write_hit_byte_mask);
  assign write_hit_mask = {{(LINE_WIDTH-`DATA_WIDTH){1'b0}}, {`DATA_WIDTH{1'b1}}}
                          << (`DATA_WIDTH * lookup_offset);
  assign write_hit_data = {{(LINE_WIDTH-`DATA_WIDTH){1'b0}}, write_hit_word}
                          << (`DATA_WIDTH * lookup_offset);
  assign write_hit_line_next = (hit_line & ~write_hit_mask) | write_hit_data;

  assign fill_word_old = fill_data_i;
  assign fill_byte_mask = {{8{miss_wstrb[3]}}, {8{miss_wstrb[2]}},
                           {8{miss_wstrb[1]}}, {8{miss_wstrb[0]}}};
  assign fill_word_next = ({`DATA_WIDTH{miss_is_write && (fill_ptr == miss_offset)}} &
                           ((fill_word_old & ~fill_byte_mask) |
                            (miss_wdata & fill_byte_mask))) |
                          ({`DATA_WIDTH{!(miss_is_write && (fill_ptr == miss_offset))}} &
                           fill_data_i);
  assign fill_word_mask = {{(LINE_WIDTH-`DATA_WIDTH){1'b0}}, {`DATA_WIDTH{1'b1}}}
                          << (`DATA_WIDTH * fill_ptr);
  assign fill_word_data = {{(LINE_WIDTH-`DATA_WIDTH){1'b0}}, fill_word_next}
                          << (`DATA_WIDTH * fill_ptr);
  assign fill_line_next = (fill_line & ~fill_word_mask) | fill_word_data;

  always @(posedge clock) begin
    if (start_fill) begin
      miss_index <= lookup_index;
    end
  end

  always @(posedge clock) begin
    if (start_fill) begin
      miss_offset <= lookup_offset;
    end
  end

  always @(posedge clock) begin
    if (start_fill) begin
      miss_ptag <= ptag_i;
    end
  end

  always @(posedge clock) begin
    if (start_fill) begin
      miss_way_reg <= miss_way_cur;
    end
  end

  always @(posedge clock) begin
    if (start_fill) begin
      wb_tag_reg <= victim_tag_cur;
    end
  end

  always @(posedge clock) begin
    if (start_fill) begin
      wb_line_reg <= victim_line_cur;
    end
  end

  always @(posedge clock) begin
    if (reset || invalidate_i) begin
      wb_dirty_reg <= 1'b0;
    end else if (start_fill) begin
      wb_dirty_reg <= valid_array[lookup_index][miss_way_cur] &&
                      dirty_array[lookup_index][miss_way_cur];
    end
  end

  always @(posedge clock) begin
    if (start_fill) begin
      miss_is_write <= is_write_i;
    end
  end

  always @(posedge clock) begin
    if (start_fill) begin
      miss_wdata <= wdata_i;
    end
  end

  always @(posedge clock) begin
    if (start_fill) begin
      miss_wstrb <= wstrb_i;
    end
  end

  always @(posedge clock) begin
    if (reset || invalidate_i) begin
      fill_ptr <= {BLOCKS_WIDTH{1'b0}};
    end else if (start_fill || fill_last_i) begin
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
    end else if (fill_valid_i && fill_last_i) begin
      fill_active <= 1'b0;
    end
  end

  generate
    genvar s;
    for (s = 0; s < SETS; s = s + 1) begin : g_dcache_state
      always @(posedge clock) begin
        if (reset || invalidate_i) begin
          valid_array[s] <= {WAYS{1'b0}};
        end else if (probe_invalidate_i && (probe_index_i == s[SETS_WIDTH-1:0])) begin
          valid_array[s][probe_way_i] <= 1'b0;
        end else if (fill_valid_i && fill_last_i && (fill_index == s[SETS_WIDTH-1:0])) begin
          valid_array[s][miss_way_reg] <= 1'b1;
        end
      end

      always @(posedge clock) begin
        if (reset || invalidate_i) begin
          dirty_array[s] <= {WAYS{1'b0}};
        end else if (probe_invalidate_i && (probe_index_i == s[SETS_WIDTH-1:0])) begin
          dirty_array[s][probe_way_i] <= 1'b0;
        end else if (fill_valid_i && fill_last_i && (fill_index == s[SETS_WIDTH-1:0])) begin
          dirty_array[s][miss_way_reg] <= miss_is_write;
        end else if (write_hit && (lookup_index == s[SETS_WIDTH-1:0])) begin
          dirty_array[s][hit_way] <= 1'b1;
        end
      end

      always @(posedge clock) begin
        if (reset || invalidate_i) begin
          fifo_ptr[s] <= {WAY_WIDTH{1'b0}};
        end else if (fill_valid_i && fill_last_i && (fill_index == s[SETS_WIDTH-1:0])) begin
          fifo_ptr[s] <= fifo_ptr[s] + 1'b1;
        end
      end
    end
  endgenerate

endmodule
