module ysyx_25030067_compare(
    input [31:0] compare_a_i,
    input [31:0] compare_b_i,
    input [2:0] compare_fn_i,
    output      compare_o
);
    wire equal, signed_less, unsigned_less;
    assign equal = compare_a_i == compare_b_i;
    assign signed_less = $signed(compare_a_i) < $signed(compare_b_i);
    assign unsigned_less = compare_a_i < compare_b_i;

    wire equal_or_not;
    wire less_than_or_not_signed;
    wire less_or_greater_unsigned;
    wire not_less_unsigned;
    assign equal_or_not = compare_fn_i[0] ? !equal : equal;
    assign less_than_or_not_signed = compare_fn_i[0] ? signed_less : !signed_less;
    assign less_or_greater_unsigned = compare_fn_i[0] ? unsigned_less : !unsigned_less && !equal;
    assign not_less_unsigned = !compare_fn_i[0] && !unsigned_less;

    wire equal_or_signed;
    wire unsigned_compare;
    assign equal_or_signed = compare_fn_i[1] ? less_than_or_not_signed : equal_or_not;
    assign unsigned_compare = compare_fn_i[1] ? not_less_unsigned : less_or_greater_unsigned;

    assign compare_o = compare_fn_i[2] ? unsigned_compare : equal_or_signed;
endmodule
