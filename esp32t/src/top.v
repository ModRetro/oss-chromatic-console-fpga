// top.v


module top #(
    parameter ISSIMU=0,
    // USB capture default: 1 = 320x288, 0 = native 160x144.
    // The host can explicitly select either resolution regardless of this.
    parameter UVC_DEFAULT_SCALE_2X=1'b1
)
(
    output              ADC_SEL,
    output              AUD_BCLK,
    output              AUD_DIN,
    output              AUD_MCLK,
    output              AUD_RESET,
    output              AUD_WCLK,

    input               BTN_A,
    input               BTN_B,
    input               BTN_DPAD_DOWN,
    input               BTN_DPAD_LEFT,
    input               BTN_DPAD_RIGHT,
    input               BTN_DPAD_UP,
    input               BTN_MENU,
    input               BTN_SEL,
    input               BTN_START,

    output  [15:0]      CART_A,
    output              CART_CLK,
    output              CART_CS,
    inout   [7:0]       CART_D,
    output              CART_RD,
    inout               CART_RST,
    output              CART_WR,
    output              CART_DATA_DIR_E,
    output              CART_CTRL_OE, // active-high cartridge shifter enable (new boards)
    output              CART_PWR_EN,
    input               CART_DET,
    input               CART_AUDIN,

    input               CLK_FPGA,       // 33.55432MHz
    input               CLK_27MHz,
    input               CLK_24MHz,

    output reg          ESP32_EN,

    output              SDIO_LS,
    input               POWER_ON_FPGA,
    output              POWER_DOWN_IO,
//    input               VBUS_DET,  // unused pin

    output reg          ESP32_IO0,

    output              I2S_BCLK,       // D16 IO33
    input               I2S_WS,         // D15 IO25 CC
    input               I2S_DIN,        // D14 IO26
    input               I2S_DOUT,       // D13 IO27
    input               ESP32_MCU_D12,  // D12 IO9
    output              ESP32_MCU_D11,  // D11 IO10 CC
    input               QSPI_CS,        // CS D10 IO5 CC
    input               QSPI_CLK,       // CLK D9 IO18 CC
    input               QSPI_MOSI,      // D D8 IO23
    input               QSPI_MISO,      // Q D7 IO19
    input               QSPI_WP,        // WP D6 IO22
    input               QSPI_HD,        // HD D5 IO21 CC
    output  reg         ESP32_MCU_D4,   // RXD
    input               ESP32_MCU_D3,   // TXD

    output              FPGA_LED_EN,
    output  reg         FPGA_LED_R,
    output  reg         FPGA_LED_G,
    output  reg         FPGA_LED_B,


    input               IR_RX,
    output              IR_LED,

    output              LCD_PWM,

    output [5:0]        LCD_DB,
    output              LCD_DOTCLK,
    output              LCD_ENABLE,
    output              LCD_HSYNC,
    output              LCD_RESET,
    output              LCD_SPI_CSX,
    output              LCD_SPI_SCLK,
    output              LCD_SPI_SDA,
    input               LCD_TE,
    output              LCD_VSYNC,

    inout               LINK_CLK,
    output              LINK_CLK_DIR_LV, // controls data flow in level shifter    
    input               LINK_IN,
    output              LINK_OUT,
    input               LINK_SD,  // changed from output to input, 
//     output              LINK_SD,
    output              LINK_SD_DIR_LV,  // 


    output              PS_CE_N,
    output              PS_CLK,
    inout   [7:0]       PS_DQ,
    inout               PS_DQS,

    inout               SCL,
    inout               SDA,

//    input               USBC_FLIP,  // unused signal
    inout               usb_dxp_io,
    inout               usb_dxn_io,
    input               usb_rxdp_i,
    input               usb_rxdn_i,
    output              usb_pullup_en_o,
    inout               usb_term_dp_io,
    inout               usb_term_dn_io,

    input               VBAT_ADC_P,
    input               VBAT_ADC_N,

    input               VERSION_DET, // discriminates between versions
    input               VERSION_DET2,
    input               DISPLAY_ID,
    output              CHG_EN_FPGA
);


