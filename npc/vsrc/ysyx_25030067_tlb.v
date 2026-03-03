`include "autoconf.vh"
`include "ysyx_25030067_riscv_param.vh"

`ifndef CONFIG_TLB_ENTRIES
  `define CONFIG_TLB_ENTRIES 32'h8
`endif

module ysyx_25030067_tlb #(
`ifdef CONFIG_RV64
  parameter VPN_WIDTH   = 27,
  parameter PPN_WIDTH   = 44,
  parameter ASID_WIDTH  = 16,
  parameter LEVEL_WIDTH = 2,
  parameter PAGE_LEVELS = 3,
  parameter VPN_SLICE   = 9
`else
  parameter VPN_WIDTH   = 20,
  parameter PPN_WIDTH   = 22,
  parameter ASID_WIDTH  = 9,
  parameter LEVEL_WIDTH = 1,
  parameter PAGE_LEVELS = 2,
  parameter VPN_SLICE   = 10
`endif
)(
  input                       clock,
  input                       reset,

  // Lookup port (combinational output)
  input                       lookup_valid_i,
  input  [VPN_WIDTH-1:0]      lookup_vpn_i,
  input  [ASID_WIDTH-1:0]     lookup_asid_i,
  output                      lookup_hit_o,
  output [PPN_WIDTH-1:0]      lookup_ppn_o,
  output [6:0]                lookup_perm_o,

  // Write port (TLB refill)
  input                       write_valid_i,
  input  [VPN_WIDTH-1:0]      write_vpn_i,
  input  [ASID_WIDTH-1:0]     write_asid_i,
  input  [PPN_WIDTH-1:0]      write_ppn_i,
  input  [6:0]                write_perm_i,
  input  [LEVEL_WIDTH-1:0]    write_page_level_i,

  // Flush (sfence.vma)
  input                       flush_all_i,
  input                       flush_vma_i,
  input                       flush_asid_valid_i,
  input  [ASID_WIDTH-1:0]     flush_asid_i,
  input                       flush_vpn_valid_i,
  input  [VPN_WIDTH-1:0]      flush_vpn_i
);

  localparam ENTRIES       = `CONFIG_TLB_ENTRIES;
  localparam ENTRIES_WIDTH = $clog2(ENTRIES);
  localparam PERM_WIDTH    = 7;
  // Permission bit indices: {D, A, G, U, X, W, R}
  localparam PERM_G        = 4;
  localparam LAST_LEVEL    = PAGE_LEVELS - 1;

  reg                      entry_valid [0:ENTRIES-1];
  reg  [VPN_WIDTH-1:0]     entry_vpn   [0:ENTRIES-1];
  reg  [PPN_WIDTH-1:0]     entry_ppn   [0:ENTRIES-1];
  reg  [ASID_WIDTH-1:0]    entry_asid  [0:ENTRIES-1];
  reg  [PERM_WIDTH-1:0]    entry_perm  [0:ENTRIES-1];
  reg  [LEVEL_WIDTH-1:0]   entry_level [0:ENTRIES-1];

  reg  [ENTRIES_WIDTH-1:0]  fifo_ptr;
  wire [ENTRIES_WIDTH-1:0]  fifo_ptr_next;

  wire [ENTRIES-1:0]        entry_hit;
  wire [ENTRIES_WIDTH-1:0]  hit_idx;
  wire [PPN_WIDTH-1:0]      composed_ppn [0:ENTRIES-1];
  wire                      _unused_ok;

  assign _unused_ok = &{1'b0, LAST_LEVEL[0]};

  ysyx_25030067_one_hot_to_binary #(
    .ASSOC(ENTRIES),
    .WAY_W(ENTRIES_WIDTH)
  ) u_hit_encoder (
    .tag_cmp_res (entry_hit),
    .way         (hit_idx)
  );

  genvar i;
  generate
    for (i = 0; i < ENTRIES; i = i + 1) begin : g_tlb_entry

      // ASID match: entry ASID matches lookup ASID, or entry is global
      wire asid_match;
      assign asid_match = (entry_asid[i] == lookup_asid_i) || entry_perm[i][PERM_G];

      // VPN match (superpage-aware)
      wire vpn_l0_match;
      wire vpn_l1_match;
      wire vpn_match;
      assign vpn_l0_match = (entry_vpn[i] == lookup_vpn_i);
      assign vpn_l1_match = (entry_vpn[i][VPN_WIDTH-1:VPN_SLICE] ==
                             lookup_vpn_i[VPN_WIDTH-1:VPN_SLICE]);
`ifdef CONFIG_RV64
      wire vpn_l2_match;
      assign vpn_l2_match = (entry_vpn[i][VPN_WIDTH-1:2*VPN_SLICE] ==
                             lookup_vpn_i[VPN_WIDTH-1:2*VPN_SLICE]);
      assign vpn_match = ({1{entry_level[i] == 2'd0}} & vpn_l0_match) |
                         ({1{entry_level[i] == 2'd1}} & vpn_l1_match) |
                         ({1{entry_level[i] == 2'd2}} & vpn_l2_match);
`else
      assign vpn_match = entry_level[i] ? vpn_l1_match : vpn_l0_match;
`endif

      assign entry_hit[i] = entry_valid[i] && asid_match && vpn_match && lookup_valid_i;

      // Composed PPN for this entry
`ifdef CONFIG_RV64
      assign composed_ppn[i] =
        ({PPN_WIDTH{entry_level[i] == 2'd0}} & entry_ppn[i]) |
        ({PPN_WIDTH{entry_level[i] == 2'd1}} &
          {entry_ppn[i][PPN_WIDTH-1:VPN_SLICE], lookup_vpn_i[VPN_SLICE-1:0]}) |
        ({PPN_WIDTH{entry_level[i] == 2'd2}} &
          {entry_ppn[i][PPN_WIDTH-1:2*VPN_SLICE], lookup_vpn_i[2*VPN_SLICE-1:0]});
`else
      assign composed_ppn[i] = entry_level[i] ?
        {entry_ppn[i][PPN_WIDTH-1:VPN_SLICE], lookup_vpn_i[VPN_SLICE-1:0]} :
        entry_ppn[i];
`endif

      // Flush logic
      wire flush_asid_ok;
      wire flush_vpn_ok;
      wire should_flush;

      // ASID-based flush skips global entries
      assign flush_asid_ok = !flush_asid_valid_i ||
                             (entry_asid[i] == flush_asid_i && !entry_perm[i][PERM_G]);

      // VPN-based flush considers superpage level
      wire flush_vpn_l0;
      wire flush_vpn_l1;
      assign flush_vpn_l0 = (entry_vpn[i] == flush_vpn_i);
      assign flush_vpn_l1 = (entry_vpn[i][VPN_WIDTH-1:VPN_SLICE] ==
                             flush_vpn_i[VPN_WIDTH-1:VPN_SLICE]);
`ifdef CONFIG_RV64
      wire flush_vpn_l2;
      assign flush_vpn_l2 = (entry_vpn[i][VPN_WIDTH-1:2*VPN_SLICE] ==
                             flush_vpn_i[VPN_WIDTH-1:2*VPN_SLICE]);
      assign flush_vpn_ok = !flush_vpn_valid_i ||
        (({1{entry_level[i] == 2'd0}} & flush_vpn_l0) |
         ({1{entry_level[i] == 2'd1}} & flush_vpn_l1) |
         ({1{entry_level[i] == 2'd2}} & flush_vpn_l2));
`else
      assign flush_vpn_ok = !flush_vpn_valid_i ||
        (entry_level[i] ? flush_vpn_l1 : flush_vpn_l0);
`endif

      assign should_flush = flush_all_i ||
                            (flush_vma_i && entry_valid[i] && flush_asid_ok && flush_vpn_ok);

      // Entry valid (control register - needs reset)
      always @(posedge clock) begin
        if (reset || should_flush) begin
          entry_valid[i] <= 1'b0;
        end else if (write_valid_i && (fifo_ptr == i)) begin
          entry_valid[i] <= 1'b1;
        end
      end

      // Entry data (data registers - no reset)
      always @(posedge clock) begin
        if (write_valid_i && (fifo_ptr == i)) begin
          entry_vpn[i]   <= write_vpn_i;
        end
      end

      always @(posedge clock) begin
        if (write_valid_i && (fifo_ptr == i)) begin
          entry_ppn[i]   <= write_ppn_i;
        end
      end

      always @(posedge clock) begin
        if (write_valid_i && (fifo_ptr == i)) begin
          entry_asid[i]  <= write_asid_i;
        end
      end
      always @(posedge clock) begin
        if (write_valid_i && (fifo_ptr == i)) begin
          entry_perm[i]  <= write_perm_i;
        end
      end
      always @(posedge clock) begin
        if (write_valid_i && (fifo_ptr == i)) begin
          entry_level[i] <= write_page_level_i;
        end
      end
    end
  endgenerate

  // Outputs
  assign lookup_hit_o  = |entry_hit;
  assign lookup_ppn_o  = composed_ppn[hit_idx];
  assign lookup_perm_o = entry_perm[hit_idx];

  // FIFO replacement pointer (control register - needs reset)
  assign fifo_ptr_next = fifo_ptr + 1'b1;

  always @(posedge clock) begin
    if (reset) begin
      fifo_ptr <= {ENTRIES_WIDTH{1'b0}};
    end else if (write_valid_i) begin
      fifo_ptr <= fifo_ptr_next;
    end
  end

endmodule
