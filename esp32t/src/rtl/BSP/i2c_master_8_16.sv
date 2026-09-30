`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company:  www.circuitden.com
// Engineer: Artin Isagholian
//           artinisagholian@gmail.com
// 
// Create Date: 01/20/2021 05:47:22 PM
// Design Name: 
// Module Name: i2c_master
// Project Name: 
// Target Devices: 
// Tool Versions: 
// Description: 
// 
// Dependencies: 
// 
// Revision:
// Revision 0.01 - File Created
// Additional Comments:
// 
//////////////////////////////////////////////////////////////////////////////////
module i2c_master_8_16#(
    parameter DATA_WIDTH      = 16,
    parameter REGISTER_WIDTH  = 8,
    parameter ADDRESS_WIDTH   = 7,
    // About 62.5 ms at hClk; bounds a stalled transaction, including STOP.
    parameter integer TIMEOUT_CYCLES = 1048576
)(
    input   wire            clock,
    input   wire            reset_n,
    input   wire            enable,
    input   wire            read_write,
    input   wire            use_16_bit,      // determine whether dealing with 8 or 16 bit
    input   wire    [15:0]  mosi_data,
    input   wire    [7:0]   register_address,
    input   wire    [6:0]   device_address,
    input   wire    [15:0]  divider,
    output  reg     [15:0]  miso_data,
    output  reg             busy,
    output  reg             transaction_error,
    inout                   external_serial_data,
    inout                   external_serial_clock
);

        localparam  S_IDLE                  =   15'b100000000000000;
        localparam  S_START                 =   15'b010000000000000;
        localparam  S_WRITE_ADDR_W          =   15'b001000000000000;
        localparam  S_CHECK_ACK             =   15'b000100000000000;
        localparam  S_WRITE_REG_ADDR        =   15'b000010000000000;
        localparam  S_RESTART               =   15'b000001000000000;
        localparam  S_WRITE_ADDR_R          =   15'b000000100000000;
        localparam  S_READ_REG              =   15'b000000010000000;
        localparam  S_SEND_NACK             =   15'b000000001000000;
        localparam  S_SEND_STOP             =   15'b000000000100000;
        localparam  S_WRITE_REG_DATA        =   15'b000000000010000;
        localparam  S_WRITE_REG_ADDR_MSB    =   15'b000000000001000;
        localparam  S_WRITE_REG_DATA_MSB    =   15'b000000000000100;
        localparam  S_READ_REG_MSB          =   15'b000000000000010;
        localparam  S_SEND_ACK              =   15'b000000000000001;

        reg [14:0]                      state;
        reg [14:0]                      _state;
        reg [14:0]                      post_state;
        reg [14:0]                      _post_state;

reg                             serial_clock;
logic                           _serial_clock;
reg     [7:0]                   saved_device_address;
logic   [7:0]                   _saved_device_address;
reg     [7:0]                   saved_register_address;
logic   [7:0]                   _saved_register_address;
reg     [15:0]                   saved_mosi_data;
logic   [15:0]                  _saved_mosi_data;
reg     [1:0]                   process_counter;
logic   [1:0]                   _process_counter;
reg     [7:0]                   bit_counter;
logic   [7:0]                   _bit_counter;
reg                             serial_data;
logic                           _serial_data;
reg                             post_serial_data;
logic                           _post_serial_data;
reg                             last_acknowledge;
logic                           _last_acknowledge;
logic                           _saved_read_write;
reg                             saved_read_write;
reg     [15:0]                  divider_counter;
logic   [15:0]                  _divider_counter;
reg                             divider_tick;
logic   [15:0]                  _miso_data;
logic                           _busy;
logic                           _transaction_error;
localparam integer TIMEOUT_WIDTH = $clog2(TIMEOUT_CYCLES + 1);
reg [TIMEOUT_WIDTH-1:0] transaction_age;
logic                           serial_data_output_enable;
logic                           serial_clock_output_enable;

logic                           saved_use_16_bit;
logic                           _saved_use_16_bit;


assign external_serial_clock    =   (serial_clock_output_enable)  ?   serial_clock  :   1'bz;
assign external_serial_data     =   (serial_data_output_enable)   ?   serial_data   :   1'bz;

always_comb begin
    _state                  =   state;
    _post_state             =   post_state;
    _process_counter        =   process_counter;
    _bit_counter            =   bit_counter;
    _last_acknowledge       =   last_acknowledge;
    _miso_data              =   miso_data;
    _saved_read_write       =   saved_read_write;
    _busy                   =   busy;
    _transaction_error      =   transaction_error;
    _divider_counter        =   divider_counter;
    _saved_register_address =   saved_register_address;
    _saved_device_address   =   saved_device_address;
    _saved_mosi_data        =   saved_mosi_data;
    _serial_data            =   serial_data;
    _serial_clock           =   serial_clock;
    _post_serial_data       =   post_serial_data;
    
    _saved_use_16_bit       =   saved_use_16_bit;

    if (divider_counter == divider) begin
        _divider_counter    =   0;
        divider_tick        =   1;
    end
    else begin
        _divider_counter    =   divider_counter + 1;
        divider_tick        =   0;
    end

    if ((state!=S_IDLE) && (state!=S_CHECK_ACK) && (state!=S_READ_REG) && (state!=S_READ_REG_MSB)) begin
        serial_data_output_enable   =   1;
    end
    else begin
        serial_data_output_enable   =   0;
    end

    if (state!=S_IDLE && process_counter!=1 && process_counter!=2) begin
        serial_clock_output_enable   =   1;
    end
    else begin
        serial_clock_output_enable   =   0;
    end

    case (state)
        S_IDLE: begin
            _process_counter        =   0;
            _bit_counter            =   0;
            _last_acknowledge       =   0;
            _busy                   =   0;
            _saved_read_write       =   read_write;
            _saved_register_address =   register_address;
            _saved_device_address   =   {device_address,1'b0};
            _saved_mosi_data        =   mosi_data;
            _serial_data            =   1;
            _serial_clock           =   1;
            _saved_use_16_bit       =   use_16_bit;

            if (enable) begin
                _transaction_error = 0;
                _state      =   S_START;
                _post_state =   S_WRITE_ADDR_W;
                _busy       =   1;
            end
        end
        S_START: begin
            if (divider_tick) begin
                case (process_counter)
                    0: begin
                        _process_counter    =   1;
                    end
                    1: begin
                        _serial_data        =   0;
                        _process_counter    =   2;
                    end
                    2:  begin
                        _bit_counter        =   8;
                        _process_counter    =   3;
                    end
                    3:  begin
                        _serial_clock       =   0;
                        _process_counter    =   0;
                        _state              =   post_state;
                        _serial_data        =   saved_device_address[ADDRESS_WIDTH];
                    end
                endcase
            end
        end
        S_WRITE_ADDR_W: begin
            if (divider_tick) begin
                case (process_counter)
                    0: begin
                        _serial_clock       =   1;
                        _process_counter    =   1;
                    end
                    1: begin
                        if (external_serial_clock == 1) begin
                            _process_counter    =   2;
                        end
                    end
                    2: begin
                        _serial_clock       =   0;
                        _bit_counter        =   bit_counter -   1;
                        _process_counter    =   3;
                    end
                    3: begin
                        if (bit_counter == 0) begin
                            _post_serial_data   =   saved_register_address[REGISTER_WIDTH-1];

                            if (REGISTER_WIDTH == 16) begin
                               _post_state =   S_WRITE_REG_ADDR_MSB;
                            end
                            else begin
                                 _post_state =   S_WRITE_REG_ADDR;
                            end

                            _state          =   S_CHECK_ACK;
                            _bit_counter    =   8;
                        end
                        else begin
                            _serial_data    =   saved_device_address[bit_counter-1];
                        end
                        _process_counter    =   0;
                    end
                endcase
            end
        end
        S_CHECK_ACK: begin
            if (divider_tick) begin
                case (process_counter)
                    0: begin
                        _serial_clock       =   1;
                        _process_counter    =   1;
                    end
                    1: begin
                        if (external_serial_clock == 1) begin
                            _last_acknowledge   =   0;
                            _process_counter    =   2;
                        end
                    end
                    2: begin
                        _serial_clock   =   0;

                        if (external_serial_data == 0) begin
                            _last_acknowledge   =   1;
                        end
                        _process_counter    =   3;
                    end
                    3:  begin
                        if (last_acknowledge == 1) begin
                            _last_acknowledge   =   0;
                            _serial_data        =   post_serial_data;
                            _state              =   post_state;
                        end
                        else begin
                            _transaction_error = 1;
                            _serial_data = 0;
                            _state = S_SEND_STOP;
                        end
                        _process_counter =   0;
                    end
                endcase
            end
        end
        S_WRITE_REG_ADDR_MSB: begin
            if (divider_tick) begin
                case (process_counter)
                    0: begin
                        _serial_clock       =   1;
                        _process_counter    =   1;
                    end
                    1: begin
                        if (external_serial_clock == 1) begin
                            _last_acknowledge   =   0;
                            _process_counter    =   2;
                        end
                    end
                    2: begin
                        _serial_clock       =   0;
                        _bit_counter        =   bit_counter - 1;
                        _process_counter    =   3;
                    end
                    3: begin
                        if (bit_counter == 0) begin
                            _post_state         =   S_WRITE_REG_ADDR;
                            _post_serial_data   =   saved_register_address[7];
                            _bit_counter        =   8;
                            _serial_data        =   0;
                            _state              =   S_CHECK_ACK;
                        end
                        else begin
                            _serial_data        =   saved_register_address[bit_counter+3'd7];
                        end
                        _process_counter        =   0;
                    end
                endcase
            end
        end
        S_WRITE_REG_ADDR: begin
            if (divider_tick) begin
                case (process_counter)
                    0: begin
                        _serial_clock       =   1;
                        _process_counter    =   1;
                    end
                    1: begin
                        if (external_serial_clock == 1) begin
                            _last_acknowledge   =   0;
                            _process_counter    =   2;
                        end
                    end
                    2: begin
                        _serial_clock       =   0;
                        _bit_counter        =   bit_counter - 1;
                        _process_counter    =   3;
                    end
                    3: begin
                        if (bit_counter == 0) begin

                            if (saved_read_write == 0) begin
                                if (DATA_WIDTH == 16) begin
                                    _post_state         =   S_WRITE_REG_DATA_MSB;
                                    _post_serial_data   =   saved_mosi_data[15];
                                end
                                else begin
                                    _post_state         =   S_WRITE_REG_DATA;
                                    _post_serial_data   =   saved_mosi_data[7];
                                end
                            end
                            else begin
                                _post_state         =   S_RESTART;
                                _post_serial_data   =   1;
                            end
                            _bit_counter    =   8;
                            _serial_data    =   0;
                            _state          =   S_CHECK_ACK;
                        end
                        else begin
                            _serial_data    =   saved_register_address[bit_counter-1];
                        end
                        _process_counter    =   0;
                    end
                endcase
            end
        end
        S_WRITE_REG_DATA_MSB: begin
            if (divider_tick) begin
                case (process_counter)
                    0: begin
                        _serial_clock       =   1;
                        _process_counter    =   1;
                    end
                    1: begin
                        if (external_serial_clock == 1) begin
                            _last_acknowledge   =   1;
                            _process_counter    =   2;
                        end
                    end
                    2: begin
                        _serial_clock       =   0;
                        _bit_counter        =   bit_counter - 1;
                        _process_counter    =   3;
                    end
                    3: begin
                        if (bit_counter == 0) begin
                            _state              =   S_CHECK_ACK;
                            _post_state         =   S_WRITE_REG_DATA;
                            _post_serial_data   =   saved_mosi_data[7];
                            _bit_counter        =   8;
                            _serial_data        =   0;
                        end
                        else begin
                            _serial_data        =   saved_mosi_data[bit_counter+3'd7];
                        end
                        _process_counter        =   0;
                    end
                endcase
            end
        end
        S_WRITE_REG_DATA: begin
            if (divider_tick) begin
                case (process_counter)
                    0: begin
                        _serial_clock       =   1;
                        _process_counter    =   1;
                    end
                    1: begin
                        if (external_serial_clock == 1) begin
                            _last_acknowledge   =   0;
                            _process_counter    =   2;
                        end
                    end
                    2: begin
                        _serial_clock       =   0;
                        _bit_counter        =   bit_counter - 1;
                        _process_counter    =   3;
                    end
                    3: begin
                        if (bit_counter == 0) begin
                            _state              =   S_CHECK_ACK;
                            _post_state         =   S_SEND_STOP;
                            _post_serial_data   =   0;
                            _bit_counter        =   8;
                            _serial_data        =   0;
                        end
                        else begin
                            _serial_data        =   saved_mosi_data[bit_counter-1];
                        end
                        _process_counter        =   0;
                    end
                endcase
            end
        end
        S_RESTART: begin
            if (divider_tick) begin
                case (process_counter)
                    0: begin
                        _process_counter    =   1;
                    end
                    1: begin
                        _process_counter    =   2;
                        _serial_clock       =   1;
                    end
                    2: begin
                        _process_counter    =   3;
                    end
                    3: begin
                        _state                      =   S_START;
                        _post_state                 =   S_WRITE_ADDR_R;
                        _saved_device_address[0]    =   1;
                        _process_counter            =   0;
                    end
                endcase
            end
        end
        S_WRITE_ADDR_R: begin
            if (divider_tick) begin
                case (process_counter)
                    0: begin
                        _serial_clock       =   1;
                        _process_counter    =   1;
                    end
                    1: begin
                        if (external_serial_clock == 1) begin
                            _last_acknowledge   =   0;
                            _process_counter    =   2;
                        end
                    end
                    2: begin
                        _serial_clock       =   0;
                        _bit_counter        =   bit_counter - 1;
                        _process_counter    =   3;
                    end
                    3: begin
                        if (bit_counter == 0) begin
                            if ( saved_use_16_bit ) begin
                                _post_state         =   S_READ_REG_MSB;
                                _post_serial_data   =   0;
                            end
                            else begin
                                _post_state         =   S_READ_REG;
                                _post_serial_data   =   0;
                            end
                            _state          =   S_CHECK_ACK;
                            _bit_counter    =   8;
                        end
                        else begin
                            _serial_data    =   saved_device_address[bit_counter-1];
                        end
                        _process_counter    =   0;
                    end
                endcase
            end
        end
        S_READ_REG_MSB: begin
            if (divider_tick) begin
                case (process_counter)
                    0: begin
                        _serial_clock       =   1;
                        _process_counter    =   1;
                    end
                    1: begin
                        if (external_serial_clock == 1) begin
                            _last_acknowledge   =   0;
                            _process_counter    =   2;
                        end
                    end
                    2: begin
                        _serial_clock               =   0;
                        //sample data on this rising edge of scl
                        _miso_data[bit_counter+7]   =   external_serial_data;
                        _bit_counter                =   bit_counter - 1;
                        _process_counter            =   3;
                    end
                    3: begin
                        if (bit_counter == 0) begin
                            _post_state     =   S_READ_REG;
                            _state          =   S_SEND_ACK;
                            _bit_counter    =   8;
                            _serial_data    =   0;
                        end
                        _process_counter    =   0;
                    end
                endcase
            end
        end
        S_READ_REG: begin
            if (divider_tick) begin
                case (process_counter)
                    0: begin
                        _serial_clock       =   1;
                        _process_counter    =   1;
                    end
                    1: begin
                        if (external_serial_clock) begin
                            _last_acknowledge   =   0;
                            _process_counter    =   2;
                        end
                    end
                    2: begin
                        _serial_clock       =   0;
                        //sample data on this rising edge of scl
                        _miso_data[bit_counter-1]   =   external_serial_data;
                        _bit_counter                =   bit_counter - 1;
                        _process_counter    =   3;
                    end
                    3: begin
                        if (bit_counter == 0) begin
                            _state          =   S_SEND_NACK;
                            _serial_data    =   0;
                        end
                        _process_counter    =   0;
                    end
                endcase
            end
        end
        S_SEND_NACK: begin
            if (divider_tick) begin
                case (process_counter)
                    0: begin
                        _serial_clock       =   1;
                        _serial_data        =   1;
                        _process_counter    =   1;
                    end
                    1: begin
                        if (external_serial_clock) begin
                            _last_acknowledge   =   0;
                            _process_counter    =   2;
                        end
                    end
                    2: begin
                        _process_counter    =   3;
                        _serial_clock       =   0;
                    end
                    3: begin
                        _state              =   S_SEND_STOP;
                        _process_counter    =   0;
                        _serial_data        =   0;
                    end
                endcase
            end
        end
        S_SEND_ACK: begin
            if (divider_tick) begin
                case (process_counter)
                    0: begin
                        _serial_clock       =   1;
                        _process_counter    =   1;
                        _serial_data        =   0;
                    end
                    1: begin
                        if (external_serial_clock) begin
                            _process_counter    =   2;
                        end
                    end
                    2: begin
                        _process_counter    =   3;
                        _serial_clock       =   0;
                    end
                    3: begin
                        _state              =   post_state;
                        _process_counter    =   0;
                    end
                endcase
            end
        end
        S_SEND_STOP: begin
            if (divider_tick) begin
                case (process_counter)
                    0: begin
                        _serial_clock       =   1;
                        _process_counter    =   1;
                    end
                    1: begin
                        if (external_serial_clock == 1) begin
                            _process_counter    =   2;
                        end
                    end
                    2: begin
                        _process_counter    =   3;
                        _serial_data        =   1;
                    end
                    3: begin
                        _state  =   S_IDLE;
                    end
                endcase
            end
        end
    endcase
    // Release the bus if a target holds SCL low indefinitely. This reports
    // failure; it cannot clear a physical short or guarantee bus recovery.
    if (busy && transaction_age == TIMEOUT_CYCLES - 1) begin
        _transaction_error = 1;
        _state = S_IDLE;
        _busy = 0;
        _process_counter = 0;
        _serial_clock = 1;
        _serial_data = 1;
    end
end

always_ff @(posedge clock) begin
    if (!reset_n) begin
        transaction_error       <=  0;
        transaction_age         <=  0;
        state                   <=  S_IDLE;
        post_state              <=  S_IDLE;
        process_counter         <=  0;
        bit_counter             <=  0;
        last_acknowledge        <=  0;
        miso_data               <=  {8'd0, 8'd0};
        saved_read_write        <=  0;
        divider_counter         <=  0;
        saved_device_address    <=  0;
        saved_register_address  <=  0;
        saved_mosi_data         <=  0;
        serial_clock            <=  0;
        serial_data             <=  0;
        saved_mosi_data         <=  0;
        post_serial_data        <=  0;
        busy                    <=  0;
        saved_use_16_bit        <=  0;
    end
    else begin
        transaction_error       <=  _transaction_error;
        if (!busy || !_busy) transaction_age <= 0;
        else transaction_age <= transaction_age + 1'b1;
        state                   <=  _state;
        post_state              <=  _post_state;
        process_counter         <=  _process_counter;
        bit_counter             <=  _bit_counter;
        last_acknowledge        <=  _last_acknowledge;
        miso_data               <=  _miso_data;
        saved_read_write        <=  _saved_read_write;
        divider_counter         <=  _divider_counter;
        saved_device_address    <=  _saved_device_address;
        saved_register_address  <=  _saved_register_address;
        saved_mosi_data         <=  _saved_mosi_data;
        serial_clock            <=  _serial_clock;
        serial_data             <=  _serial_data;
        post_serial_data        <=  _post_serial_data;
        busy                    <=  _busy;
        saved_use_16_bit        <= _saved_use_16_bit;
    end
 end


endmodule
