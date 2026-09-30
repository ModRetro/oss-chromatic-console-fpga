// Two owned line banks cross RGB666 from the video clock to USB. A bank
// stays unchanged from publication until the reader acknowledges BOTH copies.
// Source: one strobe per pixel, frame_start before row zero, line_end after
// the last pixel. Short lines or lack of a free bank discard the rest of the
// source frame; the next frame_start restores alignment without overwriting
// a bank still in use. Memory is deliberately not reset.
module uvc_capture #(
    parameter SOURCE_WIDTH = 160, parameter SOURCE_HEIGHT = 144
) (
    input reset,
    input source_clk, input source_frame_start, input source_line_end,
    input source_valid, input [17:0] source_pixel,
    input usb_clk, input scale_2x,
    output reg frame_start, output reg frame_scale_2x,
    output reg pixel_valid, output reg [17:0] pixel
);
    reg [17:0] line_ram [0:511];
    reg [1:0] published, consumed;
    (* syn_async_reg = "true" *) reg [1:0] consumed_meta, consumed_sync;
    (* syn_async_reg = "true" *) reg [1:0] published_meta, published_sync;
    // Bundled metadata is stable with its RAM bank until acknowledgement.
    reg [1:0] first_line;
    reg write_bank, read_bank;
    reg [7:0] write_x, write_y;
    reg discard;
    wire bank_free = published[write_bank] == consumed_sync[write_bank];
    (* syn_async_reg = "true" *) reg [1:0] source_reset_pipe, usb_reset_pipe;
    always @(posedge source_clk or posedge reset)
        if (reset) source_reset_pipe <= 2'b11;
        else source_reset_pipe <= {source_reset_pipe[0], 1'b0};
    always @(posedge usb_clk or posedge reset)
        if (reset) usb_reset_pipe <= 2'b11;
        // Wait for source state to reset before observing its bank toggles.
        // A one-USB-clock bus reset can be shorter than a source clock.
        else usb_reset_pipe <= {usb_reset_pipe[0], source_reset_pipe[1]};

    always @(posedge source_clk) begin
        if (source_reset_pipe[1]) begin
            consumed_meta <= 0;
            consumed_sync <= 0;
            published <= 0;
            write_bank <= 0;
            write_x <= 0;
            write_y <= 0;
            first_line <= 0;
            discard <= 1;
        end else begin
            consumed_meta <= consumed;
            consumed_sync <= consumed_meta;
            if (source_frame_start) begin
                write_x <= 0;
                write_y <= 0;
                discard <= 0;
            end else if (source_line_end) begin
                if (write_x != 0 && write_x != SOURCE_WIDTH)
                    discard <= 1;
                write_x <= 0;
            end else if (source_valid && !discard && write_y < SOURCE_HEIGHT
                         && write_x < SOURCE_WIDTH) begin
                if (!bank_free) begin
                    discard <= 1;
                end else begin
                    line_ram[{write_bank, write_x}] <= source_pixel;
                    write_x <= write_x + 1'b1;
                    if (write_x == SOURCE_WIDTH-1) begin
                        first_line[write_bank] <= write_y == 0;
                        published[write_bank] <= ~published[write_bank];
                        write_bank <= ~write_bank;
                        write_y <= write_y + 1'b1;
                    end
                end
            end
        end
    end

    reg busy, have_frame, repeat_x, repeat_y;
    reg [7:0] read_x;
    reg [1:0] phase;
    reg [17:0] ram_q;
    // Exactly one synchronous read port; replication reuses this port.
    always @(posedge usb_clk)
        ram_q <= line_ram[{read_bank, read_x}];
    always @(posedge usb_clk) begin
        if (usb_reset_pipe[1]) begin
            published_meta <= 0;
            published_sync <= 0;
            consumed <= 0;
            read_bank <= 0;
            read_x <= 0;
            phase <= 0;
            busy <= 0;
            have_frame <= 0;
            repeat_x <= 0;
            repeat_y <= 0;
            frame_start <= 0;
            frame_scale_2x <= 1;
            pixel_valid <= 0;
            pixel <= 0;
        end else begin
            published_meta <= published;
            published_sync <= published_meta;
            frame_start <= 0;
            pixel_valid <= 0;
            if (!busy) begin
                if (published_sync[read_bank] != consumed[read_bank]) begin
                    if (first_line[read_bank] || have_frame) begin
                        busy <= 1;
                        read_x <= 0;
                        phase <= 0;
                        repeat_x <= 0;
                        repeat_y <= 0;
                        if (first_line[read_bank]) begin
                            frame_start <= 1;
                            frame_scale_2x <= scale_2x;
                            have_frame <= 1;
                        end
                    end else begin
                        consumed[read_bank] <= published_sync[read_bank];
                        read_bank <= ~read_bank;
                    end
                end
            end else begin
                phase <= phase + 1'b1;
                if (phase == 3) begin
                    pixel <= ram_q;
                    pixel_valid <= 1;
                    if (frame_scale_2x && !repeat_x) begin
                        repeat_x <= 1;
                    end else begin
                        repeat_x <= 0;
                        if (read_x == SOURCE_WIDTH-1) begin
                            read_x <= 0;
                            if (frame_scale_2x && !repeat_y) begin
                                repeat_y <= 1;
                            end else begin
                                busy <= 0;
                                consumed[read_bank] <= published_sync[read_bank];
                                read_bank <= ~read_bank;
                            end
                        end else read_x <= read_x + 1'b1;
                    end
                end
            end
        end
    end
endmodule
