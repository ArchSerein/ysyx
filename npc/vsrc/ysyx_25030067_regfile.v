module ysyx_25030067_regfile (
    input clock,
    input reset,
    input [4:0] reg_src1_i,
    input [4:0] reg_src2_i,
    input [4:0] reg_dst_i,
    input reg_wen_i,
    input [31:0] reg_wdata_i,
    output [31:0] reg_rdata1_o,
    output [31:0] reg_rdata2_o
);

    // Internal signals
    // 通用寄存器
    reg [31:0] regfile [1:31];

    // write
    // 在 write back 阶段写入
    wire wr_en;
    assign wr_en = reg_wen_i && (reg_dst_i != 5'b0);
    always @(posedge clock)
    begin
      if (wr_en) begin
        regfile[reg_dst_i] <= reg_wdata_i;
      end
    end

    // read
    assign reg_rdata1_o = (reg_src1_i == 5'b0) ?
                          32'b0 : regfile[reg_src1_i];
    assign reg_rdata2_o = (reg_src2_i == 5'b0) ?
                          32'b0 : regfile[reg_src2_i];

endmodule
