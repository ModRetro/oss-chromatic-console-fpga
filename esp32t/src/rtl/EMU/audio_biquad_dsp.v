// Mono Direct Form I: y = b0*x+b1*x1+b2*x2-a1*y1-a2*y2.
// 27-bit sample histories (10 fractional bits), signed Q16 coefficients.
// One dedicated DSP per channel. ce must be separated by at least 7 clocks.
module audio_biquad_dsp #(
    parameter signed [17:0] B0 = 18'sd4711,
    parameter signed [17:0] B1 = 18'sd0,
    parameter signed [17:0] B2 = -18'sd4711,
    parameter signed [17:0] A1 = -18'sd121642,
    parameter signed [17:0] A2 = 18'sd56107
)(
    input clk, input reset, input ce,
    input signed [26:0] din,
    output reg signed [26:0] dout,
    output reg valid
);
    reg [2:0] phase;
    reg signed [26:0] x, x1, x2, y1, y2;
    reg signed [16:0] remainder;
    reg signed [26:0] operand;
    reg signed [17:0] coefficient;
    wire signed [47:0] acc;
    wire active = phase >= 1 && phase <= 5;
    // First product starts with the saved fraction through C and zero preload.
    // Later products use the DSP's internal accumulator feedback, with C off.
    wire first_product = phase == 1;
    wire round_up = acc[15] && (!acc[47] || (|acc[14:0]));
    wire signed [31:0] rounded = $signed(acc[47:16]) + $signed({31'd0,round_up});
    wire overflow = rounded[31:26] != {6{rounded[26]}};
    wire signed [26:0] next_y = overflow ?
        (rounded[31] ? {1'b1,26'd0} : {1'b0,{26{1'b1}}}) : rounded[26:0];
    // A low-word carry was added by rounding, so subtract 65536 from
    // the remainder in that case. This is exactly a signed 17-bit wiring.
    wire signed [16:0] next_remainder = {round_up,acc[15:0]};
    always @* begin
        operand = 0; coefficient = 0;
        case (phase)
            1: begin operand = x;  coefficient = B0; end
            2: begin operand = x1; coefficient = B1; end
            3: begin operand = x2; coefficient = B2; end
            4: begin operand = y1; coefficient = -A1; end
            5: begin operand = y2; coefficient = -A2; end
            default: begin end
        endcase
    end
    always @(posedge clk or posedge reset) begin
        if (reset) begin
            phase <= 0; x <= 0; x1 <= 0; x2 <= 0;
            y1 <= 0; y2 <= 0; remainder <= 0; dout <= 0; valid <= 0;
        end else begin
            valid <= 0;
            if (phase == 0) begin
                if (ce) begin x <= din; phase <= 1; end
            end else if (phase == 6) begin
                x2 <= x1; x1 <= x; y2 <= y1; y1 <= next_y;
                remainder <= overflow ? 17'sd0 : next_remainder;
                dout <= next_y; valid <= 1; phase <= 0;
            end else phase <= phase + 1'b1;
        end
    end
    MULTALU27X18 #(
        .DYN_C_SEL("TRUE"), .DYN_ACC_SEL("TRUE"),
        .PRE_LOAD(48'd0),
        .OREG_CLK("CLK0"), .MULT_RESET_MODE("ASYNC")
    ) dsp (
        .A(operand), .D(26'd0), .B(coefficient), .C({{31{remainder[16]}},remainder}),
        .DOUT(acc), .CASO(), .SOA(), .SIA(27'd0), .CASI(48'd0),
        .PSEL(1'b0), .ASEL(1'b0), .CSEL(first_product), .CASISEL(1'b0),
        .PADDSUB(1'b0), .ACCSEL(!first_product), .ADDSUB(2'b00),
        .CLK({1'b0,clk}), .CE({1'b0,active}), .RESET({1'b0,reset})
    );
endmodule
