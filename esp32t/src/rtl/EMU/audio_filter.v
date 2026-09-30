// Stereo wrapper: hclk/2 low-pass -> hclk/16 biquad -> hclk/256 output.
// Independent DSPs per channel. See docs/audio_dsp_analysis.py.
module audio_filter (
    input reset, input clk,
    input [15:0] core_l, core_r,
    output reg [15:0] filter_l, filter_r
);
    reg [1:0] reset_sync = 2'b11;
    always @(posedge clk or posedge reset)
        if (reset) reset_sync <= 2'b11;
        else reset_sync <= {reset_sync[0],1'b0};
    wire filter_reset = reset_sync[1];
    reg [7:0] div;
    always @(posedge clk or posedge filter_reset)
        if (filter_reset) div <= 0;
        else div <= div + 1'b1;
    wire first_ce = !div[0];
    wire biquad_ce = div[3:0] == 4'd1;
    wire sample_ce = div == 8'd0;

    // Preserve existing input acceptance, on the same hclk as the core.
    reg [15:0] cl, cr, cl1, cl2, cr1, cr2;
    always @(posedge clk or posedge filter_reset) begin
        if (filter_reset) begin
            cl<=0; cr<=0; cl1<=0; cl2<=0; cr1<=0; cr2<=0;
        end else begin
            cl1<=core_l; cl2<=cl1; if (cl2==cl1) cl<=cl2;
            cr1<=core_r; cr2<=cr1; if (cr2==cr1) cr<=cr2;
        end
    end
    wire signed [26:0] low_l, low_r, audio_l, audio_r;
    audio_iir1_dsp lp_l (
        .clk(clk),
        .reset(filter_reset),
        .ce(first_ce),
        .din(cl),
        .dout(low_l)
    );
    audio_iir1_dsp lp_r (
        .clk(clk),
        .reset(filter_reset),
        .ce(first_ce),
        .din(cr),
        .dout(low_r)
    );
    audio_biquad_dsp bq_l (
        .clk(clk),
        .reset(filter_reset),
        .ce(biquad_ce),
        .din(low_l),
        .dout(audio_l),
        .valid()
    );
    audio_biquad_dsp bq_r (
        .clk(clk),
        .reset(filter_reset),
        .ce(biquad_ce),
        .din(low_r),
        .dout(audio_r),
        .valid()
    );

    function [15:0] pcm16;
        input signed [26:0] value;
        reg signed [17:0] rounded;
        begin
            rounded = $signed(value[26:10]) + $signed({17'd0,(value[9] && (!value[26] || (|value[8:0])))});
            if (rounded > 18'sd32767) pcm16 = 16'h7fff;
            else if (rounded < -18'sd32768) pcm16 = 16'h8000;
            else pcm16 = rounded[15:0];
        end
    endfunction
    // Keep the existing approximately 125 ms startup mute.
    reg [12:0] mute_count;
    reg unmuted;
    always @(posedge clk or posedge filter_reset) begin
        if (filter_reset) begin
            mute_count<=0; unmuted<=0; filter_l<=0; filter_r<=0;
        end else if (sample_ce) begin
            if (!unmuted) begin
                if (&mute_count) unmuted<=1;
                else mute_count<=mute_count+1'b1;
            end
            filter_l <= unmuted ? pcm16(audio_l) : 16'd0;
            filter_r <= unmuted ? pcm16(audio_r) : 16'd0;
        end
    end
endmodule
