//
// File name          :uart.v
// Module name        :uart.v
// Created by         :GaoYun Semi
// Author             :(Winson)
// Created On         :2020-11-05 14:26 GuangZhou
// Last Modified      :
// Update Count       :2020-11-05 14:26
// Description        :
//----------------------------------------------------------------------
//===========================================
module UART 
#(    parameter CLK_FREQ    = 30'd60000000 // set system clock frequency in Hz
      //parameter BAUD_RATE   = 4000000   // baud rate value
     // parameter P_PARITY_BIT  = "none"   // legal values: "none", "even", "odd", "mark", "space"
)
(
    input              CLK        , // clock
    input              RST        , // reset
        // UART INTERFACE
    output             UART_TXD   ,
    input              UART_RXD   ,
    output             UART_RTS   , // when UART_RTS = 0, UART This Device Ready to receive.
    input              UART_CTS   , // when UART_CTS = 0, UART Opposite Device Ready to receive.
        // UART Control Reg
    input  [31:0]      BAUD_RATE ,
    input  [7:0]       PARITY_BIT,
    input  [7:0]       STOP_BIT  ,
    input  [7:0]       DATA_BITS ,
        // USER DATA INPUT INTERFACE
    input   [15:0]     TX_DATA    , //
    input              TX_DATA_VAL, // when TX_DATA_VAL = 1, data on TX_DATA will be transmit, DATA_SEND can set to 1 only when BUSY = 0
    output             TX_BUSY    , // when BUSY = 1 transiever is busy, you must not set DATA_SEND to 1
        // USER FIFO CONTROL INTERFACE
    output  [15:0]     RX_DATA    , //
    output             RX_DATA_VAL  //
);


    reg  [3:0] uart_rxd_shreg     ;
    reg        uart_rxd_debounced ;
    reg  [3:0] uart_cts_shreg     ;
    reg        uart_cts_debounced ;
    wire       uart_tx_busy       ;
    reg  [1:0] div_correct;

    reg [23:0] divider_value;
    // -------------------------------------------------------------------------
    // UART RXD DEBAUNCER
    // -------------------------------------------------------------------------
    always @(posedge CLK or posedge RST) begin
        if (RST) begin
            uart_rxd_shreg <= 4'hF;
            uart_rxd_debounced <= 1'b1;
        end
        else begin
            uart_rxd_shreg <= {UART_RXD, uart_rxd_shreg[3:1]};
            uart_rxd_debounced <= uart_rxd_shreg[0]|uart_rxd_shreg[1]|uart_rxd_shreg[2]|uart_rxd_shreg[3];
        end
    end

    always @(posedge CLK or posedge RST) begin
        if (RST) begin
            uart_cts_shreg <= 4'hF;
            uart_cts_debounced <= 1'b1;
        end
        else begin
            uart_cts_shreg <= {UART_CTS, uart_cts_shreg[3:1]};
            uart_cts_debounced <= uart_cts_shreg[0]|uart_cts_shreg[1]|uart_cts_shreg[2]|uart_cts_shreg[3];
        end
    end

    assign UART_RTS  = 1'b0;
    assign TX_BUSY   = uart_tx_busy | UART_CTS;

    // -------------------------------------------------------------------------
    // UART TRANSMITTER
    // -------------------------------------------------------------------------
    UART_TX 
    //#( .P_PARITY_BIT (P_PARITY_BIT)) 
        uart_tx_inst (
            .CLK         (CLK         )
           ,.RST         (RST         )
            // UART INTERFACE
           //,.UART_CLK_EN (uart_clk_en )
           ,.UART_TXD    (UART_TXD    )
            // UART PARAMETER
           //,.UART_PARITY_BIT (UART_PARITY_BIT  )
           //,.UART_DATA_BIT   (UART_DATA_BIT    )
           ,.PARITY_BIT  (PARITY_BIT)
           ,.STOP_BIT    (STOP_BIT  )//0: 1 stop bit  1: 1.5 stop bit 2: 2 stop bit
           ,.DATA_BITS   (DATA_BITS )//5 6 7 8 16
           ,.DIVIDER_VALUE(divider_value )//16'd37
           ,.DIV_CORRECT(div_correct  )//16'd37

            // USER DATA INPUT INTERFACE
           ,.DATA_IN     (TX_DATA     )
           ,.DATA_SEND   (TX_DATA_VAL )
           ,.BUSY        (uart_tx_busy)
    );

    // -------------------------------------------------------------------------
    // UART RECEIVER
    // ------------------------------------------------------------------------- 
    UART_RX 
    #( .P_PARITY_BIT ("odd")) 
        uart_rx_inst (
            .CLK         (CLK                )
           ,.RST         (RST                )
           // UART INTERFACE
           //,.UART_CLK_EN (uart_clk_en        )
           ,.UART_RXD    (uart_rxd_debounced )
            // UART PARAMETER
           //,.UART_PARITY_BIT (UART_PARITY_BIT  )
           //,.UART_DATA_BIT (UART_DATA_BIT  )
           ,.PARITY_BIT  (PARITY_BIT )
           ,.STOP_BIT    (STOP_BIT   )//0: 1 stop bit  1: 1.5 stop bit 2: 2 stop bit
           ,.DATA_BITS   (DATA_BITS  )//5 6 7 8 16
           ,.DIVIDER_VALUE(divider_value)//
           ,.DIV_CORRECT(div_correct  )//16'd37
            // USER DATA INPUT INTERFACE
           ,.DATA_OUT    (RX_DATA    )
           ,.DATA_VLD    (RX_DATA_VAL)
           ,.FRAME_ERROR (           )
    );



    // Constant divisions are evaluated during elaboration, not in hardware.
    // Preserve the former IP's three fractional bits: its dividend was
    // CLK_FREQ*4, so the encoded result is floor(CLK_FREQ*32 / baud).
    // [28:5] supplies clocks per bit and [4:3] the quarter-clock correction.
    localparam [31:0] DIV_115200 = {CLK_FREQ, 5'b0} / 32'd115200;
    localparam [31:0] DIV_460800 = {CLK_FREQ, 5'b0} / 32'd460800;
    localparam [31:0] DIV_921600 = {CLK_FREQ, 5'b0} / 32'd921600;

    always @(posedge CLK or posedge RST) begin
        if (RST) begin
            divider_value <= DIV_115200[28:5];
            div_correct <= DIV_115200[4:3];
        end
        else begin
            // Unsupported requests use 115200. CDC GET_LINE_CODING still
            // reports the host's requested value; only these rates are supported.
            case (BAUD_RATE)
                32'd460800: begin
                    divider_value <= DIV_460800[28:5];
                    div_correct <= DIV_460800[4:3];
                end
                32'd921600: begin
                    divider_value <= DIV_921600[28:5];
                    div_correct <= DIV_921600[4:3];
                end
                default: begin
                    divider_value <= DIV_115200[28:5];
                    div_correct <= DIV_115200[4:3];
                end
            endcase
        end
    end
    

 
endmodule
