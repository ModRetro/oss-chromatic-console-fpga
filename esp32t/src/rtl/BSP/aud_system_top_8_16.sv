// aud_system_top.v

module aud_system_top_8_16 (
    input               appear_off,
    input               gClk,
    input               hClk,
    input               reset_n,
    input   [15:0]      left,
    input   [15:0]      right,
    input               software_mute,

    output  [7:0]       volume,
    output              hHeadphones,
    output  [7:0]       pmic_sys_status,
    output  [7:0]       temperature,   // integer part
    output              AUD_BCLK,
    output              AUD_DIN,
    input               AUD_DOUT,
    output              AUD_MCLK,
    output              AUD_RESET,
    output   reg        AUD_WCLK,

    inout               SCL,
    inout               SDA,

    input wire          VERSION_DET,
    input wire          POWER_ON_FPGA
);



    wire use_16_bit;
    // New boards pull VERSION_DET low; legacy boards use its weak pull-up.
    reg [1:0] version_sync;
    reg [2:0] version_settle;
    reg has_tempsensor;
    always @(posedge hClk or negedge reset_n) begin
        if (!reset_n) begin
            version_sync <= 2'b00;
            version_settle <= 3'b000;
            has_tempsensor <= 1'b1;
        end else begin
            version_sync <= {version_sync[0], VERSION_DET};
            version_settle <= {version_settle[1:0], 1'b1};
            if (!version_settle[2]) has_tempsensor <= !version_sync[1];
        end
    end
    reg [31:0] stereo_sr;
    reg [4:0] count;

    // Output bit-clock phase only; all serializer registers use gClk.
    // When the old phase is zero, this edge makes AUD_BCLK fall.
    reg audio_phase = 1'b0;
    always @(posedge gClk or negedge reset_n)
        if (~reset_n) audio_phase <= 1'b0;
        else audio_phase <= ~audio_phase;

    wire [7:0] hpgpio;
    assign hHeadphones = hpgpio[1];

    wire mute = (software_mute | volume > 8'h76);

    wire [15:0] left_m =  mute ? 16'd0 : -left;
    wire [15:0] right_m = mute ? 16'd0 : -right;

    // Use the current sum at frame load. The former divided-clock block
    // observed the sum updated on that same gClk edge.
    wire [16:0] gMonoSpeaker = left_m + right_m;

    always @(posedge gClk or negedge reset_n) begin
        if (~reset_n) begin
            count <= 5'd0;
            AUD_WCLK <= 1'b0;
            stereo_sr <= 32'd0;
        end
        else if (~audio_phase)
        begin
            if (count == 5'd0) begin
                count <= 5'd31;
                AUD_WCLK <= 1'b1;
                stereo_sr <= ~hHeadphones ? {16'd0,gMonoSpeaker[16:1]} :
                    { right_m[15:0],left_m[15:0] };
            end
            else begin
                count <= count - 1'd1;
                if(count == 5'd16)
                    AUD_WCLK <= 1'b0;
                stereo_sr <= {stereo_sr[30:0], 1'b0};
            end
        end
    end

    assign AUD_MCLK     = gClk;
    assign AUD_BCLK     = ~audio_phase;

    // turn off audio (if emulator core in reset, this is unnecessary)
    assign AUD_DIN      = appear_off ? 1'b0 : stereo_sr[31];

    assign AUD_RESET    = reset_n;

    parameter I2C_DATA_WIDTH = 8;
    parameter REGISTER_WIDTH = 8;
    parameter ADDRESS_WIDTH = 7;

// =======================================================================
// Assumptions: 
// - 7 bit I2C address
// - 8 bit register addresses
// - 8 bit data EXCEPT for 16 bit temperature read
// =======================================================================
    wire  [15:0] i2c_miso_data;  // deal with 15 or 8 bit data, truncate, pad as necessary
    wire         i2c_busy;       // output
    wire         i2c_transaction_error;

    wire         tlv320_init_done;
    wire         tlv320_i2c_enable;
    wire         tlv320_i2c_read_write;
    wire  [7:0]  tlv320_i2c_mosi_data;
    wire  [7:0]  tlv320_i2c_register_address;
    wire  [6:0]  tlv320_i2c_device_address;

    wire         pol_i2c_enable;
    wire         pol_i2c_read_write;
    wire  [7:0]  pol_i2c_mosi_data;
    wire  [7:0]  pol_i2c_register_address;
    wire  [6:0]  pol_i2c_device_address;

    wire         i2c_enable = tlv320_init_done ? pol_i2c_enable : tlv320_i2c_enable;
    wire         i2c_read_write = tlv320_init_done ? pol_i2c_read_write : tlv320_i2c_read_write;
    wire  [7:0]  i2c_mosi_data = tlv320_init_done ? pol_i2c_mosi_data : tlv320_i2c_mosi_data;
    wire  [7:0]  i2c_register_address = tlv320_init_done ? pol_i2c_register_address : tlv320_i2c_register_address;
    wire  [6:0]  i2c_device_address = tlv320_init_done ? pol_i2c_device_address : tlv320_i2c_device_address;

//    wire use_16_bit;

    // Initializes the Audio codec
    tlv320_init u_tlv320_init(
        .pclk(hClk),
        .vb_rst(~reset_n),
        .i2c_busy(i2c_busy),
        .tlv320_init_done(tlv320_init_done),

        .i2c_enable(tlv320_i2c_enable),
        .i2c_read_write(tlv320_i2c_read_write),
        .i2c_mosi_data(tlv320_i2c_mosi_data),
        .i2c_register_address(tlv320_i2c_register_address),
        .i2c_device_address(tlv320_i2c_device_address)
    );


    // 
    polling_master_8_16 u_pol_master(
        .clk(hClk),
        .rst(~reset_n),
        .i2c_busy(i2c_busy),
        .enable(tlv320_init_done && version_settle[2]),
        .i2c_transaction_error(i2c_transaction_error),
        .mute(software_mute),
        .use_16_bit (use_16_bit),
        .volume(volume),
        .gpio(hpgpio),
        .pmic_sys_status(pmic_sys_status),
        .new_fault(),
        .inlim(),
        .chargeCurrent(),
        .temperature(temperature),
        .i2c_enable(pol_i2c_enable),
        .i2c_miso_data(i2c_miso_data),
        .i2c_read_write(pol_i2c_read_write),
        .i2c_mosi_data(pol_i2c_mosi_data),
        .i2c_register_address(pol_i2c_register_address),
        .i2c_device_address(pol_i2c_device_address),

        .HAS_TEMPSENSOR (has_tempsensor)
    );


    // 8 or 16 bit reads dependent on "use_16_bit" signal

    i2c_master_8_16 #(
        .DATA_WIDTH (8), 
        .REGISTER_WIDTH (8), 
        .ADDRESS_WIDTH (7)
    ) i2c_master_inst (
        .clock                  (hClk),
        .reset_n                (reset_n),
        .enable                 (i2c_enable),
        .read_write             (i2c_read_write),
        .use_16_bit             (use_16_bit),
        // when operating as master, both sources of I2C transactions output 8 bit data.  To maintain
        // a uniform implementation, changed the I2C master so that input and output data is 16 bit.
        // Padding and truncation occurs in appropriae place
        .mosi_data              ({8'h0, i2c_mosi_data}),  
        .register_address       (i2c_register_address),
        .device_address         (i2c_device_address),
        .divider                (16'd20),

        .miso_data              (i2c_miso_data),
        .busy                   (i2c_busy),
        .transaction_error      (i2c_transaction_error),

        .external_serial_data   (SDA),
        .external_serial_clock  (SCL)
    );



endmodule