// ---------------------------------------------------------------
// 'POWER_ON_FPGA` high when chromatic powered off USB but
// power switch off.  
//
// In this state, need to enable the USB charger if LiPo battery
// connected
// ---------------------------------------------------------------


    wire [7:0] temperature;
    wire emulator_was_reset; // signal from emulator core, indicating a reset took place
    wire appear_off = emulator_was_reset | POWER_ON_FPGA; // turn stuff off , alternatively could set CART_RST = ~POWER_ON_FPGA ...

    // Cartridge power and isolation are sequenced below, independently of
    // emulator/menu resets and USB activity.

// SD link not actively used, configure so that FPGA side is always an input
// nothing connected to SD card => open (high impedance)
// L (1'b0): B to A  
// H (1'b1): A to B
//
// A-side connected to FPGA, B-side connected to upstream components.
    assign LINK_SD_DIR_LV = 1'b0; 
////////////// 

    assign POWER_DOWN_IO = 1'bZ;
    assign SDIO_LS = 1'd1;

    wire    BIST_failed;
    wire    BIST_finished;

    assign FPGA_LED_EN = !POWER_ON_FPGA;

    wire lock_o;

    wire fClk;
    wire pClk;
    wire hClk;
    wire gClk;
    wire xClk;


    Gowin_PLL u_Gowin_PLL(
        .reset(1'd0),//input reset
        .clkout0(fClk), //output clkout0 ~150MHz
        .clkout1(pClk), //output clkout1 ~33.554MHz
        .clkout2(hClk), //output clkout2 ~16.777MHz
        .clkout3(gClk), //output clkout3 ~8.388MHz
        .clkout4(xClk), //output clkout4 ~75MHz
//        .clkout5(hdmiclk), //output clkout4 ~75MHz
        .lock(lock_o), //output lock
        .clkin(CLK_FPGA) //input clkin
    );

    reg [22:0] secondCounter = 'd0;
    reg secondEna;
    reg halfSecondEna;
    reg [16:0] percentCounter = 'd0;
    reg percentEna;

    always@(posedge gClk) begin
        percentEna <= 1'b0;
        if (percentCounter == 83886) begin
            percentEna     <= 1'b1;
            percentCounter <= 17'd0;
        end else begin
            percentCounter <= percentCounter + 1'd1;
        end

        secondEna      <= 1'b0;
        halfSecondEna  <= 1'b0;
        if (secondCounter == 4194303) begin
            halfSecondEna  <= 1'b1;
        end
        if (secondCounter == 8388607) begin
            secondEna      <= 1'b1;
            halfSecondEna  <= 1'b1;
            secondCounter  <= 23'd0;
            percentCounter <= 17'd0;
        end else begin
            secondCounter <= secondCounter + 1'd1;
        end

    end


// ================================================================================
// Latch Cart RST. 
// 
// Monitor the high-impedance CART_RST signal.  Should stay high ordinarily.  
// Reset the Gameboy core in emu_system_top, if CART_RST goes low as it could be
// imply an issue. 
//
// If CART_RST deasserts, latch it and maintain an active low reset for 256 clock
// cycles.  This "latched_cart_rst_n" feeds the gameboy core reset.
// =================================================================================
`define ENABLE_CART_RST_MONITOR
`ifdef ENABLE_CART_RST_MONITOR

//
//    reg [7:0] rst_counter;
    reg [3:0] rst_counter;
    reg       timeout_done;
    reg [1:0] cart_rst_sync;
    reg       latched_cart_rst_n;
    always@(posedge xClk or negedge CART_RST) begin
        if(!CART_RST) begin
            timeout_done <= 1'b0;
            cart_rst_sync <= 2'b00;
            rst_counter <= 4'h0;
        end else begin
            if (rst_counter < 4'hF/*8'hff*/) begin
                rst_counter <= rst_counter + 1;
            end else begin
                timeout_done <= 1'b1;
            end
            cart_rst_sync <= {cart_rst_sync[0],timeout_done};
        end
    end
    assign latched_cart_rst_n = cart_rst_sync[1];


`else 
    wire latched_cart_rst_n = 1'b1;
`endif

//    localparam HALF_SECOND_XCLK_TIMER = 37_500_000;

    wire low_battery;
    wire boot_rom_enabled;
    wire LED_Green;
    wire LED_Red;
    wire LED_Yellow;
    wire LED_White;
    wire [7:0]  pmic_sys_status;



    always@(posedge xClk) begin

        if (~lock_o) begin 
            FPGA_LED_R <= 1'b1;
            FPGA_LED_B <= 1'b1;
            FPGA_LED_G <= 1'b1;  
        end
        else begin 

                // normal operations - switch on and/or not connected over USB
                if (LED_White) begin
                    FPGA_LED_R <= 1'd0; //1'd0;
                    FPGA_LED_B <= 1'd0; //1'd0;
                    FPGA_LED_G <= 1'd0;//1'd0;
                end else if (LED_Green) begin
                    FPGA_LED_R <= 1'd1;
                    FPGA_LED_B <= 1'd1;
                    FPGA_LED_G <= 1'd0;
                end else if (LED_Yellow) begin
                    FPGA_LED_R <= 1'd0;
                    FPGA_LED_B <= 1'd1;
                    FPGA_LED_G <= secondCounter[4];
                end else if (LED_Red) begin
                    FPGA_LED_R <= 1'd0;
                    FPGA_LED_B <= 1'd1;
                    FPGA_LED_G <= 1'd1;
                end else begin
                    FPGA_LED_R <= 1'd1;
                    FPGA_LED_B <= 1'd1;
                    FPGA_LED_G <= 1'd1;
                end

        end
    end

    wire [15:0]       hWrBurstQ;
    wire [15:0]       hWrBurstQ2;
    wire              hHsync;
    wire              hVsync;

    wire gb_lcd_clkena;
    wire [14:0] gb_lcd_data;
    wire [1:0] gb_lcd_mode;
    wire gb_lcd_on;
    wire gb_lcd_vsync;
    wire LCD_INIT_DONE;

    wire              hGBNewLine;
    wire [22:0]       hGBAddress;
    wire              hGBWrite;
    wire [15:0]       hGBData;
    wire capture_valid, capture_frame_start, capture_line_end;


    reg LCD_VSYNC_r1;
    always@(posedge gClk)
        LCD_VSYNC_r1 <= LCD_VSYNC;

    reg memrst = 1'd1;

    reg LCD_EN1;
    reg LCD_EN0;
    reg LCD_EN;
    wire qMenuInit;
    wire LCD_BACKLIGHT_INIT;
    always@(posedge gClk or posedge memrst) begin
        if(memrst) begin
            LCD_EN <= 1'd0;
            LCD_EN0 <= 1'd0;
            LCD_EN1 <= 1'd0;
        end else begin
            if(LCD_VSYNC&~LCD_VSYNC_r1) begin
                LCD_EN0 <= LCD_INIT_DONE & LCD_BACKLIGHT_INIT;
                LCD_EN1 <= LCD_EN0;
                LCD_EN  <= LCD_EN1;
            end
            // synthesis translate_off
            LCD_EN  <= 1'd1;
            // synthesis translate_on
        end
    end

    wire [31:0] debug_system;
    wire [15:0] system_control;
    wire [17:0] capture_pixel;
    wire menuDisabled;
    wire hDrawOSD;
    vid_system_top #(ISSIMU)
    u_vid_system_top(
        .appear_off (appear_off),
        .gClk(gClk),
        .hClk(hClk),
        .pClk(pClk),
        .reset(memrst ),    

        .BTN_MENU(menuDisabled),

        .LCD_DB(LCD_DB),  
        .capture_valid(capture_valid),
        .capture_frame_start(capture_frame_start),
        .capture_line_end(capture_line_end),
        .capture_pixel(capture_pixel),
        .LCD_DOTCLK(LCD_DOTCLK),
        .LCD_ENABLE(LCD_ENABLE),
        .LCD_HSYNC(LCD_HSYNC),
        .LCD_EN(LCD_EN),
        .LCD_RESET(LCD_RESET), 
        .LCD_SPI_CSX(LCD_SPI_CSX),
        .LCD_SPI_SCLK(LCD_SPI_SCLK),
        .LCD_SPI_SDA(LCD_SPI_SDA),
        .LCD_TE(LCD_TE),
        .LCD_VSYNC(LCD_VSYNC),
        .LCD_GENLOCK(),

        .frameBlendEnable(system_control[1]),
        .colorCorrectionEnableLCD(system_control[2]),
        .colorCorrectionEnableUVC(system_control[3]),
        .voltageLow(low_battery),
        .lowBattDispMode(system_control[14:13]),
        .showTimer(1'b0), //system_control[8]),
        .runTimer(system_control[9]),
        .resetTimer(system_control[10]),
        .gSecondEna(secondEna),
        .gPercentEna(percentEna),
        .debug_system(debug_system),
        .debug_system_on(1'b0),

        .hDrawOSD(hDrawOSD),
        .hGBNewLine(hGBNewLine),
        .hGBAddress(hGBAddress),
        .hGBWrite(hGBWrite),
        .hGBData(hGBData),

        .hHsync(hHsync),
        .hVsync(hVsync),
        .hWrBurstQ(hWrBurstQ),
        .hWrBurstQ2(hWrBurstQ2),

        .LCD_INIT_DONE(LCD_INIT_DONE),
        .gb_lcd_clkena(gb_lcd_clkena), 
        .gb_lcd_mode(gb_lcd_mode),
        .gb_lcd_on(gb_lcd_on),   
        .gb_lcd_vsync(gb_lcd_vsync), 
        .gb_lcd_data(gb_lcd_data)
    );



    wire [15:0] left, right;
    wire [7:0]  volume;
    wire        hHeadphones;

    aud_system_top_8_16 u_aud_system_top(     
        .VERSION_DET (VERSION_DET),
        .appear_off (appear_off),
        .gClk(gClk),
        .hClk(hClk),
        .reset_n(lock_o),
        .left(left),
        .right(right),

        .AUD_BCLK(AUD_BCLK),
        .AUD_DIN(AUD_DIN),
        .AUD_DOUT(1'b0), // Codec return audio is unused.
        .AUD_MCLK(AUD_MCLK),
        .AUD_RESET(AUD_RESET),
        .AUD_WCLK(AUD_WCLK),

        .software_mute(system_control[0]),
        .pmic_sys_status(pmic_sys_status),
        .volume(volume),
        .temperature(temperature),
        .hHeadphones(hHeadphones),
        .SCL(SCL),
        .SDA(SDA),
        .POWER_ON_FPGA (POWER_ON_FPGA)
//        .use_16_bit (use_16_bit)
    );    

// =====================================================================
// Previously, both of these clocked processes used "xClk".
// Using the higher frequency "fClk" domain removed recovery timing
// violations without impacting functionality
// =====================================================================
    reg [17:0] CART_DET_sr;
    always@(posedge fClk)
        CART_DET_sr <= {CART_DET_sr[16:0], CART_DET};

    // CART_DET = 0 (no cart inserted)
    always@(posedge fClk or negedge lock_o)
        if(~lock_o)
            memrst <= 1'd1;
        else
            memrst <= CART_DET_sr[17:2] == 16'h7FFF || CART_DET_sr[17:2] == 16'h8000;

    mem_system_top #(ISSIMU)
    u_mem_system_top
    (
        .xClk(xClk),
        .fClk(fClk),
        .hClk(hClk),
        .reset (memrst), 
        .QSPI_CLK(QSPI_CLK),
        .QSPI_MOSI(QSPI_MOSI),
        .QSPI_MISO(QSPI_MISO),
        .QSPI_CS(QSPI_CS),
        .QSPI_WP(QSPI_WP),
        .QSPI_HD(QSPI_HD),

        .PS_CE_N(PS_CE_N),
        .PS_CLK(PS_CLK),
        .PS_DQ(PS_DQ),
        .PS_DQS(PS_DQS),

        .BIST_failed(BIST_failed),
        .BIST_finished(BIST_finished),
        .qMenuInit(qMenuInit),
        .hGBNewLine(hGBNewLine),
        .hGBAddress(hGBAddress),
        .hGBWrite(hGBWrite),
        .hGBData(hGBData),

        // mm_burst_read_to_stream
        .hValid(gb_lcd_clkena),
        .hHsync(gb_lcd_mode[1]),
        .hVsync(gb_lcd_vsync),
        .hWrBurstQ(hWrBurstQ),
        .hWrBurstQ2(hWrBurstQ2)
    );

    wire IR_RX_FILTER;

    wire lcd_on_int;
    wire lcd_off_overwrite;

    wire [8:0] MCU_buttons;
    
    //////////////////////////////////////////////// 
    // apply debounce logic to menu button
//    wire BTN_MENU_ored = BTN_MENU & ~MCU_buttons[8]; // BTN_MENU is low active


    wire nBTN_MENU_filtered;
    wire nBTN_MENU = ~BTN_MENU;
    button_debouncer debouncer_MENU     (gClk, nBTN_MENU     , nBTN_MENU_filtered     );
    wire BTN_MENU_filtered = ~nBTN_MENU_filtered & ~MCU_buttons[8];
    //////////////////////////////////////////////// 
    wire BTN_A_filtered;
    wire BTN_B_filtered;
    wire BTN_DPAD_DOWN_filtered;
    wire BTN_DPAD_LEFT_filtered;
    wire BTN_DPAD_RIGHT_filtered;
    wire BTN_DPAD_UP_filtered;
    wire BTN_SEL_filtered;
    wire BTN_START_filtered;

    button_debouncer debouncer_A         (gClk, BTN_A         , BTN_A_filtered         );
    button_debouncer debouncer_B         (gClk, BTN_B         , BTN_B_filtered         );
    button_debouncer debouncer_DPAD_DOWN (gClk, BTN_DPAD_DOWN , BTN_DPAD_DOWN_filtered );
    button_debouncer debouncer_DPAD_LEFT (gClk, BTN_DPAD_LEFT , BTN_DPAD_LEFT_filtered );
    button_debouncer debouncer_DPAD_RIGHT(gClk, BTN_DPAD_RIGHT, BTN_DPAD_RIGHT_filtered);
    button_debouncer debouncer_DPAD_UP   (gClk, BTN_DPAD_UP   , BTN_DPAD_UP_filtered   );
    button_debouncer debouncer_SEL       (gClk, BTN_SEL       , BTN_SEL_filtered       );
    button_debouncer debouncer_START     (gClk, BTN_START     , BTN_START_filtered     );

    wire [63:0] paletteBGIn;
    wire [63:0] paletteOBJ0In;
    wire [63:0] paletteOBJ1In;
    wire [2:0]  gbc_color_temp;
    wire gbc_mode;
    wire [63:0] gpd;



    wire cartridge_ready;
    wire [15:0] core_cart_a;
    wire [7:0] core_cart_d_in, core_cart_d_out;
    wire core_cart_clk, core_cart_cs, core_cart_rd, core_cart_wr;
    wire core_cart_data_dir_e;
    reg [1:0] cartridge_reset_sync = 2'b00;
    always @(posedge hClk or negedge lock_o)
        if (!lock_o) cartridge_reset_sync <= 2'b00;
        else cartridge_reset_sync <= {cartridge_reset_sync[0], 1'b1};

    cartridge_interface u_cartridge_interface (
        .clk(hClk),
        .reset_n(cartridge_reset_sync[1]),
        .cartridge_enable(~POWER_ON_FPGA),
        .version_detect(VERSION_DET),
        .cartridge_ready(cartridge_ready),
        .core_a(core_cart_a),
        .core_clk(core_cart_clk),
        .core_cs(core_cart_cs),
        .core_rd(core_cart_rd),
        .core_wr(core_cart_wr),
        .core_d_out(core_cart_d_out),
        .core_d_in(core_cart_d_in),
        .core_data_dir_e(core_cart_data_dir_e),
        .CART_A(CART_A),
        .CART_CLK(CART_CLK),
        .CART_CS(CART_CS),
        .CART_RD(CART_RD),
        .CART_WR(CART_WR),
        .CART_D(CART_D),
        .CART_RST(CART_RST),
        .CART_DATA_DIR_E(CART_DATA_DIR_E),
        .CART_CTRL_OE(CART_CTRL_OE),
        .CART_PWR_EN(CART_PWR_EN)
    );

    emu_system_top u_emu_system_top(
        .o_emulator_reset (emulator_was_reset),
        .hclk(hClk),
        .pclk(pClk),
        .fclk(fClk),
        .xclk(xClk), 
        .reset_n(~memrst),//lock_o),
        .POWER_GOOD(cartridge_ready),

        .customPaletteEna(paletteBGIn[63]),
        .paletteOff(system_control[12]),
        .paletteBGIn(paletteBGIn),
        .paletteOBJ0In(paletteOBJ0In),
        .paletteOBJ1In(paletteOBJ1In),
        .gbc_color_temp(gbc_color_temp),
        .gbc_mode(gbc_mode),
        .gpd(gpd),

        .BTN_NODIAGONAL(system_control[11]),
        .BTN_A(BTN_A_filtered | MCU_buttons[3]),
        .BTN_B(BTN_B_filtered | MCU_buttons[2]),
        .BTN_DPAD_DOWN(BTN_DPAD_DOWN_filtered | MCU_buttons[7]),
        .BTN_DPAD_LEFT(BTN_DPAD_LEFT_filtered | MCU_buttons[6]),
        .BTN_DPAD_RIGHT(BTN_DPAD_RIGHT_filtered | MCU_buttons[5]),
        .BTN_DPAD_UP(BTN_DPAD_UP_filtered | MCU_buttons[4]),

        .BTN_MENU(~BTN_MENU_filtered), // debounce menu button too
//         .BTN_MENU(~BTN_MENU_ored),

        .BTN_SEL(BTN_SEL_filtered | MCU_buttons[1]),
        .BTN_START(BTN_START_filtered | MCU_buttons[0]),
        .MENU_CLOSED(menuDisabled),

        .CART_A(core_cart_a),
        .CART_CLK(core_cart_clk),
        .CART_CS(core_cart_cs),
        .CART_D_IN(core_cart_d_in),
        .CART_D_OUT(core_cart_d_out),
        .CART_RD(core_cart_rd),
        .CART_WR(core_cart_wr),
        .CART_DATA_DIR_E(core_cart_data_dir_e),

        .IR_RX(IR_RX),
        .IR_LED(IR_LED),    

        .LINK_CLK(LINK_CLK),
        .LINK_CLK_DIR_LV (LINK_CLK_DIR_LV), // control direction of clock through core
        .LINK_IN(LINK_IN),
        .LINK_OUT(LINK_OUT),

        .lcd_on_int(lcd_on_int),
        .lcd_off_overwrite(lcd_off_overwrite),

        .boot_rom_enabled(boot_rom_enabled),

        // audio
        .left(left),
        .right(right),
        // video
        .LCD_INIT_DONE(LCD_INIT_DONE),
        .gb_lcd_clkena(gb_lcd_clkena),
        .gb_lcd_mode(gb_lcd_mode),
        .gb_lcd_on(gb_lcd_on),
        .gb_lcd_vsync(gb_lcd_vsync),
        .gb_lcd_data(gb_lcd_data),   

        .latched_cart_rst_n (latched_cart_rst_n)   
    );

    reg UART_TXD;
    wire UART_RXD;
    wire PHY_CLKOUT;
    wire usblocked;
    always@(posedge PHY_CLKOUT or negedge usblocked)
    begin
        if(~usblocked)
        begin
            UART_TXD     <= 1'd1;
            ESP32_MCU_D4 <= 1'd1;
        end
        else
        begin
            UART_TXD     <= ESP32_MCU_D3;
            ESP32_MCU_D4 <= UART_RXD;
        end
    end
    wire UART_DTR;
    wire UART_RTS;
    wire [1:0] DTRRTS = {UART_DTR, UART_RTS};



    reg [11:0] ESP_BOOT_DELAY_COUNTER = 0;
    reg [7:0] ESP_BOOT_DELAY_SHIFT = 0;


    reg ESP32_EN_INT = 1;
    reg ESP32_IO0_INT = 1;

    // 8MHz clock
    always@(posedge gClk) begin

        ESP32_IO0 <= ESP32_IO0_INT;

        ESP_BOOT_DELAY_COUNTER <= ESP_BOOT_DELAY_COUNTER + 1'b1;

        if(ESP_BOOT_DELAY_COUNTER == 0) begin
            ESP_BOOT_DELAY_SHIFT <= {ESP_BOOT_DELAY_SHIFT[6:0], ESP32_EN_INT};
            ESP32_EN <= ESP_BOOT_DELAY_SHIFT[7];
           end

        if(~ESP32_EN_INT) begin
            ESP_BOOT_DELAY_SHIFT <= 8'b0;
            ESP32_EN <= 0;
        end
    end

    always@(posedge PHY_CLKOUT or negedge usblocked)
    begin
        if(~usblocked)
        begin
            ESP32_EN_INT <= 1'd1;
            ESP32_IO0_INT <= 1'd1;
        end
        else
        begin
            ESP32_EN_INT <= ~UART_RTS;
            ESP32_IO0_INT <= (DTRRTS == 2'b00);
        end
    end

    wire clk24;
    wire [7:0] debugs;

    reg [23:0] usbinitcnt;
    reg usbrst = 1'd1;

    // 8388607 = 1s
    always@(posedge gClk or negedge lock_o)
        if(~lock_o)
        begin
            usbinitcnt <= 'd0;
            usbrst     <= 1'd1;
        end
        else
            if(usbinitcnt < 8388607)
            begin
                usbinitcnt <= usbinitcnt + 1'd1;
                usbrst <= 1'd1;
            end
            else
                usbrst <= 1'd0;

    usbuvcuart_top #(.DEFAULT_SCALE_2X(UVC_DEFAULT_SCALE_2X)) u_usb_top(
        .CLK_24MHz(CLK_24MHz),
        .ERST(usbrst | POWER_ON_FPGA),   // hold in reset while switch in off position
        .pClk(PHY_CLKOUT),
        .usblocked(usblocked),
        .hClk(gClk),

        .UART_TXD(UART_RXD), // output
        .UART_RXD(UART_TXD), // input
        .UART_CTS(1'b0), // Active-low CTS: hardware flow control unused.
        .E_UART_DTR(UART_DTR), // used for ESP32_EN
        .E_UART_RTS(UART_RTS), // used for ESP32_IO0 (bootloader select)

        .left(left),
        .right(right),

        .video_clk(hClk),
        .video_valid(capture_valid),
        .video_frame_start(capture_frame_start),
        .video_line_end(capture_line_end),
        .video_pixel(capture_pixel),
        .debugs(debugs),
        .playerNum({4'd0, system_control[7:4]}),
        .usb_dxp_io(usb_dxp_io),
        .usb_dxn_io(usb_dxn_io),
        .usb_rxdp_i(usb_rxdp_i),
        .usb_rxdn_i(usb_rxdn_i),
        .usb_pullup_en_o(usb_pullup_en_o),
        .usb_term_dp_io(usb_term_dp_io),
        .usb_term_dn_io(usb_term_dn_io)
    );

    wire [13:0] hAdcValue_r1;
    wire hAdcReq_ext;
    wire hAdcReady_r1;
    adc_wrap u_adc_wrap(
        .clk(gClk),
        .reset_n(lock_o),
        .hAdcReq_ext(hAdcReq_ext),
        .hAdcValue_r1(hAdcValue_r1),
        .hAdcReady_r1(hAdcReady_r1),
        .VBAT_ADC_P(VBAT_ADC_P),
        .VBAT_ADC_N(VBAT_ADC_N)
    );

    wire [7:0]  uart_tx_data;
    wire        uart_tx_busy;
    wire        uart_tx_val;

    wire [15:0] uart_rx_data;
    wire        uart_rx_val;

//////////////////////////////////////////////// 
// modify based on addition of debounce logic
//    wire menu_gated = qMenuInit&(CART_DET_sr[6:3]==4'b1111) ? BTN_MENU_ored : 1'b1;
    wire menu_gated = qMenuInit&(CART_DET_sr[6:3]==4'b1111) ? BTN_MENU_filtered : 1'b1;
////////////////////////////////////////////////

// --------------------------------------------------------------
// Enable the USB charger when the Chromatic is powered with LiPo,
// 
// however, need to wait for charger to be fully configured (I2C)
// --------------------------------------------------------------
    
   wire powered_by_lipo;
   assign CHG_EN_FPGA = 1'b1; //powered_by_lipo;


    system_monitor u_system_monitor(
        .appear_off (appear_off),
        .clk(gClk),
        .reset(~lock_o),
        .BTN_A(BTN_A_filtered),
        .BTN_B(BTN_B_filtered),
        .BTN_DPAD_DOWN(BTN_DPAD_DOWN_filtered),
        .BTN_DPAD_LEFT(BTN_DPAD_LEFT_filtered),
        .BTN_DPAD_RIGHT(BTN_DPAD_RIGHT_filtered),
        .BTN_DPAD_UP(BTN_DPAD_UP_filtered),
        .BTN_MENU(menu_gated),
        .BTN_SEL(BTN_SEL_filtered),
        .BTN_START(BTN_START_filtered),
        .menuDisabled(menuDisabled),
        .LCD_BACKLIGHT_INIT(LCD_BACKLIGHT_INIT),
        .LCD_INIT_DONE(LCD_INIT_DONE & ~boot_rom_enabled),
        .LCD_PWM(LCD_PWM),
        .hAdcReq_ext(hAdcReq_ext),
        .hAdcValue_r1(hAdcValue_r1),
        .hAdcReady_r1(hAdcReady_r1),
        .ADC_SEL(ADC_SEL),
        .hButtons(9'd0),
        .MCU_buttons(MCU_buttons),
        .hVolume(volume[6:0]),
        .pmic_sys_status(pmic_sys_status),
        .temperature(temperature),
        .hHeadphones(hHeadphones),
        .gSecondEna(secondEna),
        .gHalfSecondEna(halfSecondEna),
        .debug_system(debug_system),
        .low_battery(low_battery),
        .LED_Green(LED_Green),
        .LED_Red(LED_Red),
        .LED_Yellow(LED_Yellow),
        .LED_White(LED_White),
        .system_control(system_control),
        .paletteBGIn(paletteBGIn),
        .paletteOBJ0In(paletteOBJ0In),
        .paletteOBJ1In(paletteOBJ1In),
        .gbc_color_temp(gbc_color_temp),
        .gbc_mode(gbc_mode),
        .gpd(gpd),
        .uart_rx_data(uart_rx_data[7:0]),
        .uart_rx_val(uart_rx_val),
        .uart_tx_busy(uart_tx_busy),
        .uart_tx_data(uart_tx_data),
        .uart_tx_val(uart_tx_val),
  
        .VERSION_DET (VERSION_DET),
        .POWERED_BY_LIPO (powered_by_lipo)
    );

    UART2
    #(.CLK_FREQ(30'd8388608))
    u_UART2
    (
        .CLK(gClk), // clock
        .RST(~lock_o), // reset
        // UART INTERFACE
        .UART_TXD(ESP32_MCU_D11), //output
        .UART_RXD(ESP32_MCU_D12), //input
        .UART_RTS(), //output // when UART_RTS = 0, UART This Device Ready to receive.
        .UART_CTS(1'd0), //input// when UART_CTS = 0, UART Opposite Device Ready to receive.
        // UART Control Reg
        .BAUD_RATE(32'd115200), //input 32
        .PARITY_BIT(8'd0), // input 8
        .STOP_BIT(8'd0), // input 8
        .DATA_BITS(8'd8), // input 8
        // USER DATA INPUT INTERFACE
        .TX_DATA({8'd0, uart_tx_data}), //input 16
        .TX_DATA_VAL(uart_tx_val), //input 1 when TX_DATA_VAL = 1, data on TX_DATA will be transmit, DATA_SEND can set to 1 only when BUSY = 0
        .TX_BUSY(uart_tx_busy), //output when BUSY = 1 transiever is busy, you must not set DATA_SEND to 1
        // USER FIFO CONTROL INTERFACE
        .RX_DATA(uart_rx_data), //output 16
        .RX_DATA_VAL(uart_rx_val)//output
    );

    assign I2S_BCLK = menuDisabled;

endmodule
