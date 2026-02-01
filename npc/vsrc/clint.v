module ysyx_25030067_clint (
    input                   clock,
    input                   reset,

    input                   arvalid_i,
    output                  arready_o,
    input  [31:0]           araddr_i,

    output                  rvalid_o,
    input                   rready_i,
    output  [31:0]          rdata_o
);

    reg     [31:0]          mtime_h;
    reg     [31:0]          mtime_l;
    reg     [31:0]          raddr;
    reg                     valid;
    always @(posedge clock) begin
        if (reset) begin
            mtime_h <= 0;
            mtime_l <= 0;
        end else begin
          if (mtime_l == 32'hffffffff) begin
            mtime_h <= mtime_h + 1;
          end
          mtime_l <= mtime_l + 1;
        end
    end
    always @(posedge clock) begin
      if (arvalid_i && !valid) begin
        valid <= 1;
        raddr <= araddr_i;
      end else if (rready_i) begin
        valid <= 0;
      end
    end

    assign rdata_o     = raddr[3:0] == 4'hc ? mtime_h : mtime_l; 
    assign arready_o   = !valid;
    assign rvalid_o    = valid;
endmodule
