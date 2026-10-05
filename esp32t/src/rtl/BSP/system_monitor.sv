// system_monitor.v

module system_monitor(
    input               appear_off,
    input               clk,
    input               reset,
    input               BTN_A,
    input               BTN_B,
    input               BTN_DPAD_DOWN,
    input               BTN_DPAD_LEFT,
    input               BTN_DPAD_RIGHT,
    input               BTN_DPAD_UP,
    input               BTN_MENU, // pressed = 0
    input               BTN_SEL,
    input               BTN_START,
    // Controls external mux into ADC
    output  reg         menuDisabled,
    output  reg         ADC_SEL,
    output  reg         hAdcReq_ext,
    input               LCD_INIT_DONE,
    output  reg         LCD_PWM,
    output  reg         LCD_BACKLIGHT_INIT = 1'd0,
    input               hAdcReady_r1,
    input   [13:0]      hAdcValue_r1,
    input   [8:0]       hButtons,
    output  reg [8:0]   MCU_buttons,
    input   [6:0]       hVolume,
    input   [7:0]       pmic_sys_status,
    input   [7:0]       temperature,
    input               hHeadphones,
    input               gSecondEna,
    input               gHalfSecondEna,
    output  reg         low_battery,
    output  reg         LED_Green,
    output  reg         LED_Red,
    output  reg         LED_Yellow,
    output  reg         LED_White,
    output  reg [15:0]  system_control,
    output  reg [31:0]  debug_system,
    output  reg [63:0]  paletteBGIn,
    output  reg [63:0]  paletteOBJ0In,
    output  reg [63:0]  paletteOBJ1In,
    output  reg [2:0]   gbc_color_temp,
    input               gbc_mode,
    input   [63:0]      gpd,
    input   [7:0]       uart_rx_data,
    input               uart_rx_val,
    input               uart_tx_busy,
    output  [7:0]       uart_tx_data,
    output              uart_tx_val,

    input               VERSION_DET,
    output              POWERED_BY_LIPO
);

    localparam [1:0] PALETTE_HOTKEY_EVENT_NONE = 2'd0;
    localparam [1:0] PALETTE_HOTKEY_EVENT_UP   = 2'd1;
    localparam [1:0] PALETTE_HOTKEY_EVENT_DOWN = 2'd2;

    localparam NUM_CH = 10;
    wire [$clog2(NUM_CH)-1:0] tx_channel;
    wire write_done;

    wire    [6:0]   rx_address;
    wire    [79:0]  rx_data;
    wire            rx_data_val;

    reg [15:0] btnMenu_sr;
    reg btnMenu_r1;
    reg btnMenu_r2;

    reg [15:0] btnDown_sr;
    reg btnDown_r1;
    reg btnDown_r2;

    reg [15:0] btnUp_sr;
    reg btnUp_r1;
    reg btnUp_r2;

    reg [15:0] btnLeft_sr;
    reg btnLeft_r1;
    reg btnLeft_r2;

    reg [15:0] btnRight_sr;
    reg btnRight_r1;
    reg btnRight_r2;

    reg btnStart_r1;
    reg btnStart_r2;
    reg btnSelect_r1;
    reg btnSelect_r2;
    reg btnA_r1;
    reg btnA_r2;
    reg btnB_r1;
    reg btnB_r2;

    reg pressed;
    reg [3:0] brightness = 4'd3;
    reg [1:0] blockBrightnessReceive;

    reg request_buttons  = 1'b0;
    reg request_version  = 1'b0;
    reg updateBrightness = 1'b0;
    reg request_gpd     = 1'b0;

    reg lowpowerBacklight = 1'b0;
    reg [3:0] lowerpowerOldBL;
    reg request_SystemStatusExtended = 1'b0;
    reg [1:0] palette_hotkey_event = PALETTE_HOTKEY_EVENT_NONE;

    reg [13:0] volt;
    wire       bat_is_LI;

    // Raw ADC thresholds, selected by VERSION_DET (1=original, 0=V2).
    // Original warning values retain pre-v18.9 behavior. V2 values use
    // the MCU voltage conversion to match the same battery-bar levels.
    // Red LED and low-battery icon: approximately 20% AA / 17% LiPo.
    localparam [13:0] LOW_BATTERY_AA_ADC   = 14'd1071;
    localparam [13:0] LOW_BATTERY_LIPO_ADC = 14'd1182;
    localparam [13:0] LOW_BATTERY_AA_ADC_V2      = 14'd1118;
    localparam [13:0] LOW_BATTERY_LIPO_ADC_V2    = 14'd1238;

    // AA power-save entry and recovery; V2 matches the original meter levels.
    // Separate recovery threshold prevents toggling near the entry threshold.
    localparam [13:0] POWER_SAVE_ENTER_ADC = 14'd979;
    localparam [13:0] POWER_SAVE_EXIT_ADC  = 14'd1293;
    localparam [13:0] POWER_SAVE_ENTER_ADC_V2    = 14'd1019;
    localparam [13:0] POWER_SAVE_EXIT_ADC_V2     = 14'd1357;

    wire [13:0] low_battery_threshold = VERSION_DET
        ? (bat_is_LI ? LOW_BATTERY_LIPO_ADC : LOW_BATTERY_AA_ADC)
        : (bat_is_LI ? LOW_BATTERY_LIPO_ADC_V2 : LOW_BATTERY_AA_ADC_V2);
    wire [13:0] power_save_enter_threshold = VERSION_DET
        ? POWER_SAVE_ENTER_ADC : POWER_SAVE_ENTER_ADC_V2;
    wire [13:0] power_save_exit_threshold = VERSION_DET
        ? POWER_SAVE_EXIT_ADC : POWER_SAVE_EXIT_ADC_V2;

    always@(posedge clk or posedge reset)
    begin
        if(reset) begin
            system_control <= 16'd0;
            MCU_buttons    <= 9'd0;
            request_gpd   <= 1'b0;
            gbc_color_temp <= 3'd0;
            palette_hotkey_event <= PALETTE_HOTKEY_EVENT_NONE;
        end else begin
            request_buttons              <= 1'b0;
            request_version              <= 1'b0;
            updateBrightness             <= 1'b0;

            if (gHalfSecondEna) begin
               LCD_BACKLIGHT_INIT  <= 1'd1;
            end

            if(rx_data_val)
            begin
                if(rx_address == 7'hD) begin
                    request_gpd <= 1'b1;
                end
                if(rx_address == 7'hC) begin
                    if (rx_data[63]) begin
                        paletteOBJ1In <= rx_data[63:0];
                    end else begin
                        paletteOBJ0In <= rx_data[63:0];
                    end
                end
                if(rx_address == 7'hB) begin
                    paletteBGIn <= rx_data[63:0];
                end
                if(rx_address == 7'd9) begin
                    MCU_buttons <= rx_data[8:0];
                end
                if(rx_address == 7'd6) begin
                    request_version <= 1'b1;
                end
                if(rx_address == 7'd5) begin
                    if (blockBrightnessReceive == 2'd0) begin
                        brightness      <=  rx_data[13:0];
                    end else begin
                        blockBrightnessReceive <= blockBrightnessReceive - 1;
                    end
                end
                if(rx_address == 7'd4) begin
                    system_control  <=  rx_data[15:0];
                end
                if(rx_address == 7'hE) begin
                    // Keep this in sync with MCU fpga_tx.c kTxCmd_GBCColorTemp = 0xE.
                    // GBC color temperature level (len 2): [level][0x00]
                    gbc_color_temp <= (rx_data[15:8] != 8'd0 || rx_data[7:0] == 8'd0) ? rx_data[15:8] : rx_data[7:0];
                end
                if(rx_address == 7'd2) begin
                    request_buttons <= 1'b1;
                end
            end

            if (menuDisabled) begin
                if((btnLeft_sr[15:0] == 16'h8000)&&~btnMenu_r2) begin
                    if(brightness >= 1)
                    begin
                        brightness <= brightness - 9'd1;
                        pressed <= 1'd0;
                        blockBrightnessReceive <= 2'd3;
                        updateBrightness <= 1'b1;
                    end
                end
                if((btnRight_sr[15:0] == 16'h8000)&&~btnMenu_r2) begin
                    if(brightness != 15)
                    begin
                        pressed <= 1'd0;
                        brightness <= brightness + 9'd1;
                        blockBrightnessReceive <= 2'd3;
                        updateBrightness <= 1'b1;
                    end
                end
                if((btnUp_sr[15:0] == 16'h8000)&&~btnMenu_r2) begin
                    if (gbc_mode && (gbc_color_temp < 3'd5))
                    begin
                        gbc_color_temp <= gbc_color_temp + 3'd1;
                        request_SystemStatusExtended <= 1'b1;
                    end
                    else if (~gbc_mode)
                    begin
                        palette_hotkey_event <= PALETTE_HOTKEY_EVENT_UP;
                        request_SystemStatusExtended <= 1'b1;
                    end
                end
                if((btnDown_sr[15:0] == 16'h8000)&&~btnMenu_r2) begin
                    if (gbc_mode && (gbc_color_temp > 3'd0))
                    begin
                        gbc_color_temp <= gbc_color_temp - 3'd1;
                        request_SystemStatusExtended <= 1'b1;
                    end
                    else if (~gbc_mode)
                    begin
                        palette_hotkey_event <= PALETTE_HOTKEY_EVENT_DOWN;
                        request_SystemStatusExtended <= 1'b1;
                    end
                end
            end

            if (lowpowerBacklight) begin
               brightness       <= 4'd0;
               updateBrightness <= 1'b0;
            end

            if (volt >= 700) begin // ~1.8V
               if (~lowpowerBacklight && ~bat_is_LI && volt < power_save_enter_threshold) begin
                  request_SystemStatusExtended <= 1'b1;
                  lowpowerBacklight            <= 1'b1;
                  lowerpowerOldBL              <= brightness;
               end

               if (lowpowerBacklight && ~bat_is_LI && volt > power_save_exit_threshold) begin
                  request_SystemStatusExtended <= 1'b1;
                  lowpowerBacklight            <= 1'b0;
                  brightness                   <= lowerpowerOldBL;
               end
            end

            if (write_done && tx_channel == 9 && request_gpd) begin
                request_gpd <= 1'b0; // Clear after sending once
            end

            if (write_done && tx_channel == 8 && request_SystemStatusExtended) begin
                request_SystemStatusExtended <= 1'b0;
                palette_hotkey_event <= PALETTE_HOTKEY_EVENT_NONE;
            end

        end
    end

    reg menuDown = 1'b0;
    always@(posedge clk)
    begin
        if( reset | appear_off ) begin    // disable menu when appropriate, reset or appear off
            menuDisabled <= 1'b1;
            btnMenu_r1 <= 1'b1; // active-low button: released
            btnMenu_r2 <= 1'b1;
        end else begin
            btnMenu_r1 <= BTN_MENU;
            btnMenu_r2 <= btnMenu_r1;
            btnMenu_sr <= {btnMenu_sr[14:0], btnMenu_r2};
            if(btnMenu_sr[15:0] == 16'h8000) begin
               menuDown <= 1'b1;
            end
            if(btnMenu_sr[15:0] == 16'h7FFF && menuDown) begin
               menuDisabled <= ~menuDisabled;
               menuDown     <= 1'b0;
            end

            if (btnA_r2 | btnB_r2 | btnDown_r2 | btnUp_r2 | btnLeft_r2 | btnRight_r2 | btnSelect_r2 | btnStart_r2) menuDown <= 1'b0;

            btnDown_r1 <= BTN_DPAD_DOWN;
            btnDown_r2 <= btnDown_r1;
            btnDown_sr <= {btnDown_sr[14:0], btnDown_r2};

            btnUp_r1 <= BTN_DPAD_UP;
            btnUp_r2 <= btnUp_r1;
            btnUp_sr <= {btnUp_sr[14:0], btnUp_r2};

            btnLeft_r1 <= BTN_DPAD_LEFT;
            btnLeft_r2 <= btnLeft_r1;
            btnLeft_sr <= {btnLeft_sr[14:0], btnLeft_r2};

            btnRight_r1 <= BTN_DPAD_RIGHT;
            btnRight_r2 <= btnRight_r1;
            btnRight_sr <= {btnRight_sr[14:0], btnRight_r2};

            btnSelect_r1 <= BTN_SEL;
            btnSelect_r2 <= btnSelect_r1;

            btnStart_r1 <= BTN_START;
            btnStart_r2 <= btnStart_r1;

            btnA_r1 <= BTN_A;
            btnA_r2 <= btnA_r1;

            btnB_r1 <= BTN_B;
            btnB_r2 <= btnB_r1;

        end
    end

    reg [7:0] lcdcount;
    always@(posedge clk)
        if(lcdcount < 448)
            lcdcount <= lcdcount + 1'd1;
        else
            lcdcount <= 'd0;


    // control backlight through external signal, for example, tied to emulator reset
    always_comb begin 
        LCD_PWM = 1'b0;
        if (appear_off) begin 
            LCD_PWM = 1'b0;
        end 
        else begin // leave back light on
            LCD_PWM = LCD_INIT_DONE&LCD_BACKLIGHT_INIT ? (lcdcount <= {brightness[3:0], 4'd0}) : 1'd0;
        end
    end
//////    assign LCD_PWM = LCD_INIT_DONE&LCD_BACKLIGHT_INIT ? (lcdcount <= {brightness[3:0], 4'd0}) : 1'd0;


    // 8.388608Mhz clock -> ~119.2ns
    // 0.005s / 119.2ns = 41946

    localparam ADC_INTERVAL_CYCLES = 'd41946;
    reg [15:0] adc_timer;
    reg [9:0] startup_cnt;            // wait for ~4 seconds to have stable measurements
    reg signed [10:0] startup_select; // measure if AA or lithium is used, negative -> LI, positive -> AA
    reg startup_done = 1'b0;

    always@(posedge clk) begin
        if(adc_timer < ADC_INTERVAL_CYCLES) begin
            adc_timer <= adc_timer + 1'd1;
            hAdcReq_ext <= 'd0;
            // Toggle the mux slightly ahead of starting the measurement
            if (startup_done) begin
                ADC_SEL <= startup_select[10];
            end else if(adc_timer == ADC_INTERVAL_CYCLES - 1000) begin
                ADC_SEL <= ~ADC_SEL;
            end
        end else begin
            adc_timer <= 'd0;
            hAdcReq_ext <= 'd1;
        end
    end

   assign POWERED_BY_LIPO = bat_is_LI;   // bring to top level

   assign     bat_is_LI = startup_select[10];
   reg [21:0] volt_sum;
   reg [8:0]  volt_cnt;
   reg        transmitVolt;

   // Existing board-specific validity gate for battery LED/icon decisions.
   wire [13:0] VOLTAGE_1V8 = VERSION_DET ? 14'd700 : 14'd646;
   reg blink;

   always@(posedge clk or posedge reset) begin

      if(reset) begin
         low_battery    <= 1'd0;
         LED_Red        <= 1'd0;
         LED_Green      <= 1'd0;
         LED_Yellow     <= 1'd0;
         blink          <= 1'd0;
         volt           <= 14'd0;
         volt_sum       <= 22'd0;
         volt_cnt       <=  9'd0;
         startup_cnt    <= 11'd0;
         startup_select <= 11'd0;
         startup_done   <= 1'b0;
         transmitVolt   <= 1'b0;
      end else begin

         transmitVolt <= 1'b0;

         debug_system <= {1'd0 , startup_select,  6'd0, volt };

         if(hAdcReady_r1) begin
            if (~startup_cnt[9]) begin // wait for ~4 seconds to have stable measurements
               startup_cnt <= startup_cnt + 1'd1;
            end

            if (startup_done) begin // average values for determined type only
               volt_sum <= volt_sum + hAdcValue_r1;
               volt_cnt <= volt_cnt + 1;
            end else if (startup_cnt[9] && hAdcValue_r1 >= 700) begin // measure if AA or lithium is used, negative -> LI, positive -> AA
               if (ADC_SEL) begin
                  startup_select <= startup_select - 1'd1;
               end else begin
                  startup_select <= startup_select + 1'd1;
               end
            end

            if (startup_select > 11'sd127 || startup_select < -11'sd127) begin // determine type based on which delivered higher values for some seconds
               startup_done <= 1'b1;
            end
         end

         if (volt_cnt[8]) begin
            volt_sum    <= 22'd0;
            volt_cnt    <=  9'd0;
            volt        <= volt_sum[21:8];
            transmitVolt <= 1'b1;
         end

         if (gSecondEna) blink <= ~blink;

         low_battery <= 1'd0;
         LED_Red     <= 1'd0;
         LED_Green   <= 1'd0;
         LED_Yellow  <= 1'd0;
         LED_White   <= 1'd0;

        if (volt >= VOLTAGE_1V8) begin
//         if (volt >= 700) begin // ~1.8V

            if (pmic_sys_status[2]) begin // BQ24296M REG08 PG_STAT: input power good

               // REG08 CHRG_STAT[1:0]: 01=precharge, 10=fast charge,
               // 00=not charging, 11=charge complete. Do not infer charge
               // completion from the battery ADC; it can cross a voltage
               // threshold repeatedly near full charge.
               if (bat_is_LI && ((pmic_sys_status[5:4] == 2'b01) ||
                                 (pmic_sys_status[5:4] == 2'b10))) begin
                  LED_White   <= 1'd1;
               end

            end else begin

               if(volt < low_battery_threshold) begin
                  low_battery <= 1'd1;
                  if (blink) LED_Red <= 1'd1;
               end

            end

         end
      end
   end

    wire [6:0] tx_address;
    wire       write;


    wire [13:0] buttons = {
        4'd0,
        menuDisabled,
        ~btnMenu_r2, // use the gClk-staged menu state for the UART payload
        BTN_DPAD_DOWN,
        BTN_DPAD_LEFT,
        BTN_DPAD_RIGHT,
        BTN_DPAD_UP,
        BTN_A,
        BTN_B,
        BTN_SEL,
        BTN_START
    };


    reg [13:0] version = {
        1'd0,  // 1 bit reserved
        1'd0,  // 1 bit debug,
        6'd14, // 6 bits minor version
        6'd18  // 6 bits major version
    };


    wire [NUM_CH-1:0] channelsNewDataValid =
    {
        request_gpd,                                  // Game Palette Data
        ~menuDisabled | request_SystemStatusExtended, // System Status Extended
        ~menuDisabled,                                // reserved
        ~menuDisabled | request_version,              // version info
        ~menuDisabled,                                // pmic sys status
        ~menuDisabled,                                // System Control
        ~menuDisabled | updateBrightness,             // Audio + Brightness
        ~menuDisabled | request_buttons,              // Buttons
        (~menuDisabled & transmitVolt & bat_is_LI),   // Lithium
        (~menuDisabled & transmitVolt & ~bat_is_LI)   // AA
    };

    wire [13:0] audio_brightness = {2'd0, brightness, hHeadphones, hVolume};
    wire [13:0] mic_sys_status = {6'd0 , pmic_sys_status};

    wire [7:0] tx_byteCount = (tx_channel == 0) ? 8'd2 : // AA
                              (tx_channel == 1) ? 8'd2 : // Lithium
                              (tx_channel == 2) ? 8'd2 : // Buttons
                              (tx_channel == 3) ? 8'd2 : // Audio + Brightness
                              (tx_channel == 4) ? 8'd2 : // System Control
                              (tx_channel == 5) ? 8'd2 : // pmic sys status
                              (tx_channel == 6) ? 8'd2 : // version info
                              (tx_channel == 7) ? 8'd4 : // reserved
                              (tx_channel == 8) ? 8'd4 : // System Status Extended
                              (tx_channel == 9) ? 8'd8 : // BG Palette Data
                              8'd1;

    wire [7:0] tx_bytepos;

    // new PCB: VERSION_DET == 1'b0
    // old PCB: VERSION_DET == 1'b1
    // * previous version of firmware and FPGA design didn't use most significant bit in "tx_senddata"
    // * by default it's set to 0.  To maintain compatibility, a value of 0 should correspond to legacy
    // * so we store the negation of VERION_DET
    wire pcb_version = !VERSION_DET;
    
    // To avoid long logic delay, migrate toward parallel implementation via case statement, above.
    // Note that if the number of channels increases beyond 10, may need to adjust the static
    // width of the "tx_channel" below
    reg [7:0] tx_senddata;
    always_comb begin 
        tx_senddata = 8'd0;

        case ({tx_channel, tx_bytepos})
            // AA battery
            {4'd0, 8'd0}:    tx_senddata = {pcb_version, 1'd0, volt[13:8]}; 
            {4'd0, 8'd1}:    tx_senddata = volt[7:0];        
            // LiPo
            {4'd1, 8'd0}:    tx_senddata = {pcb_version, 1'd0, volt[13:8]}; 
            {4'd1, 8'd1}:    tx_senddata = volt[7:0]; 
            // Buttons
            {4'd2, 8'd0}:    tx_senddata = {2'd0, buttons[13:8]} ; 
            {4'd2, 8'd1}:    tx_senddata = buttons[7:0];    
            //Audio+Brightness
            {4'd3, 8'd0}:    tx_senddata = {2'd0, audio_brightness[13:8]}; 
            {4'd3, 8'd1}:    tx_senddata = audio_brightness[7:0];    
            // System Control
            {4'd4, 8'd0}:    tx_senddata = {2'd0, system_control[13:8]}; 
            {4'd4, 8'd1}:    tx_senddata = system_control[7:0];   
            // PMIC (NEED TO CORRECT TIMING VIOLATIONS HERE)
            {4'd5, 8'd0}:    tx_senddata = {2'd0, mic_sys_status[13:8]}; // pmic sys status
            {4'd5, 8'd1}:    tx_senddata = mic_sys_status[7:0];     
            // Version 
            {4'd6, 8'd0}:    tx_senddata = {2'd0, version[13:8]}; 
            {4'd6, 8'd1}:    tx_senddata = version[7:0];   
            // Reserved (temperature for testing purposes)
            {4'd7, 8'd0}:    tx_senddata = temperature[7:0];  // only care about integer part 
            {4'd7, 8'd1}:    tx_senddata = 8'd0;   
            {4'd7, 8'd2}:    tx_senddata = 8'd0; 
            {4'd7, 8'd3}:    tx_senddata = 8'd0;   
            // System status
            {4'd8, 8'd0}:    tx_senddata = {6'd0, gbc_mode, lowpowerBacklight}; 
            {4'd8, 8'd1}:    tx_senddata = {5'd0, gbc_color_temp};   
            {4'd8, 8'd2}:    tx_senddata = {6'd0, palette_hotkey_event}; 
            {4'd8, 8'd3}:    tx_senddata = 8'd0;   
            // Combined game palette
            {4'd9, 8'd0}:    tx_senddata = gpd[7:0]; 
            {4'd9, 8'd1}:    tx_senddata = gpd[15:8];   
            {4'd9, 8'd2}:    tx_senddata = gpd[23:16]; 
            {4'd9, 8'd3}:    tx_senddata = gpd[31:24];   
            {4'd9, 8'd4}:    tx_senddata = gpd[39:32]; 
            {4'd9, 8'd5}:    tx_senddata = gpd[47:40];   
            {4'd9, 8'd6}:    tx_senddata = gpd[55:48]; 
            {4'd9, 8'd7}:    tx_senddata = gpd[63:56];           

            default:         tx_senddata = 8'd0;
        endcase
    end

/*
    wire [7:0] tx_senddata = (tx_channel == 0 && tx_bytepos == 0) ? {pcb_version, 1'd0, volt[13:8]} : // AA, 
                             (tx_channel == 0 && tx_bytepos == 1) ? volt[7:0] :

                             (tx_channel == 1 && tx_bytepos == 0) ? {pcb_version, 1'd0, volt[13:8]} : // Lithium, 
                             (tx_channel == 1 && tx_bytepos == 1) ? volt[7:0] :

                             (tx_channel == 2 && tx_bytepos == 0) ? {2'd0, buttons[13:8]} : // Buttons
                             (tx_channel == 2 && tx_bytepos == 1) ? buttons[7:0] :

                             (tx_channel == 3 && tx_bytepos == 0) ? {2'd0, audio_brightness[13:8]} : // Audio + Brightness
                             (tx_channel == 3 && tx_bytepos == 1) ? audio_brightness[7:0] :

                             (tx_channel == 4 && tx_bytepos == 0) ? {2'd0, system_control[13:8]} : // System Control
                             (tx_channel == 4 && tx_bytepos == 1) ? system_control[7:0] :

                             (tx_channel == 5 && tx_bytepos == 0) ? {2'd0, mic_sys_status[13:8]} : // pmic sys status
                             (tx_channel == 5 && tx_bytepos == 1) ? mic_sys_status[7:0]  :

                             (tx_channel == 6 && tx_bytepos == 0) ? {2'd0, version[13:8]} : // version info
                             (tx_channel == 6 && tx_bytepos == 1) ? version[7:0] :

                             (tx_channel == 7 && tx_bytepos == 0) ? 8'd0 : // reserved
                             (tx_channel == 7 && tx_bytepos == 1) ? 8'd0 :
                             (tx_channel == 7 && tx_bytepos == 2) ? 8'd0 :
                             (tx_channel == 7 && tx_bytepos == 3) ? 8'd0 :

                             (tx_channel == 8 && tx_bytepos == 0) ? {6'd0, gbc_mode, lowpowerBacklight} : // System Status Extended
                             (tx_channel == 8 && tx_bytepos == 1) ? {5'd0, gbc_color_temp} :
                             // [1:0] palette hotkey event (one-shot): 0=none, 1=up, 2=down
                             (tx_channel == 8 && tx_bytepos == 2) ? {6'd0, palette_hotkey_event} :
                             (tx_channel == 8 && tx_bytepos == 3) ? 8'd0 :

                             (tx_channel == 9 && tx_bytepos == 0) ? gpd[7:0] : // Combined Game Palette Data
                             (tx_channel == 9 && tx_bytepos == 1) ? gpd[15:8] :
                             (tx_channel == 9 && tx_bytepos == 2) ? gpd[23:16] :
                             (tx_channel == 9 && tx_bytepos == 3) ? gpd[31:24] :
                             (tx_channel == 9 && tx_bytepos == 4) ? gpd[39:32] :
                             (tx_channel == 9 && tx_bytepos == 5) ? gpd[47:40] :
                             (tx_channel == 9 && tx_bytepos == 6) ? gpd[55:48] :
                             (tx_channel == 9 && tx_bytepos == 7) ? gpd[63:56] :
                             8'd0;
*/
    wire uartDisabled;

    system_monitor_arbiter
    #(
        .NUM_CH(NUM_CH)
    ) u_system_monitor_arbiter
    (
        .clk(clk),
        .reset(reset),
        .uartDisabled(uartDisabled),
        .menuDisabled(menuDisabled),
        .channelsNewDataValid(channelsNewDataValid),
        .uart_tx_busy(uart_tx_busy),
        .tx_address(tx_address),
        .tx_channel(tx_channel),
        .write_done(write_done),
        .write(write)
    );

    uart_packet_wrapper_tx u_uart_packet_wrapper_tx
    (
        .clk(clk),
        .reset(reset),
        .uart_tx_busy(uart_tx_busy),
        .uart_tx_data(uart_tx_data),
        .uart_tx_val(uart_tx_val),
        .uartDisabled(uartDisabled),
        .menuDisabled(menuDisabled),
        .write(write),
        .write_done(write_done),
        .tx_address(tx_address),
        .tx_byteCount(tx_byteCount),
        .tx_bytepos(tx_bytepos),
        .tx_senddata(tx_senddata)
    );

    uart_packet_wrapper_rx u_uart_packet_wrapper_rx
    (
        .clk(clk),
        .reset(reset),
        .uart_rx_val(uart_rx_val),
        .uart_rx_data(uart_rx_data),
        .uartDisabled(uartDisabled),
        .rx_address(rx_address),
        .rx_data(rx_data),
        .rx_data_val(rx_data_val)
    );

endmodule
