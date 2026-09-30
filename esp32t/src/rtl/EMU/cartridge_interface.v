// Cartridge power and pin isolation. OE is active high on this board.
// Run from the always-running hClk, independently of emulator reset.
module cartridge_interface #(
    parameter integer CLK_HZ = 16777216,
    parameter integer POWER_UP_CYCLES = (CLK_HZ + 19) / 20,
    parameter integer SETTLE_CYCLES = (CLK_HZ + 99) / 100,
    parameter integer POWER_DOWN_CYCLES = (CLK_HZ + 99) / 100
) (
    input clk,
    input reset_n,
    input cartridge_enable,
    input version_detect,
    output cartridge_ready,
    input [15:0] core_a,
    input core_clk, core_cs, core_rd, core_wr,
    input [7:0] core_d_out,
    input core_data_dir_e,
    output [7:0] core_d_in,
    output [15:0] CART_A,
    output CART_CLK, CART_CS, CART_RD, CART_WR,
    inout [7:0] CART_D,
    inout CART_RST,
    output CART_DATA_DIR_E,
    output CART_CTRL_OE,
    output CART_PWR_EN
);
    localparam OFF = 3'd0, POWER_UP = 3'd1, SETTLE = 3'd2,
               RUNNING = 3'd3, POWER_DOWN = 3'd4;
    reg [2:0] state = OFF;
    reg [31:0] timer = 0;
    reg [1:0] enable_sync = 0;
    reg [1:0] version_sync = 0;
    reg [2:0] version_valid = 0;
    reg legacy = 0;

    always @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            enable_sync <= 0;
            version_sync <= 0;
            version_valid <= 0;
            legacy <= 0;
        end else begin
            enable_sync <= {enable_sync[0], cartridge_enable};
            version_sync <= {version_sync[0], version_detect};
            version_valid <= {version_valid[1:0], 1'b1};
            // The board strap is static; latch it after synchronization.
            if (!version_valid[2]) legacy <= version_sync[1];
        end
    end

    always @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            state <= OFF;
            timer <= 0;
        end else begin
            case (state)
                OFF: begin
                    timer <= 0;
                    if (version_valid[2] && enable_sync[1]) state <= POWER_UP;
                end
                POWER_UP, SETTLE, RUNNING: begin
                    if (!enable_sync[1]) begin
                        state <= POWER_DOWN;
                        timer <= 0;
                    end else if (state == POWER_UP) begin
                        if (timer == POWER_UP_CYCLES - 1) begin
                            state <= SETTLE;
                            timer <= 0;
                        end else timer <= timer + 1'b1;
                    end else if (state == SETTLE) begin
                        if (timer == SETTLE_CYCLES - 1) begin
                            state <= RUNNING;
                            timer <= 0;
                        end else timer <= timer + 1'b1;
                    end
                end
                POWER_DOWN: begin
                    // Finish shutdown even if the switch is turned back on.
                    if (timer == POWER_DOWN_CYCLES - 1) begin
                        state <= OFF;
                        timer <= 0;
                    end else timer <= timer + 1'b1;
                end
                default: begin state <= OFF; timer <= 0; end
            endcase
        end
    end

    assign cartridge_ready = state == RUNNING;
    assign CART_PWR_EN = state == POWER_UP || state == SETTLE || state == RUNNING;
    // Legacy OE retains its previous switch-controlled behavior.
    assign CART_CTRL_OE = legacy ? enable_sync[1] : (state == SETTLE || state == RUNNING);
    wire pass_pins = legacy || cartridge_ready;
    wire drive_low = !legacy && state == OFF;
    assign CART_A = pass_pins ? core_a : 16'b0;
    assign CART_CLK = pass_pins ? core_clk : !drive_low;
    assign CART_CS = pass_pins ? core_cs : !drive_low;
    assign CART_RD = pass_pins ? core_rd : !drive_low;
    assign CART_WR = pass_pins ? core_wr : !drive_low;
    // DIR_E low means FPGA -> cartridge. During startup/shutdown idle,
    // release data; only drive it low once the shutdown delay has elapsed.
    assign CART_DATA_DIR_E = pass_pins ? core_data_dir_e : !drive_low;
    assign CART_D = drive_low ? 8'b0 :
                    (pass_pins && !core_data_dir_e) ? core_d_out : 8'bz;
    // Reset can also be driven by cartridges: never actively drive it high.
    assign CART_RST = drive_low ? 1'b0 : 1'bz;
    assign core_d_in = cartridge_ready ? CART_D : 8'b0;
endmodule
