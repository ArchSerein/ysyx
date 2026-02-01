`include "./include/generated/autoconf.vh"
module ysyx_25030067_axi (
    input                           clock,
    input                           reset,
    input                           io_interrupt,

    input                           io_master_awready,
    output                          io_master_awvalid,
    output [31:0]                   io_master_awaddr,
    output [ 3:0]                   io_master_awid,
    output [ 7:0]                   io_master_awlen,
    output [ 2:0]                   io_master_awsize,
    output [ 1:0]                   io_master_awburst,

    input                           io_master_wready,
    output                          io_master_wvalid,
    output [31:0]                   io_master_wdata,
    output [ 3:0]                   io_master_wstrb,
    output                          io_master_wlast,

    output                          io_master_bready,
    input                           io_master_bvalid,
    input [ 1:0]                    io_master_bresp,
    input [ 3:0]                    io_master_bid,

    input                           io_master_arready,
    output                          io_master_arvalid,
    output [31:0]                   io_master_araddr,
    output [ 3:0]                   io_master_arid,
    output [ 7:0]                   io_master_arlen,
    output [ 2:0]                   io_master_arsize,
    output [ 1:0]                   io_master_arburst,

    output                          io_master_rready,
    input                           io_master_rvalid,
    input [31:0]                    io_master_rdata,
    input [ 1:0]                    io_master_rresp,
    input                           io_master_rlast,
    input [ 3:0]                    io_master_rid,

    output                          io_slave_awready,
    input                           io_slave_awvalid,
    input [31:0]                    io_slave_awaddr,
    input [ 3:0]                    io_slave_awid,
    input [ 7:0]                    io_slave_awlen,
    input [ 2:0]                    io_slave_awsize,
    input [ 1:0]                    io_slave_awburst,

    output                          io_slave_wready,
    input                           io_slave_wvalid,
    input [31:0]                    io_slave_wdata,
    input [ 3:0]                    io_slave_wstrb,
    input                           io_slave_wlast,

    input                           io_slave_bready,
    output                          io_slave_bvalid,
    output [ 1:0]                   io_slave_bresp,
    output [ 3:0]                   io_slave_bid,

    output                          io_slave_arready,
    input                           io_slave_arvalid,
    input [31:0]                    io_slave_araddr,
    input [ 3:0]                    io_slave_arid,
    input [ 7:0]                    io_slave_arlen,
    input [ 2:0]                    io_slave_arsize,
    input [ 1:0]                    io_slave_arburst,

    input                           io_slave_rready,
    output                          io_slave_rvalid,
    output [31:0]                   io_slave_rdata,
    output [ 1:0]                   io_slave_rresp,
    output                          io_slave_rlast,
    output [ 3:0]                   io_slave_rid
);

    wire                      icache_arvalid;
    wire      [31:0]          icache_araddr;
    wire                      icache_arready;
    wire      [ 2:0]          icache_arsize;
    wire      [ 1:0]          icache_arburst;
    wire      [ 7:0]          icache_arlen;

    wire                      icache_rlast;
    wire                      icache_rready;
    wire                      icache_rvalid;
    wire      [31:0]          icache_rdata;
    wire      [ 1:0]          icache_rresp;

    wire                      exu_arvalid;
    wire      [ 2:0]          exu_arsize;
    wire      [31:0]          exu_araddr;
    wire                      exu_arready;

    wire                      lsu_rready;
    wire                      lsu_rvalid;
    wire      [31:0]          lsu_rdata;
    wire      [ 1:0]          lsu_rresp;

    wire                      exu_awvalid;
    wire      [31:0]          exu_awaddr;
    wire                      exu_awready;

    wire                      exu_wvalid;
    wire      [31:0]          exu_wdata;
    wire      [ 3:0]          exu_wstrb;
    wire                      exu_wready;

    wire                      lsu_bvalid;
    wire      [ 1:0]          lsu_bresp;
    wire                      lsu_bready;

    ysyx_25030067_core core_module (
        .clock                      (clock),
        .reset                      (reset),

        .icache_arvalid             (icache_arvalid),
        .icache_araddr              (icache_araddr),
        .icache_arready             (icache_arready),
        .icache_arsize              (icache_arsize),
        .icache_arburst             (icache_arburst),
        .icache_arlen               (icache_arlen),

        .icache_rlast               (icache_rlast),
        .icache_rready              (icache_rready),
        .icache_rvalid              (icache_rvalid),
        .icache_rdata               (icache_rdata),
        .icache_rresp               (icache_rresp),

        .exu_arvalid                (exu_arvalid),
        .exu_araddr                 (exu_araddr),
        .exu_arready                (exu_arready),
        .exu_arsize                 (exu_arsize),

        .lsu_rready                 (lsu_rready),
        .lsu_rvalid                 (lsu_rvalid),
        .lsu_rdata                  (lsu_rdata),
        .lsu_rresp                  (lsu_rresp),

        .exu_awvalid                (exu_awvalid),
        .exu_awaddr                 (exu_awaddr),
        .exu_awready                (exu_awready),

        .exu_wvalid                 (exu_wvalid),
        .exu_wdata                  (exu_wdata),
        .exu_wstrb                  (exu_wstrb),
        .exu_wready                 (exu_wready),

        .lsu_bvalid                 (lsu_bvalid),
        .lsu_bresp                  (lsu_bresp),
        .lsu_bready                 (lsu_bready)
    );

    reg  clint_select;
    wire is_clint;
    wire clint_arvalid;
    wire clint_arready;
    wire clint_rvalid;
    wire clint_rready;
    wire [31:0] clint_rdata;
    ysyx_25030067_clint ysyx_25030067_clint_module (
        .clock            (clock),
        .reset            (reset),

        .arvalid_i        (clint_arvalid),
        .arready_o        (clint_arready),
        .araddr_i         (exu_araddr),

        .rvalid_o         (clint_rvalid),
        .rready_i         (clint_rready),
        .rdata_o          (clint_rdata)
    );

    reg   [ 1:0]        grant;
    wire  [ 1:0]        rreq;
    wire  [ 1:0]        grant_q;
    ysyx_25030067_arbiter #(
      .MASTER(2)
    ) ysyx_25030067_arbiter_module (
      .clock          (clock),
      .reset          (reset),
      .rreq_i         (rreq),
      .grant_o        (grant_q)
    );
    assign rreq = {icache_arvalid, exu_arvalid};
    reg   idle;
    reg   read_busy;
    reg   write_busy;
    wire  acquire_arbiter;
    wire  release_arbiter;
    always @(posedge clock) begin
      if (idle) begin
        read_busy <= 1'b0;
      end else if (acquire_arbiter) begin
        read_busy <= 1'b1;
      end
    end
    always @(posedge clock) begin
      if (release_arbiter) begin
        idle <= 1'b1;
      end else if (idle && grant_q != 0) begin
        idle <= 1'b0;
      end
    end
    always @(posedge clock) begin
      if (idle) begin
        grant <= grant_q;
      end
    end
    assign release_arbiter = reset || (io_master_rvalid && io_master_rready && io_master_rlast) || (clint_select && clint_rvalid && lsu_rready);
    assign acquire_arbiter =  grant[1] && icache_arvalid && icache_arready ||
                              (grant[0] || is_clint) && exu_arvalid && exu_arready;

    always @(posedge clock) begin
      if (is_clint) begin
        clint_select <= 1'b1;
      end else if (clint_rvalid && lsu_rready) begin
        clint_select <= 1'b0;
      end
    end
    assign is_clint = exu_araddr[31:16] == 16'h0200 && exu_arvalid;
    assign clint_arvalid = exu_arvalid && is_clint && !read_busy;
    assign clint_rready = lsu_rready;

    always @(posedge clock) begin
      if (reset || (io_master_bvalid && io_master_bready)) begin
        write_busy <= 1'b0;
      end else if (exu_awvalid && exu_awready) begin
        write_busy <= 1'b1;
      end
    end

    assign io_master_awvalid = exu_awvalid && !write_busy;
    assign io_master_awaddr = exu_awaddr;
    assign io_master_awid = 4'b0000;
    assign io_master_awlen = 8'b00000000;
    assign io_master_awsize = 3'b000;
    assign io_master_awburst = 2'b00;
    assign exu_awready = io_master_awready && !write_busy;

    assign io_master_wvalid = exu_wvalid && !write_busy;
    assign exu_wready = io_master_wready && !write_busy;
    assign io_master_wdata = exu_wdata;
    assign io_master_wstrb = exu_wstrb;
    assign io_master_wlast = 1'b1;

    assign io_master_bready = lsu_bready;
    assign lsu_bvalid = io_master_bvalid;
    assign lsu_bresp = io_master_bresp;

    assign io_master_arvalid = (grant[1] && icache_arvalid && !read_busy) || (exu_arvalid && !is_clint && grant[0] && !read_busy);
    assign io_master_araddr = ({32{grant[1]}} & icache_araddr) | ({32{grant[0]}} & exu_araddr);
    assign io_master_arid = 4'b0000;
    assign io_master_arlen = grant[1] ? icache_arlen : 8'h0;
    assign io_master_arsize = ({3{grant[1]}} & icache_arsize) | ({3{grant[0]}} & exu_arsize);
    assign io_master_arburst = grant[1] ? icache_arburst : 2'b00;
    assign exu_arready = grant[0] && !read_busy && io_master_arready;

    assign io_master_rready = (grant[1] && icache_rready) | (grant[0] && lsu_rready);

    assign icache_arready = io_master_arready && grant[1] && !read_busy;
    assign icache_rvalid = io_master_rvalid & grant[1];
    assign icache_rdata = io_master_rdata;
    assign icache_rresp = io_master_rresp;
    assign icache_rlast = io_master_rlast;

    assign lsu_rvalid = clint_select ? clint_rvalid : io_master_rvalid & grant[0];
    assign lsu_rdata = clint_select ? clint_rdata : io_master_rdata;
    assign lsu_rresp = clint_select ? 2'b00 : io_master_rresp;

    // unused signals
    assign io_slave_awready = 1'b0;
    assign io_slave_wready = 1'b0;
    assign io_slave_bvalid = 1'b0;
    assign io_slave_arready = 1'b0;
    assign io_slave_rvalid = 1'b0;

    assign io_slave_awready = 1'b0;
    assign io_slave_wready = 1'b0;

    assign io_slave_bvalid = 1'b0;
    assign io_slave_bid = 4'b0000;
    assign io_slave_bresp = 2'b00;

    assign io_slave_arready = 1'b0;

    assign io_slave_rvalid = 1'b0;
    assign io_slave_rdata = 32'h00000000;
    assign io_slave_rresp = 2'b00;
    assign io_slave_rlast = 1'b0;
    assign io_slave_rid = 4'b0000;

endmodule
