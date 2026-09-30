// RGB666 to BT.601 limited-range YUY2. One pixel strobe every >=4 clocks.
// Conversion uses the existing capture matrix, truncating without rounding:
// Y=16+(66R+129G+25B)/256; U=128+(-38R-74G+112B)/256;
// V=128+(112R-94G-18B)/256. R/G/B here are source components * 4.
// No DSP multipliers and no vendor IP. Clear at each accepted source frame.
module uvc_rgb_to_yuy2 (
    input clk, input reset, input pixel_valid, input [17:0] pixel,
    output reg byte_valid, output reg [7:0] byte_data
);
    wire [13:0] r = {8'd0, pixel[5:0]};
    wire [13:0] g = {8'd0, pixel[11:6]};
    wire [13:0] b = {8'd0, pixel[17:12]};
    reg [13:0] yr, yg, yb, ur, ug, ub, vr, vg, vb;
    reg [13:0] sy, su, sv;
    reg [2:0] valid_pipe;
    reg [7:0] y, u, v;
    reg pair_second;
    reg [7:0] first_y, first_u, first_v;
    reg [7:0] pair_u, pair_y, pair_v;
    reg [1:0] emit_left;
    wire [8:0] sum_u = {1'b0, first_u} + {1'b0, u};
    wire [8:0] sum_v = {1'b0, first_v} + {1'b0, v};
    always @(posedge clk) begin
        // With six-bit inputs the denominator is 64. The biased sums fit
        // in 14 unsigned bits, including the negative chroma terms.
        yr <= (r << 6) + (r << 1);
        yg <= (g << 7) + g;
        yb <= (b << 4) + (b << 3) + b;
        ur <= (r << 5) + (r << 2) + (r << 1);
        ug <= (g << 6) + (g << 3) + (g << 1);
        ub <= (b << 7) - (b << 4);
        vr <= (r << 7) - (r << 4);
        vg <= (g << 6) + (g << 5) - (g << 1);
        vb <= (b << 4) + (b << 1);
        sy <= 14'd1024 + yr + yg + yb;
        su <= 14'd8192 + ub - ur - ug;
        sv <= 14'd8192 + vr - vg - vb;
        y <= sy[13:6];
        u <= su[13:6];
        v <= sv[13:6];
        if (reset) begin
            valid_pipe <= 0;
            pair_second <= 0;
            emit_left <= 0;
            byte_valid <= 0;
            byte_data <= 0;
        end else begin
            valid_pipe <= {valid_pipe[1:0], pixel_valid};
            byte_valid <= 0;
            if (valid_pipe[2]) begin
                pair_second <= ~pair_second;
                if (!pair_second) begin
                    first_y <= y;
                    first_u <= u;
                    first_v <= v;
                end else begin
                    byte_data <= first_y;
                    byte_valid <= 1;
                    pair_u <= sum_u[8:1];
                    pair_y <= y;
                    pair_v <= sum_v[8:1];
                    emit_left <= 3;
                end
            end
            if (emit_left != 0) begin
                byte_valid <= 1;
                emit_left <= emit_left - 1'b1;
                case (emit_left)
                    3: byte_data <= pair_u;
                    2: byte_data <= pair_y;
                    1: byte_data <= pair_v;
                    default: byte_data <= 0;
                endcase
            end
        end
    end
endmodule
