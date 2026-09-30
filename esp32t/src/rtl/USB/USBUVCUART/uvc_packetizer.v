// UVC payload transfer -> one or two high-speed isochronous transactions.
// Reserve the entire transfer at SOF; bytes arriving later cannot change its
// lengths, PID promise, or EOF. The 12-byte header occurs only in transaction
// one. txpop consumes the currently presented byte (no speculative FIFO pop).
module uvc_packetizer (
    input clk, input reset, input enabled, input high_bandwidth,
    input frame_start, input [17:0] frame_bytes,
    input byte_valid, input [7:0] byte_data,
    input sof, input txact, input txpop,
    output reg [7:0] txdata, output reg [11:0] txlength,
    output cork, output reg [3:0] pid,
    output reg overflow
);
    localparam IDLE=2'd0, ARMED=2'd1, ACTIVE=2'd2;
    reg [1:0] state;
    reg live_frame, fid, transfer_eof, continuation;
    reg [17:0] remaining;
    reg [11:0] second_length;
    reg [10:0] position;
    reg [31:0] timestamp, frame_pts, transfer_pts, transfer_scr;
    reg [13:0] microframe;
    reg [10:0] transfer_sof;
    reg transfer_fid, transfer_error;
    wire [7:0] front;
    wire [12:0] count;
    wire full;
    wire payload_byte = continuation || position >= 12;
    wire pop = txpop && state != IDLE && payload_byte;
    // The controller can accept an advertised idle header before txact rises.
    // Starting capture must not cancel that header or reset its byte position.
    // It owns no FIFO payload, so capture may still clear/refill the FIFO.
    wire keep_idle = state == ARMED && !continuation &&
                     txlength == 12 && !transfer_eof && !sof;
    // A transfer still owns its queued bytes when txact falls: retirement
    // may arm DATA0, which remains promised throughout the inter-packet gap.
    wire transfer_owned = txact || state == ACTIVE ||
                          (state == ARMED && continuation);
    wire accept_frame = frame_start && (!transfer_owned || keep_idle);
    wire clear = reset || !enabled || accept_frame;
    uvc_byte_fifo fifo (
        .clk(clk),
        .clear(clear),
        .push(byte_valid && live_frame && !frame_start),
        .data(byte_data),
        .pop(pop),
        .front(front),
        .count(count),
        .full(full)
    );
    assign cork = state == IDLE;
    wire [12:0] capacity = high_bandwidth ? 13'd2036 : 13'd1012;
    wire [17:0] wanted = remaining < capacity ? remaining : {5'd0,capacity};
    // Do not emit short transfers mid-frame: only the final transfer may
    // consume fewer than 1012 bytes. Header-only transfers keep host timing.
    wire [11:0] reserve_bytes = !live_frame ? 12'd0 :
        (count >= wanted) ? wanted[11:0] :
        (count >= 1012 && remaining >= 1012) ? 12'd1012 : 12'd0;
    always @* begin
        txdata = front;
        if (!continuation && position < 12) begin
            case (position)
                0: txdata = 12;
                1: txdata = {1'b1, transfer_error, 2'b00, 2'b11, transfer_eof, transfer_fid};
                2: txdata = transfer_pts[7:0];
                3: txdata = transfer_pts[15:8];
                4: txdata = transfer_pts[23:16];
                5: txdata = transfer_pts[31:24];
                6: txdata = transfer_scr[7:0];
                7: txdata = transfer_scr[15:8];
                8: txdata = transfer_scr[23:16];
                9: txdata = transfer_scr[31:24];
                10: txdata = transfer_sof[7:0];
                11: txdata = {5'd0,transfer_sof[10:8]};
                default: txdata = 0;
            endcase
        end
    end
    always @(posedge clk) begin
        if (reset) begin
            state <= IDLE;
            live_frame <= 0;
            remaining <= 0;
            fid <= 0;
            timestamp <= 0;
            microframe <= 0;
            frame_pts <= 0;
            transfer_pts <= 0;
            transfer_scr <= 0;
            transfer_sof <= 0;
            transfer_fid <= 0;
            transfer_error <= 0;
            transfer_eof <= 0;
            continuation <= 0;
            second_length <= 0;
            position <= 0;
            txlength <= 0;
            pid <= 4'b0011;
            overflow <= 0;
        end else begin
            timestamp <= timestamp + 1'b1;
            if (sof) microframe <= microframe + 1'b1;
            if (!enabled) begin
                state <= IDLE;
                live_frame <= 0;
                remaining <= 0;
                overflow <= 0;
            end else if (accept_frame) begin
                // Drop any unfinished previous frame. A new FID tells the
                // host to discard it; never splice two source frames.
                if (!keep_idle) state <= IDLE;
                else begin
                    if (txact) state <= ACTIVE;
                    if (txpop) position <= position + 1'b1;
                end
                live_frame <= 1;
                remaining <= frame_bytes;
                fid <= ~fid;
                frame_pts <= timestamp;
                overflow <= 0;
            end else begin
                if (frame_start || (byte_valid && live_frame && full && !pop)) begin
                    live_frame <= 0;
                    overflow <= 1;
                end
                if (sof && state != IDLE) begin
                    // A promised transaction was not requested/completed in
                    // its microframe. Do not reuse its bytes in a later frame.
                    live_frame <= 0;
                    overflow <= 1;
                    if (!txact) state <= IDLE;
                end else if (sof && !txact) begin
                    state <= ARMED;
                    position <= 0;
                    continuation <= 0;
                    transfer_pts <= frame_pts;
                    transfer_scr <= timestamp;
                    transfer_sof <= microframe[13:3]; // USB frame, not microframe
                    transfer_fid <= fid;
                    // Snapshot ERR with the header; never change flags in flight.
                    transfer_error <= overflow;
                    transfer_eof <= reserve_bytes != 0 && reserve_bytes == remaining;
                    remaining <= remaining - reserve_bytes;
                    txlength <= reserve_bytes > 1012 ? 12'd1024 : reserve_bytes + 12'd12;
                    second_length <= reserve_bytes > 1012 ? reserve_bytes - 12'd1012 : 12'd0;
                    pid <= reserve_bytes > 1012 ? 4'b1011 : 4'b0011;
                end else begin
                    if (state == ARMED && txact) state <= ACTIVE;
                    if (txpop && state != IDLE) position <= position + 1'b1;
                    if (state == ACTIVE && !txact) begin
                        position <= 0;
                        if ({1'b0,position} != txlength) begin
                            // Unconsumed reserved bytes no longer have a valid
                            // frame offset. Cancel the pair and ignore producer
                            // bytes until a new capture safely flushes the FIFO.
                            live_frame <= 0;
                            overflow <= 1;
                            second_length <= 0;
                            state <= IDLE;
                        end else if (second_length != 0) begin
                            state <= ARMED;
                            continuation <= 1;
                            txlength <= second_length;
                            second_length <= 0;
                            pid <= 4'b0011;
                        end else state <= IDLE;
                    end
                end
            end
        end
    end
endmodule
