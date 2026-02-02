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
    reg [31:0] regfile [31:0];

    // write
    // 在 write back 阶段写入
    always @(posedge clock)
    begin
        if (reset) begin
            for (int i = 0; i < 32; i = i + 1) begin
                regfile[i] <= 32'b0;
            end
        end
        if (reg_wen_i) begin
            regfile[reg_dst_i] <= reg_wdata_i;
        end

        // x0 always be zero
        regfile[0] <= 32'b0;
    end

    // read
    assign reg_rdata1_o = regfile[reg_src1_i];
    assign reg_rdata2_o = regfile[reg_src2_i];

endmodule
