`include "usb_video/uvc_defs.v"
// UVC 1.1 PROBE and COMMIT are distinct. A complete SET_CUR data stage is
// required before either selection changes; PROBE never changes the raster.
module uvc_control #(parameter DEFAULT_SCALE_2X=1'b1) (
    input reset, input clk, input header_ready,
    input [7:0] request_type, input [7:0] request,
    input [15:0] value, input [15:0] index, input [15:0] length,
    input [15:0] offset, input [7:0] rxdata,
    input rxact, input rxvalid, input txpop,
    output reg txvalid, output reg [11:0] txlength,
    output reg [7:0] txdata, output scale_2x
);
    localparam [7:0] DEFAULT_FRAME_INDEX = DEFAULT_SCALE_2X ? 8'd1 : 8'd2;
    reg [7:0] probe_index, commit_index, received_index;
    wire selected = header_ready && index == `UVC_VS_INTERFACE && value[7:0] == 0
        && (value[15:8] == `VS_PROBE_CONTROL || value[15:8] == `VS_COMMIT_CONTROL);
    assign scale_2x = commit_index == 1;
    wire [7:0] reply_index = request == `GET_CUR
        ? (value[15:8] == `VS_COMMIT_CONTROL ? commit_index : probe_index)
        : request == `GET_DEF ? DEFAULT_FRAME_INDEX : 8'd1;
    wire [31:0] reply_size = reply_index == 2 ? 32'd46080 : 32'd184320;
    wire [31:0] reply_payload = reply_index == 2 ? 32'd1024 : 32'd2048;
    wire block_get = request == `GET_CUR || request == `GET_DEF
        || request == `GET_MIN || request == `GET_MAX || request == `GET_RES;
    wire supported_get = block_get || request == `GET_LEN || request == `GET_INFO;
    wire [11:0] reply_length = request == `GET_LEN ? 12'd2 :
                              request == `GET_INFO ? 12'd1 : 12'd34;
    function [7:0] reply_byte;
        input [15:0] address;
        begin
            reply_byte = 0;
            if (request == `GET_LEN) begin
                if (address == 0) reply_byte = 34;
            end else if (request == `GET_INFO) begin
                if (address == 0) reply_byte = 3; // GET and SET supported
            end else if (request != `GET_RES) begin
                case (address)
                    2: reply_byte = 1; // YUY2 format
                    3: reply_byte = reply_index;
                    4: reply_byte = (`FRAME_INTERVAL >> 0) & 255;
                    5: reply_byte = (`FRAME_INTERVAL >> 8) & 255;
                    6: reply_byte = (`FRAME_INTERVAL >> 16) & 255;
                    7: reply_byte = (`FRAME_INTERVAL >> 24) & 255;
                    18: reply_byte = reply_size[7:0];
                    19: reply_byte = reply_size[15:8];
                    20: reply_byte = reply_size[23:16];
                    21: reply_byte = reply_size[31:24];
                    22: reply_byte = reply_payload[7:0];
                    23: reply_byte = reply_payload[15:8];
                    24: reply_byte = reply_payload[23:16];
                    25: reply_byte = reply_payload[31:24];
                    26: reply_byte = 8'h00; // 60,000,000 Hz
                    27: reply_byte = 8'h87;
                    28: reply_byte = 8'h93;
                    29: reply_byte = 8'h03;
                    default: reply_byte = 0;
                endcase
            end
        end
    endfunction
    always @(posedge clk) begin
        if (reset) begin
            probe_index <= DEFAULT_FRAME_INDEX;
            commit_index <= DEFAULT_FRAME_INDEX;
            received_index <= DEFAULT_FRAME_INDEX;
            txvalid <= 0;
            txlength <= 0;
            txdata <= 0;
        end else if (!selected) begin
            txvalid <= 0;
        end else if (request_type == 8'h21 && request == `SET_CUR) begin
            txvalid <= 0;
            if (rxact && rxvalid && (length == 26 || length == 34)) begin
                if (offset == 3) received_index <= (rxdata == 1 || rxdata == 2)
                    ? rxdata : DEFAULT_FRAME_INDEX;
                if (offset == length - 1'b1) begin
                    if (value[15:8] == `VS_PROBE_CONTROL) probe_index <= received_index;
                    else commit_index <= received_index;
                end
            end
        end else if (request_type == 8'hA1 && supported_get && length != 0) begin
            if (txpop) begin
                txdata <= reply_byte(offset + 1'b1);
                if (offset + 1'b1 >= txlength) txvalid <= 0;
            end else if (offset == 0) begin
                txvalid <= 1;
                txlength <= length < reply_length ? length[11:0] : reply_length;
                txdata <= reply_byte(0);
            end
        end else txvalid <= 0;
    end
endmodule
