// Mono 40 kHz low-pass at hclk/2. Ten fractional sample bits, Q16 alpha.
// Keep the unrounded accumulator: acc = y*65536 + remainder, so feeding
// it back through C implements fraction saving without another wide adder.
module audio_iir1_dsp #(
    parameter signed [17:0] ALPHA = 18'sd1934
)(
    input clk, input reset, input ce,
    input signed [15:0] din,
    output signed [26:0] dout
);
    wire signed [47:0] acc;
    // Nearest rounding, ties away from zero. For negative values, a tie
    // rounds down; for positive values it rounds up.
    wire round_up = acc[15] && (!acc[47] || (|acc[14:0]));
    wire signed [31:0] rounded = $signed(acc[47:16]) + $signed({31'd0,round_up});
    // The first-order convex update stays in the signed 16-bit input range.
    wire signed [25:0] state_value = rounded[25:0];
    assign dout = {state_value[25],state_value};

    MULTALU27X18 #(
        .P_SEL(1'b1), .P_ADDSUB(1'b1),
        .C_SEL(1'b1), .ACC_SEL(1'b0),
        .OREG_CLK("CLK0"), .MULT_RESET_MODE("ASYNC")
    ) dsp (
        .A({din[15],din,10'd0}), .D(state_value), .B(ALPHA), .C(acc),
        .DOUT(acc), .CASO(), .SOA(), .SIA(27'd0), .CASI(48'd0),
        .PSEL(1'b0), .ASEL(1'b0), .CSEL(1'b0), .CASISEL(1'b0),
        .PADDSUB(1'b0), .ACCSEL(1'b0), .ADDSUB(2'b00),
        .CLK({1'b0,clk}), .CE({1'b0,ce}), .RESET({1'b0,reset})
    );
endmodule
