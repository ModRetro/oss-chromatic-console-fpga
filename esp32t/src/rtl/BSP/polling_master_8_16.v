// polling_master.v
// Poll TLV320 Audio codec
/// Read volume wheel value (Page0 R117 bits 6:0)
/// Read GPIO (headphone attached) value(Page0 R51 bit1)
//// Toggle headphone or speaker

// Poll BQ24296MRGER PMIC state
/// I2C address 0x6B
/// Write R05 = 0x8C (watchdog disabled; termination and safety timer enabled)
/// Write R02 = 0x45 (320mA nominal cold) or 0x20 (1024mA warm/legacy)
/// Read  R08 System Status Reg
/// Read  R09 New Fault Register

// Poll TMP112AIDRLR Temperature Sensor state
/// I2C address  0x48
//


// Poll ATSHA204A encryption

module polling_master_8_16#(
    parameter I2C_DATA_WIDTH = 8,
    parameter REGISTER_WIDTH = 8,
    parameter ADDRESS_WIDTH = 7,
    parameter integer TEMP_MAX_AGE_CYCLES = 16777216 // One second at hClk
)(
    input                                   clk,
    input                                   rst,
    input                                   i2c_busy,
    input                                   i2c_transaction_error,
    input                                   enable,
    input                                   mute,
    
    input       [15:0]                      i2c_miso_data,

    output  reg [7:0]                       volume,
    output  reg [7:0]                       gpio,
    output  reg [7:0]                       pmic_sys_status,
    output  reg [7:0]                       new_fault,
    output  reg [7:0]                       inlim,
    output  reg [7:0]                       chargeCurrent,

    output  reg [7:0]                       temperature,
 
    output  reg                             i2c_enable,
    output  reg                             i2c_read_write,
    output  reg     [I2C_DATA_WIDTH-1:0]    i2c_mosi_data,
    output  reg     [REGISTER_WIDTH-1:0]    i2c_register_address,
    output  reg     [ADDRESS_WIDTH-1:0]     i2c_device_address,
    output  reg                             use_16_bit,
    input  wire                             HAS_TEMPSENSOR
    
);
 
    reg [7:0] scount;
    reg [7:0] regindex;
    
    localparam CODEC = 7'h18;
    localparam PMIC = 7'h6B;
    localparam TEMP = 7'h48; //PMIC; 

    reg [15:0] state;
    localparam S_VOLUME       = 16'h0001;
    localparam S_HP_GPIO      = 16'h0002;
    localparam S_HP_EN0       = 16'h0004;
    localparam S_HP_EN1       = 16'h0008;
    localparam S_HP_SWPWRDOWN = 16'h0010;
    localparam S_HP_EN2       = 16'h0020;
    localparam S_HP_EN3       = 16'h0040;
    localparam S_HP_EN4       = 16'h0080;
    localparam S_SYS_STATUS   = 16'h0100;
    localparam S_NEW_FAULT    = 16'h0200;
    localparam S_INLIM        = 16'h0400;
    localparam S_CHARGEWRITE  = 16'h0800;
    localparam S_CHARGEREAD   = 16'h1000;
    localparam S_IDLE         = 16'h2000;
    localparam S_TEMPREAD     = 16'h4000;
    localparam S_WATCHDOG     = 16'h8000;
    // REG02: 512 mA offset plus 64 mA steps in bits [7:2].
    localparam CHARGE_LEGACY = 8'h20; // 1024 mA; no temperature sensor
    localparam CHARGE_COLD   = 8'h45; // 320 mA nominal: 1600 mA * 20%
    localparam CHARGE_WARM   = 8'h20; // 1024 mA (existing new-board setting)
    localparam CHARGE_TIMERS = 8'h8C; // Termination + 12-hour safety timer; no watchdog
    localparam TEMP_AGE_WIDTH = $clog2(TEMP_MAX_AGE_CYCLES + 1);
    reg [TEMP_AGE_WIDTH-1:0] temperature_age;
    reg temperature_valid;
    wire [7:0] requested_current = !HAS_TEMPSENSOR ? CHARGE_LEGACY :
        (!temperature_valid || temperature_age >= TEMP_MAX_AGE_CYCLES ||
         $signed(temperature) < 8'sd15) ? CHARGE_COLD : CHARGE_WARM;

    reg txActive;

    localparam TEMP_CONFIG = 8'h01;
    localparam TEMP_VALUE  = 8'h00; 

    reg [31:0] count;
    always@(posedge clk)
    begin
        if(rst)
        begin
            temperature          <= 8'd0;
            temperature_valid    <= 1'b0;
            temperature_age      <= 0;
            txActive             <= 1'b0;
            chargeCurrent        <= 8'd0;
            scount               <= 'd0;
            i2c_read_write       <= 'd0;
            i2c_register_address <= 'd0;
            i2c_mosi_data        <= 'd0;
            i2c_device_address   <= CODEC;
            i2c_enable           <= 'd0;
            regindex             <= 'd0;
            state                <= S_IDLE;
            use_16_bit           <= 1'b0;

        end
        else begin
            if (temperature_age < TEMP_MAX_AGE_CYCLES)
                temperature_age <= temperature_age + 1'b1;
            else
                temperature_valid <= 1'b0;

            case(state)
            S_IDLE:
            begin
                i2c_enable       <= 'd0;
                txActive         <= 1'd0;
                i2c_read_write   <= 'd1; // Read
                if(~i2c_busy && enable)
                begin
                    state                <= S_VOLUME;
                    i2c_device_address   <= CODEC;
                    i2c_register_address <= 8'd117; // Volume
                    use_16_bit           <= 1'b0;

                end
            end

            S_VOLUME:
            begin
                if(i2c_busy)
                begin
                    txActive         <= 1'd1;
                    i2c_enable       <= 'd0;
                end
                else
                    if(txActive)
                    begin
                        i2c_read_write   <= 'd1; // Read
                        state                <= S_HP_GPIO;
                        i2c_register_address <= 8'd51; // HP Status
                        i2c_device_address   <= CODEC;
                        volume               <= i2c_miso_data[7:0];
                        txActive             <= 1'd0;
                        use_16_bit           <= 1'b0;

                    end
                    else
                        i2c_enable       <= 'd1;
            end
            S_HP_GPIO:
            begin
                if(i2c_busy)
                begin
                    txActive         <= 1'd1;
                    i2c_enable       <= 'd0;
                end
                else
                    if(txActive)
                    begin
                        gpio                 <= i2c_miso_data[7:0];
                        state                <= S_HP_EN0;
                        i2c_read_write       <= 'd0; // Write
                        i2c_register_address <= 8'd00; // Page select
                        i2c_mosi_data        <= 8'd01; // Page 1
                        i2c_device_address   <= CODEC;
                        txActive             <= 1'd0;
                        use_16_bit           <= 1'b0;

                    end
                    else
                        i2c_enable           <= 'd1;
            end
            S_HP_EN0:
            begin
                if(i2c_busy)
                begin
                    txActive         <= 1'd1;
                    i2c_enable       <= 'd0;
                end
                else
                    if(txActive)
                    begin
                        state                <= S_HP_EN1;
                        i2c_read_write       <= 'd0; // Write
                        i2c_register_address <= 8'h26; // Left Analog Volume to SPK
                        if(gpio[1])
                            i2c_mosi_data        <= 8'h7F; // Mute Speaker (use headphones)
                        else
                            i2c_mosi_data        <= 8'h00; // Enable speaker (use speaker)
                        i2c_device_address   <= CODEC;
                        txActive             <= 1'd0;
                        use_16_bit           <= 1'b0;

                    end
                    else
                        i2c_enable           <= 'd1;
            end
            S_HP_EN1:
            begin
                if(i2c_busy)
                begin
                    txActive         <= 1'd1;
                    i2c_enable       <= 'd0;
                end
                else
                    if(txActive)
                    begin
                        state                <= S_HP_SWPWRDOWN;
                        i2c_read_write       <= 'd0; // Write
                        i2c_register_address <= 8'h1F; // Headphone Driver
                        if(gpio[1])
                            i2c_mosi_data        <= 8'hC4; // Enable driver (use headphones)
                        else
                            i2c_mosi_data        <= 8'h04; // 04 Disable driver (use speaker)

                        i2c_device_address   <= CODEC;
                        txActive             <= 1'd0;
                        use_16_bit           <= 1'b0;

                    end
                    else
                        i2c_enable           <= 'd1;
            end
            S_HP_SWPWRDOWN:
            begin
                if(i2c_busy)
                begin
                    txActive         <= 1'd1;
                    i2c_enable       <= 'd0;
                end
                else
                    if(txActive)
                    begin
                        state                <= S_HP_EN2;
                        i2c_read_write       <= 'd0; // Write
                        i2c_register_address <= 8'h2E; // Headphone Driver
                        if(mute)
                            i2c_mosi_data        <= 8'h80; // software power down - enabled
                        else
                            i2c_mosi_data        <= 8'h00; // software power down - disabled

                        i2c_device_address   <= CODEC;
                        txActive             <= 1'd0;
                        use_16_bit           <= 1'b0;

                    end
                    else
                        i2c_enable           <= 'd1;
            end
            S_HP_EN2:
            begin
                if(i2c_busy)
                begin
                    txActive         <= 1'd1;
                    i2c_enable       <= 'd0;
                end
                else
                    if(txActive)
                    begin
                        state                <= S_HP_EN3;
                        i2c_read_write       <= 'd0; // Write
                        i2c_register_address <= 8'd00; // Page select
                        i2c_mosi_data        <= 8'd00; // Page 0
                        i2c_device_address   <= CODEC;
                        txActive             <= 1'd0;
                        use_16_bit           <= 1'b0;

                    end
                    else
                        i2c_enable           <= 'd1;
            end
            S_HP_EN3:
            begin
                if(i2c_busy)
                begin
                    txActive         <= 1'd1;
                    i2c_enable       <= 'd0;
                end
                else
                    if(txActive)
                    begin
                        state                <= S_HP_EN4;
                        i2c_read_write       <= 'd0; // Write
                        i2c_register_address <= 8'h3F; // DAC Data-Path setup
                        if(gpio[1])
                            i2c_mosi_data        <= 8'hD4; // Power up both dacs
                        else
                            i2c_mosi_data        <= 8'h90; // Power down right DAC, speaker mix both channel
                        i2c_device_address   <= CODEC;
                        txActive             <= 1'd0;
                        use_16_bit           <= 1'b0;

                    end
                    else
                        i2c_enable           <= 'd1;
            end
            S_HP_EN4:
            begin
                if(i2c_busy)
                begin
                    txActive         <= 1'd1;
                    i2c_enable       <= 'd0;
                end
                else
                    if(txActive)
                    begin
                        i2c_read_write       <= 'd1; // Read
                        state                <= S_SYS_STATUS;
                        i2c_register_address <= 8'd08; // System Status
                        i2c_device_address   <= PMIC;
                        txActive             <= 1'd0;
                        use_16_bit           <= 1'b0;

                    end
                    else
                        i2c_enable           <= 'd1;
            end
            S_SYS_STATUS:
            begin
                if(i2c_busy)
                begin
                    txActive         <= 1'd1;
                    i2c_enable       <= 'd0;
                end
                else
                    if(txActive)
                    begin
                        i2c_read_write       <= 'd1; // Read
                        state                <= S_NEW_FAULT;
                        i2c_register_address <= 8'd09; // Fault Status
                        i2c_device_address   <= PMIC;
                        pmic_sys_status      <= i2c_miso_data[7:0];
                        txActive             <= 1'd0;
                        use_16_bit           <= 1'b0;

                    end
                    else
                        i2c_enable           <= 'd1;
            end
            S_NEW_FAULT:
            begin
                if(i2c_busy)
                begin
                    txActive         <= 1'd1;
                    i2c_enable       <= 'd0;
                end
                else
                    if(txActive)
                    begin
                        i2c_read_write       <= 'd1; // Read
                        state                <= S_INLIM;
                        i2c_register_address <= 8'd00; // Input Limit
                        i2c_device_address   <= PMIC;
                        new_fault            <= i2c_miso_data[7:0];
                        txActive             <= 1'd0;
                        use_16_bit           <= 1'b0;
                    end
                    else
                        i2c_enable           <= 'd1;
            end
            S_INLIM:
            begin
                if(i2c_busy) begin
                    txActive <= 1'b1;
                    i2c_enable <= 1'b0;
                end else if(txActive) begin
                    if (!i2c_transaction_error) inlim <= i2c_miso_data[7:0];
                    // Write the complete, known timer configuration every pass.
                    state <= S_WATCHDOG;
                    i2c_read_write <= 1'b0;
                    i2c_register_address <= 8'h05;
                    i2c_device_address <= PMIC;
                    i2c_mosi_data <= CHARGE_TIMERS;
                    use_16_bit <= 1'b0;
                    txActive <= 1'b0;
                end else i2c_enable <= 1'b1;
            end
            S_WATCHDOG:
            begin
                if(i2c_busy) begin
                    txActive <= 1'b1;
                    i2c_enable <= 1'b0;
                end else if(txActive) begin
                    // Failed writes are retried on the next pass; current
                    // programming never depends on a charger register read.
                    txActive <= 1'b0;
                    if (HAS_TEMPSENSOR) begin
                        state <= S_TEMPREAD;
                        i2c_read_write <= 1'b1;
                        i2c_register_address <= TEMP_VALUE;
                        i2c_device_address <= TEMP;
                        use_16_bit <= 1'b1;
                    end else begin
                        state <= S_CHARGEWRITE;
                        i2c_read_write <= 1'b0;
                        i2c_register_address <= 8'h02;
                        i2c_device_address <= PMIC;
                        i2c_mosi_data <= CHARGE_LEGACY;
                        use_16_bit <= 1'b0;
                    end
                end else i2c_enable <= 1'b1;
            end
            S_TEMPREAD:
            begin
                if(i2c_busy) begin
                    txActive <= 1'b1;
                    i2c_enable <= 1'b0;
                end else if(txActive) begin
                    // TMP112 normal mode: signed integer degrees in [15:8].
                    // Never consume stale receive-buffer contents after NACK.
                    temperature_valid <= !i2c_transaction_error;
                    if (!i2c_transaction_error) begin
                        temperature <= i2c_miso_data[15:8];
                        temperature_age <= 0;
                    end
                    state <= S_CHARGEWRITE;
                    i2c_read_write <= 1'b0;
                    i2c_register_address <= 8'h02;
                    i2c_device_address <= PMIC;
                    use_16_bit <= 1'b0;
                    // Select from this completed read, not the previous sample.
                    i2c_mosi_data <= i2c_transaction_error ? CHARGE_COLD :
                        ($signed(i2c_miso_data[15:8]) < 8'sd15 ? CHARGE_COLD : CHARGE_WARM);
                    txActive <= 1'b0;
                end else i2c_enable <= 1'b1;
            end
            S_CHARGEWRITE:
            begin
                if(i2c_busy) begin
                    txActive <= 1'b1;
                    i2c_enable <= 1'b0;
                end else if(txActive) begin
                    state <= S_CHARGEREAD;
                    i2c_read_write <= 1'b1;
                    i2c_register_address <= 8'h02;
                    i2c_device_address <= PMIC;
                    txActive <= 1'b0;
                end else begin
                    // Recheck validity at launch if a sample has aged out.
                    i2c_mosi_data <= requested_current;
                    i2c_enable <= 1'b1;
                end
            end
            S_CHARGEREAD:
            begin
                if(i2c_busy) begin
                    txActive <= 1'b1;
                    i2c_enable <= 1'b0;
                end else if(txActive) begin
                    // Readback is telemetry only, never an input to policy.
                    if (!i2c_transaction_error) chargeCurrent <= i2c_miso_data[7:0];
                    state <= S_IDLE;
                    txActive <= 1'b0;
                end else i2c_enable <= 1'b1;
            end
            endcase
        end
    end

endmodule


// Temperature sensor
// * use normal mode, EM = 0
// * temperature register 8'd0, need to read 2 bytes
//   - 1st byte is full,  
//   - 2nd byte is partially full (most significant 4 bits populated, lower bits are 0)
//   - shouldn't need to read the lower byte, in fact the datasheet mentions that
//   - represented as Q8.4 format 
// * defaults to 4Hz conversion mode
//
//    Examples:
//    0x64 = 100C
//    0x32 = 50C
//    0x17 = 23C
//
//
//
//
//
//
//
