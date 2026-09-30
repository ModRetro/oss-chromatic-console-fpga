// Single-clock, synchronous-read RAM FIFO. count includes the front byte.
// The front register always presents the next byte, including empty writes
// and simultaneous last-byte pop/write. No asynchronous RAM read or CDC.
module uvc_byte_fifo #(parameter ADDRESS_BITS = 12) (
    input clk, input clear, input push, input [7:0] data,
    input pop, output reg [7:0] front,
    output reg [ADDRESS_BITS:0] count, output full
);
    reg [7:0] memory [0:(1<<ADDRESS_BITS)-1];
    reg [ADDRESS_BITS-1:0] write_address, read_address;
    wire take = pop && count != 0;
    assign full = count == (1<<ADDRESS_BITS);
    wire put = push && (!full || take);
    wire [ADDRESS_BITS-1:0] next_read = read_address + take;
    always @(posedge clk) begin
        if (put) memory[write_address] <= data;
        if (count > (take ? 1 : 0)) front <= memory[next_read];
        if (put && count == (take ? 1 : 0)) front <= data;
        if (clear) begin
            count <= 0;
            write_address <= 0;
            read_address <= 0;
            front <= 0;
        end else begin
            if (put) write_address <= write_address + 1'b1;
            if (take) read_address <= next_read;
            case ({put,take})
                2'b10: count <= count + 1'b1;
                2'b01: count <= count - 1'b1;
                default: ;
            endcase
        end
    end
endmodule
