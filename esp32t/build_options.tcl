# Scalar process options shared with the IDE (no Tcl JSON package required).
set config_file [open impl/evt1_x2_process_config.json r]
set config_json [read $config_file]
close $config_file
proc ide_option {key} {
    global config_json
    set pattern [format {"%s"\s*:\s*("[^"]*"|true|false|[0-9]+)} $key]
    if {![regexp $pattern $config_json match value]} {
        error "Missing IDE process setting: $key"
    }
    set value [string trim $value \"]
    if {$value eq "true"} { return 1 }
    if {$value eq "false"} { return 0 }
    return $value
}
foreach {key option} {
    TopModule top_module
    OUTPUT_BASE_NAME output_base_name
    Global_Freq global_freq
    GwSyn_Loop_Limit looplimit
    Ram_RW_Check rw_check_on_ram
    Disable_Insert_Pad disable_io_insertion
    Map_Option map_option
    Run_Timing_Driven timing_driven
    Place_Option place_option
    Route_Option route_option
    Clock_Route_Order clock_route_order
    Route_Maxfan route_maxfan
    INCREMENTAL_PLACE_ONLY inc_place
    INCREMENTAL_PLACE_AND_ROUTING inc_pnr
    PlaceInRegToIob ireg_in_iob
    PlaceOutRegToIob oreg_in_iob
    PlaceIoRegToIob ioreg_in_iob
    Replicate_Resources replicate_resources
    Correct_Hold_Violation correct_hold_violation
    Convert_SDP32_36_to_SDP16_18 convert_sdp32_36_to_sdp16_18
    Co-Place_IO_Registers co-place_io_registers
    Promote_Physical_Constraint_Warning_to_Error cst_warn_to_error
    Report_Auto-Placed_Io_Information rpt_auto_place_io_info
    Generate_SDF_File gen_sdf
    Generate_Constraint_File_of_Ports gen_io_cst
    Generate_Post_Place_File gen_posp
    Generate_Plain_Text_Timing_Report gen_text_timing_rpt
    Generate_Post_PNR_Simulation_Model_File gen_verilog_sim_netlist
    Generate_VHDL_Post_PNR_Simulation_Model_File gen_vhdl_sim_netlist
    JTAG use_jtag_as_gpio
    SSPI use_sspi_as_gpio
    MSPI use_mspi_as_gpio
    READY use_ready_as_gpio
    DONE use_done_as_gpio
    MODE_IO use_mode_as_gpio
    I2C use_i2c_as_gpio
    CPU use_cpu_as_gpio
    POWER_ON_RESET_MONITOR power_on_reset_monitor
    CRC_CHECK bit_crc_check
    COMPRESS bit_compress
    SECURITY_BIT bit_security
    PRINT_BSRAM_VALUE bit_incl_bsram_init
    HOTBOOT hotboot
    USERCODE user_code
    BACKGROUND_PROGRAMMING bg_programming
    Multi_Boot multi_boot
    MSPI_JUMP mspi_jump
    VCC vcc
} {
    set value [ide_option $key]
    puts "IDE option: -$option $value"
    set_option -$option $value
}
# The GW5A CLI rejects gen_ibis even when disabled.
if {[ide_option Generate_IBIS_File]} {
    error "IBIS generation is unsupported by this device's CLI"
}
# These voltage fields are fixed for this device; the CLI rejects setters.
foreach key {VCCAUX VCCX} {
    if {[ide_option $key] ne "3.3"} { error "Unsupported IDE voltage: $key" }
}
# These IDE labels differ from the Tcl spelling. Fail rather than ignore edits.
foreach {key expected option value} {
    Synthesize_tool GowinSyn synthesis_tool gowinsynthesis
    Verilog_Standard Vlg_Std_Sysv2017 verilog_std sysv2017
    VHDL_Standard VHDL_Std_2008 vhdl_std vhd2008
    FORMAT binary bit_format bin
    Unused_Pin As_input_tri_stated_with_pull_up unused_pin default
    DOWNLOAD_SPEED 210/2 loading_rate 210/2
} {
    if {[ide_option $key] ne $expected} {
        error "Update build_options.tcl mapping for IDE setting $key"
    }
    set_option -$option $value
}
