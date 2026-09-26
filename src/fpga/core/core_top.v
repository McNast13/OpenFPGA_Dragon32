//
// User core top-level
//
// Instantiated by the real top-level: apf_top
//

`default_nettype none

module core_top (

//
// physical connections
//

///////////////////////////////////////////////////
// clock inputs 74.25mhz. not phase aligned, so treat these domains as asynchronous

input   wire            clk_74a, // mainclk1
input   wire            clk_74b, // mainclk1 

///////////////////////////////////////////////////
// cartridge interface
// switches between 3.3v and 5v mechanically
// output enable for multibit translators controlled by pic32

// GBA AD[15:8]
inout   wire    [7:0]   cart_tran_bank2,
output  wire            cart_tran_bank2_dir,

// GBA AD[7:0]
inout   wire    [7:0]   cart_tran_bank3,
output  wire            cart_tran_bank3_dir,

// GBA A[23:16]
inout   wire    [7:0]   cart_tran_bank1,
output  wire            cart_tran_bank1_dir,

// GBA [7] PHI#
// GBA [6] WR#
// GBA [5] RD#
// GBA [4] CS1#/CS#
//     [3:0] unwired
inout   wire    [7:4]   cart_tran_bank0,
output  wire            cart_tran_bank0_dir,

// GBA CS2#/RES#
inout   wire            cart_tran_pin30,
output  wire            cart_tran_pin30_dir,
// when GBC cart is inserted, this signal when low or weak will pull GBC /RES low with a special circuit
// the goal is that when unconfigured, the FPGA weak pullups won't interfere.
// thus, if GBC cart is inserted, FPGA must drive this high in order to let the level translators
// and general IO drive this pin.
output  wire            cart_pin30_pwroff_reset,

// GBA IRQ/DRQ
inout   wire            cart_tran_pin31,
output  wire            cart_tran_pin31_dir,

// infrared
input   wire            port_ir_rx,
output  wire            port_ir_tx,
output  wire            port_ir_rx_disable, 

// GBA link port
inout   wire            port_tran_si,
output  wire            port_tran_si_dir,
inout   wire            port_tran_so,
output  wire            port_tran_so_dir,
inout   wire            port_tran_sck,
output  wire            port_tran_sck_dir,
inout   wire            port_tran_sd,
output  wire            port_tran_sd_dir,
 
///////////////////////////////////////////////////
// cellular psram 0 and 1, two chips (64mbit x2 dual die per chip)

output  wire    [21:16] cram0_a,
inout   wire    [15:0]  cram0_dq,
input   wire            cram0_wait,
output  wire            cram0_clk,
output  wire            cram0_adv_n,
output  wire            cram0_cre,
output  wire            cram0_ce0_n,
output  wire            cram0_ce1_n,
output  wire            cram0_oe_n,
output  wire            cram0_we_n,
output  wire            cram0_ub_n,
output  wire            cram0_lb_n,

output  wire    [21:16] cram1_a,
inout   wire    [15:0]  cram1_dq,
input   wire            cram1_wait,
output  wire            cram1_clk,
output  wire            cram1_adv_n,
output  wire            cram1_cre,
output  wire            cram1_ce0_n,
output  wire            cram1_ce1_n,
output  wire            cram1_oe_n,
output  wire            cram1_we_n,
output  wire            cram1_ub_n,
output  wire            cram1_lb_n,

///////////////////////////////////////////////////
// sdram, 512mbit 16bit

output  wire    [12:0]  dram_a,
output  wire    [1:0]   dram_ba,
inout   wire    [15:0]  dram_dq,
output  wire    [1:0]   dram_dqm,
output  wire            dram_clk,
output  wire            dram_cke,
output  wire            dram_ras_n,
output  wire            dram_cas_n,
output  wire            dram_we_n,

///////////////////////////////////////////////////
// sram, 1mbit 16bit

output  wire    [16:0]  sram_a,
inout   wire    [15:0]  sram_dq,
output  wire            sram_oe_n,
output  wire            sram_we_n,
output  wire            sram_ub_n,
output  wire            sram_lb_n,

///////////////////////////////////////////////////
// vblank driven by dock for sync in a certain mode

input   wire            vblank,

///////////////////////////////////////////////////
// i/o to 6515D breakout usb uart

output  wire            dbg_tx,
input   wire            dbg_rx,

///////////////////////////////////////////////////
// i/o pads near jtag connector user can solder to

output  wire            user1,
input   wire            user2,

///////////////////////////////////////////////////
// RFU internal i2c bus 

inout   wire            aux_sda,
output  wire            aux_scl,

///////////////////////////////////////////////////
// RFU, do not use
output  wire            vpll_feed,


//
// logical connections
//

///////////////////////////////////////////////////
// video, audio output to scaler
output  wire    [23:0]  video_rgb,
output  wire            video_rgb_clock,
output  wire            video_rgb_clock_90,
output  wire            video_de,
output  wire            video_skip,
output  wire            video_vs,
output  wire            video_hs,
    
output  wire            audio_mclk,
input   wire            audio_adc,
output  wire            audio_dac,
output  wire            audio_lrck,

///////////////////////////////////////////////////
// bridge bus connection
// synchronous to clk_74a
output  wire            bridge_endian_little,
input   wire    [31:0]  bridge_addr,
input   wire            bridge_rd,
output  reg     [31:0]  bridge_rd_data,
input   wire            bridge_wr,
input   wire    [31:0]  bridge_wr_data,

///////////////////////////////////////////////////
// controller data
// 
// key bitmap:
//   [0]    dpad_up
//   [1]    dpad_down
//   [2]    dpad_left
//   [3]    dpad_right
//   [4]    face_a
//   [5]    face_b
//   [6]    face_x
//   [7]    face_y
//   [8]    trig_l1
//   [9]    trig_r1
//   [10]   trig_l2
//   [11]   trig_r2
//   [12]   trig_l3
//   [13]   trig_r3
//   [14]   face_select
//   [15]   face_start
//   [31:28] type
// joy values - unsigned
//   [ 7: 0] lstick_x
//   [15: 8] lstick_y
//   [23:16] rstick_x
//   [31:24] rstick_y
// trigger values - unsigned
//   [ 7: 0] ltrig
//   [15: 8] rtrig
//
input   wire    [31:0]  cont1_key,
input   wire    [31:0]  cont2_key,
input   wire    [31:0]  cont3_key,
input   wire    [31:0]  cont4_key,
input   wire    [31:0]  cont1_joy,
input   wire    [31:0]  cont2_joy,
input   wire    [31:0]  cont3_joy,
input   wire    [31:0]  cont4_joy,
input   wire    [15:0]  cont1_trig,
input   wire    [15:0]  cont2_trig,
input   wire    [15:0]  cont3_trig,
input   wire    [15:0]  cont4_trig
    
);

// not using the IR port, so turn off both the LED, and
// disable the receive circuit to save power
assign port_ir_tx = 0;
assign port_ir_rx_disable = 1;

// bridge endianness
assign bridge_endian_little = 0;

// cart is unused, so set all level translators accordingly
// directions are 0:IN, 1:OUT
assign cart_tran_bank3 = 8'hzz;
assign cart_tran_bank3_dir = 1'b0;
assign cart_tran_bank2 = 8'hzz;
assign cart_tran_bank2_dir = 1'b0;
assign cart_tran_bank1 = 8'hzz;
assign cart_tran_bank1_dir = 1'b0;
assign cart_tran_bank0 = 4'hf;
assign cart_tran_bank0_dir = 1'b1;
assign cart_tran_pin30 = 1'b0;      // reset or cs2, we let the hw control it by itself
assign cart_tran_pin30_dir = 1'bz;
assign cart_pin30_pwroff_reset = 1'b0;  // hardware can control this
assign cart_tran_pin31 = 1'bz;      // input
assign cart_tran_pin31_dir = 1'b0;  // input

// link port is unused, set to input only to be safe
// each bit may be bidirectional in some applications
assign port_tran_so = 1'bz;
assign port_tran_so_dir = 1'b0;     // SO is output only
assign port_tran_si = 1'bz;
assign port_tran_si_dir = 1'b0;     // SI is input only
assign port_tran_sck = 1'bz;
assign port_tran_sck_dir = 1'b0;    // clock direction can change
assign port_tran_sd = 1'bz;
assign port_tran_sd_dir = 1'b0;     // SD is input and not used

// tie off the rest of the pins we are not using
assign cram0_a = 'h0;
assign cram0_dq = {16{1'bZ}};
assign cram0_clk = 0;
assign cram0_adv_n = 1;
assign cram0_cre = 0;
assign cram0_ce0_n = 1;
assign cram0_ce1_n = 1;
assign cram0_oe_n = 1;
assign cram0_we_n = 1;
assign cram0_ub_n = 1;
assign cram0_lb_n = 1;

assign cram1_a = 'h0;
assign cram1_dq = {16{1'bZ}};
assign cram1_clk = 0;
assign cram1_adv_n = 1;
assign cram1_cre = 0;
assign cram1_ce0_n = 1;
assign cram1_ce1_n = 1;
assign cram1_oe_n = 1;
assign cram1_we_n = 1;
assign cram1_ub_n = 1;
assign cram1_lb_n = 1;

assign dram_a = 'h0;
assign dram_ba = 'h0;
assign dram_dq = {16{1'bZ}};
assign dram_dqm = 'h0;
assign dram_clk = 'h0;
assign dram_cke = 'h0;
assign dram_ras_n = 'h1;
assign dram_cas_n = 'h1;
assign dram_we_n = 'h1;

assign sram_a = 'h0;
assign sram_dq = {16{1'bZ}};
assign sram_oe_n  = 1;
assign sram_we_n  = 1;
assign sram_ub_n  = 1;
assign sram_lb_n  = 1;

assign dbg_tx = 1'bZ;
assign user1 = 1'bZ;
assign aux_scl = 1'bZ;
assign vpll_feed = 1'bZ;


// for bridge write data, we just broadcast it to all bus devices
// for bridge read data, we have to mux it
// add your own devices here
always @(*) begin
    casex(bridge_addr)
    default: begin
        bridge_rd_data <= 0;
    end
    32'h10xxxxxx: begin
        // example
        // bridge_rd_data <= example_device_data;
        bridge_rd_data <= 0;
    end
    32'hF8xxxxxx: begin
        bridge_rd_data <= cmd_bridge_rd_data;
    end
    endcase
end


//
// host/target command handler
//
    wire            reset_n;                // driven by host commands, can be used as core-wide reset
    wire    [31:0]  cmd_bridge_rd_data;
    
// bridge host commands
// synchronous to clk_74a
    wire            status_boot_done = pll_core_locked_s; 
    wire            status_setup_done = pll_core_locked_s; // rising edge triggers a target command
    wire            status_running = reset_n; // we are running as soon as reset_n goes high

    wire            dataslot_requestread;
    wire    [15:0]  dataslot_requestread_id;
    wire            dataslot_requestread_ack = 1;
    wire            dataslot_requestread_ok = 1;

    wire            dataslot_requestwrite;
    wire    [15:0]  dataslot_requestwrite_id;
    wire    [31:0]  dataslot_requestwrite_size;
    wire            dataslot_requestwrite_ack = 1;
    wire            dataslot_requestwrite_ok = 1;

    wire            dataslot_update;
    wire    [15:0]  dataslot_update_id;
    wire    [31:0]  dataslot_update_size;
    
    wire            dataslot_allcomplete;

    wire     [31:0] rtc_epoch_seconds;
    wire     [31:0] rtc_date_bcd;
    wire     [31:0] rtc_time_bcd;
    wire            rtc_valid;

    wire            savestate_supported;
    wire    [31:0]  savestate_addr;
    wire    [31:0]  savestate_size;
    wire    [31:0]  savestate_maxloadsize;

    wire            savestate_start;
    wire            savestate_start_ack;
    wire            savestate_start_busy;
    wire            savestate_start_ok;
    wire            savestate_start_err;

    wire            savestate_load;
    wire            savestate_load_ack;
    wire            savestate_load_busy;
    wire            savestate_load_ok;
    wire            savestate_load_err;
    
    wire            osnotify_inmenu;

// bridge target commands
// synchronous to clk_74a

    reg             target_dataslot_read;       
    reg             target_dataslot_write;
    reg             target_dataslot_getfile;    // require additional param/resp structs to be mapped
    reg             target_dataslot_openfile;   // require additional param/resp structs to be mapped
    
    wire            target_dataslot_ack;        
    wire            target_dataslot_done;
    wire    [2:0]   target_dataslot_err;

    reg     [15:0]  target_dataslot_id;
    reg     [31:0]  target_dataslot_slotoffset;
    reg     [31:0]  target_dataslot_bridgeaddr;
    reg     [31:0]  target_dataslot_length;
    
    wire    [31:0]  target_buffer_param_struct; // to be mapped/implemented when using some Target commands
    wire    [31:0]  target_buffer_resp_struct;  // to be mapped/implemented when using some Target commands
    
// bridge data slot access
// synchronous to clk_74a

    wire    [9:0]   datatable_addr;
    wire            datatable_wren;
    wire    [31:0]  datatable_data;
    wire    [31:0]  datatable_q;

core_bridge_cmd icb (

    .clk                ( clk_74a ),
    .reset_n            ( reset_n ),

    .bridge_endian_little   ( bridge_endian_little ),
    .bridge_addr            ( bridge_addr ),
    .bridge_rd              ( bridge_rd ),
    .bridge_rd_data         ( cmd_bridge_rd_data ),
    .bridge_wr              ( bridge_wr ),
    .bridge_wr_data         ( bridge_wr_data ),
    
    .status_boot_done       ( status_boot_done ),
    .status_setup_done      ( status_setup_done ),
    .status_running         ( status_running ),

    .dataslot_requestread       ( dataslot_requestread ),
    .dataslot_requestread_id    ( dataslot_requestread_id ),
    .dataslot_requestread_ack   ( dataslot_requestread_ack ),
    .dataslot_requestread_ok    ( dataslot_requestread_ok ),

    .dataslot_requestwrite      ( dataslot_requestwrite ),
    .dataslot_requestwrite_id   ( dataslot_requestwrite_id ),
    .dataslot_requestwrite_size ( dataslot_requestwrite_size ),
    .dataslot_requestwrite_ack  ( dataslot_requestwrite_ack ),
    .dataslot_requestwrite_ok   ( dataslot_requestwrite_ok ),

    .dataslot_update            ( dataslot_update ),
    .dataslot_update_id         ( dataslot_update_id ),
    .dataslot_update_size       ( dataslot_update_size ),
    
    .dataslot_allcomplete   ( dataslot_allcomplete ),

    .rtc_epoch_seconds      ( rtc_epoch_seconds ),
    .rtc_date_bcd           ( rtc_date_bcd ),
    .rtc_time_bcd           ( rtc_time_bcd ),
    .rtc_valid              ( rtc_valid ),
    
    .savestate_supported    ( savestate_supported ),
    .savestate_addr         ( savestate_addr ),
    .savestate_size         ( savestate_size ),
    .savestate_maxloadsize  ( savestate_maxloadsize ),

    .savestate_start        ( savestate_start ),
    .savestate_start_ack    ( savestate_start_ack ),
    .savestate_start_busy   ( savestate_start_busy ),
    .savestate_start_ok     ( savestate_start_ok ),
    .savestate_start_err    ( savestate_start_err ),

    .savestate_load         ( savestate_load ),
    .savestate_load_ack     ( savestate_load_ack ),
    .savestate_load_busy    ( savestate_load_busy ),
    .savestate_load_ok      ( savestate_load_ok ),
    .savestate_load_err     ( savestate_load_err ),

    .osnotify_inmenu        ( osnotify_inmenu ),
    
    .target_dataslot_read       ( target_dataslot_read ),
    .target_dataslot_write      ( target_dataslot_write ),
    .target_dataslot_getfile    ( target_dataslot_getfile ),
    .target_dataslot_openfile   ( target_dataslot_openfile ),
    
    .target_dataslot_ack        ( target_dataslot_ack ),
    .target_dataslot_done       ( target_dataslot_done ),
    .target_dataslot_err        ( target_dataslot_err ),

    .target_dataslot_id         ( target_dataslot_id ),
    .target_dataslot_slotoffset ( target_dataslot_slotoffset ),
    .target_dataslot_bridgeaddr ( target_dataslot_bridgeaddr ),
    .target_dataslot_length     ( target_dataslot_length ),

    .target_buffer_param_struct ( target_buffer_param_struct ),
    .target_buffer_resp_struct  ( target_buffer_resp_struct ),
    
    .datatable_addr         ( datatable_addr ),
    .datatable_wren         ( datatable_wren ),
    .datatable_data         ( datatable_data ),
    .datatable_q            ( datatable_q )

);



////////////////////////////////////////////////////////////////////////////////////////



// Dragon 32 machine clock
//
// dragoncoco.sv (and everything inside it) is a single-clock-domain design
// wanting ~57.272727 MHz (16x NTSC colorburst - a real hardware constant of
// the machine, unrelated to the Pocket's own clocking). Actually driven at
// 14.85 MHz for now, about a quarter of real-time speed - see dragon_pll.v
// for the full story on why (real timing closure limits on this specific
// part, not a PLL configuration issue) and why that's an acceptable trade
// for phase 1's gate. Derived from the APF system reference clock via a
// hand-written altera_pll instance - see dragon_pll.v and NOTES.md for why
// this didn't need Quartus's IP wizard.
// outclk_1 is the same frequency, phase-shifted 90 degrees, for the
// scaler's DDIO output clock (mirrors how mf_pllbase below does the same
// thing for its own outputs).

    wire    clk_dragon;
    wire    clk_dragon_90deg;
    wire    pll_dragon_locked;

dragon_pll dp1 (
    .refclk    ( clk_74a ),
    .rst       ( 0 ),
    .outclk_0  ( clk_dragon ),
    .outclk_1  ( clk_dragon_90deg ),
    .locked    ( pll_dragon_locked )
);

    wire    reset_n_dragon;
synch_3 s_rst_dragon (reset_n, reset_n_dragon, clk_dragon);

// Boot ROM loading: APF bridge writes -> dragoncoco.sv's ioctl_* bus.
//
// data_loader (agg23/analogue-pocket-utils, MIT) watches the bridge for
// writes into the data slot's declared address range and hands them out as
// a simple write_en/write_addr/write_data stream in our clock domain - see
// dist/Cores/McNast13.Dragon32/data.json for the matching slot ("address":
// "0x00000000", so ADDRESS_MASK_UPPER_4 is 0 here) and Assets/dragon32/
// McNast13.Dragon32/ for where the user's own boot.rom lands.
//
// ioctl_index is fixed at 8'h40 ({BOOT1, BOOT} per dragoncoco.sv's own
// constants) so every write lands in the Dragon 32 boot ROM slot
// specifically, not the CoCo2/Dragon64/disk slots multiplexed on the same
// bus inside the machine.

    wire            rom_wr;
    wire    [13:0]  rom_addr;
    wire    [7:0]   rom_data;

data_loader #(
    .ADDRESS_MASK_UPPER_4 ( 4'h0 ),
    .ADDRESS_SIZE         ( 14 ),
    .WRITE_MEM_CLOCK_DELAY( 12 ),
    .WRITE_MEM_EN_CYCLE_LENGTH( 5 )
) rom_data_loader (
    .clk_74a               ( clk_74a ),
    .clk_memory             ( clk_dragon ),

    .bridge_wr              ( bridge_wr ),
    .bridge_endian_little   ( bridge_endian_little ),
    .bridge_addr            ( bridge_addr ),
    .bridge_wr_data         ( bridge_wr_data ),

    .write_en   ( rom_wr ),
    .write_addr ( rom_addr ),
    .write_data ( rom_data )
);

// The Dragon 32 machine itself - ported from MiSTer's CoCo2_MiSTer as-is
// (see NOTES.md for the full inventory). Phase 1 scope only: get it
// booting to the BASIC prompt with a real picture. Input (phase 3) and
// audio (phase 2) are deliberately still tied off/silent here.

    wire [7:0]  dragon_red, dragon_green, dragon_blue;
    wire        dragon_hblank, dragon_vblank, dragon_hsync, dragon_vsync;

dragoncoco dragon (
    .clk            ( clk_dragon ),
    .turbo          ( 1'b0 ),
    .trig_reset_n   ( reset_n_dragon ),
    .hard_reset     ( 1'b0 ),
    .dragon         ( 1'b1 ),
    .dragon64       ( 1'b0 ),
    .kblayout       ( 1'b0 ),

    .red            ( dragon_red ),
    .green          ( dragon_green ),
    .blue           ( dragon_blue ),
    .hblank         ( dragon_hblank ),
    .vblank         ( dragon_vblank ),
    .hsync          ( dragon_hsync ),
    .vsync          ( dragon_vsync ),

    .vclk           (  ),
    .clk_Q_out      (  ),

    .artifact_phase ( 1'b0 ),
    .artifact_enable( 1'b0 ),
    .overscan       ( 1'b0 ),

    .uart_din       ( 1'b0 ),

    // keyboard input deferred to phase 3 - no key ever pressed for now,
    // which is fine: the Dragon boots straight to BASIC without one
    .ps2_key        ( 11'b0 ),

    // controller input deferred to phase 3
    .joy1           ( 16'b0 ),
    .joy2           ( 16'b0 ),
    .joya1          ( 16'b0 ),
    .joya2          ( 16'b0 ),
    .joy_use_dpad   ( 1'b0 ),

    .ioctl_data     ( rom_data ),
    .ioctl_addr     ( {2'b00, rom_addr} ),
    .ioctl_download ( 1'b0 ),
    .ioctl_wr       ( rom_wr ),
    .ioctl_index    ( 16'h0040 ),
    .roms_loaded    (  ),
    .roms_reset     ( ~reset_n_dragon ),

    // tape deferred to phase 3
    .casdout        ( 1'b0 ),
    .cas_relay      (  ),

    // audio deferred to phase 2
    .cass_snd       ( 12'b0 ),
    .sound          (  ),
    .sndout         (  ),

    .v_count        (  ),
    .h_count        (  ),
    .DLine1         (  ),
    .DLine2         (  ),

    // disk support not in v1 - fdc.sv still elaborates and runs, it just
    // never gets used while this stays 0
    .disk_cart_enabled( 1'b0 ),
    .CLK50MHZ       ( clk_74a ),

    .img_mounted    ( 5'b0 ),
    .img_readonly   ( 1'b0 ),
    .img_size       ( 20'b0 ),
    .sd_lba         (  ),
    .sd_blk_cnt     (  ),
    .sd_rd          (  ),
    .sd_wr          (  ),
    .sd_ack         ( 5'b0 ),
    .sd_buff_addr   ( 9'b0 ),
    .sd_buff_dout   ( 8'b0 ),
    .sd_buff_din    (  ),
    .sd_buff_wr     ( 1'b0 ),

    .CASS_REWIND_RECORD( 1'b0 )
);

// TEMPORARY DIAGNOSTIC BUILD - see NOTES.md "Debugging the gray screen".
//
// The intended design (see git history) drives the scaler directly from
// dragoncoco's own clk_dragon-clocked video signals. On real hardware that
// showed a solid gray screen indistinguishable from phase 0's test
// pattern, with no way to tell from the picture alone which of several
// possible causes it was (dragon_pll never locking, the machine stuck in
// reset, the boot ROM never actually arriving, or something else entirely
// inside dragoncoco's own video generation) - and if clk_dragon itself
// isn't a good clock, driving video_rgb_clock from it wouldn't show
// anything at all, which would look identical to what was reported.
//
// So: drive the scaler from clk_core_12288 (mf_pllbase's output - already
// proven working in phase 0, entirely independent of dragon_pll) and show
// one of four solid colors instead of real video, encoding exactly where
// the machine's boot sequence actually got to:
//
//   RED    - dragon_pll (dp1) never locked
//   BLUE   - dp1 locked, but reset_n_dragon never released
//   YELLOW - reset released, but the boot ROM was never written at all
//   GREEN  - all three look fine - the bug is elsewhere (most likely
//            inside dragoncoco's own video timing, or the CPU not
//            executing correctly)
//
// Revert to real video passthrough once this narrows down which it is.

    reg rom_ever_written = 1'b0;
always @(posedge clk_dragon) begin
    if (rom_wr) rom_ever_written <= 1'b1;
end

    wire pll_dragon_locked_s;
    wire reset_n_dragon_s;
    wire rom_ever_written_s;
synch_3 s_diag_pll (pll_dragon_locked, pll_dragon_locked_s, clk_core_12288);
synch_3 s_diag_rst (reset_n_dragon,    reset_n_dragon_s,    clk_core_12288);
synch_3 s_diag_rom (rom_ever_written,  rom_ever_written_s,  clk_core_12288);

    wire [23:0] diag_color =
        ~pll_dragon_locked_s ? 24'hFF0000 :
        ~reset_n_dragon_s    ? 24'h0000FF :
        ~rom_ever_written_s  ? 24'hFFFF00 :
                               24'h00FF00;

// dragon_hsync/vsync/hblank/vblank/red/green/blue and clk_dragon_90deg are
// unused while this diagnostic build drives video from clk_core_12288
// instead - harmless (just unused-pin warnings), left as-is so the machine
// instantiation itself doesn't need touching to revert this later.

assign video_rgb_clock = clk_core_12288;
assign video_rgb_clock_90 = clk_core_12288_90deg;
assign video_rgb = vidout_rgb;
assign video_de = vidout_de;
assign video_skip = vidout_skip;
assign video_vs = vidout_vs;
assign video_hs = vidout_hs;

    localparam  VID_V_BPORCH = 'd10;
    localparam  VID_V_ACTIVE = 'd240;
    localparam  VID_V_TOTAL = 'd512;
    localparam  VID_H_BPORCH = 'd10;
    localparam  VID_H_ACTIVE = 'd320;
    localparam  VID_H_TOTAL = 'd400;

    reg [15:0]  frame_count;

    reg [9:0]   x_count;
    reg [9:0]   y_count;

    reg [23:0]  vidout_rgb;
    reg         vidout_de;
    reg         vidout_skip;
    reg         vidout_vs;
    reg         vidout_hs;

always @(posedge clk_core_12288 or negedge reset_n) begin

    if(~reset_n) begin

        x_count <= 0;
        y_count <= 0;

    end else begin
        vidout_de <= 0;
        vidout_skip <= 0;
        vidout_vs <= 0;
        vidout_hs <= 0;

        x_count <= x_count + 1'b1;
        if(x_count == VID_H_TOTAL-1) begin
            x_count <= 0;

            y_count <= y_count + 1'b1;
            if(y_count == VID_V_TOTAL-1) begin
                y_count <= 0;
            end
        end

        if(x_count == 0 && y_count == 0) begin
            vidout_vs <= 1;
            frame_count <= frame_count + 1'b1;
        end

        if(x_count == 3) begin
            vidout_hs <= 1;
        end

        vidout_rgb <= 24'h0;
        if(x_count >= VID_H_BPORCH && x_count < VID_H_ACTIVE+VID_H_BPORCH) begin
            if(y_count >= VID_V_BPORCH && y_count < VID_V_ACTIVE+VID_V_BPORCH) begin
                vidout_de <= 1;
                vidout_rgb <= diag_color;
            end
        end
    end
end




//
// audio i2s silence generator
// see other examples for actual audio generation
//

assign audio_mclk = audgen_mclk;
assign audio_dac = audgen_dac;
assign audio_lrck = audgen_lrck;

// generate MCLK = 12.288mhz with fractional accumulator
    reg         [21:0]  audgen_accum;
    reg                 audgen_mclk;
    parameter   [20:0]  CYCLE_48KHZ = 21'd122880 * 2;
always @(posedge clk_74a) begin
    audgen_accum <= audgen_accum + CYCLE_48KHZ;
    if(audgen_accum >= 21'd742500) begin
        audgen_mclk <= ~audgen_mclk;
        audgen_accum <= audgen_accum - 21'd742500 + CYCLE_48KHZ;
    end
end

// generate SCLK = 3.072mhz by dividing MCLK by 4
    reg [1:0]   aud_mclk_divider;
    wire        audgen_sclk = aud_mclk_divider[1] /* synthesis keep*/;
    reg         audgen_lrck_1;
always @(posedge audgen_mclk) begin
    aud_mclk_divider <= aud_mclk_divider + 1'b1;
end

// shift out audio data as I2S 
// 32 total bits per channel, but only 16 active bits at the start and then 16 dummy bits
//
    reg     [4:0]   audgen_lrck_cnt;    
    reg             audgen_lrck;
    reg             audgen_dac;
always @(negedge audgen_sclk) begin
    audgen_dac <= 1'b0;
    // 48khz * 64
    audgen_lrck_cnt <= audgen_lrck_cnt + 1'b1;
    if(audgen_lrck_cnt == 31) begin
        // switch channels
        audgen_lrck <= ~audgen_lrck;
        
    end 
end


///////////////////////////////////////////////


    wire    clk_core_12288;
    wire    clk_core_12288_90deg;
    
    wire    pll_core_locked;
    // status_boot_done/status_setup_done (below) shouldn't report ready
    // until *both* PLLs - this one and dragon_pll - are locked
    wire    pll_all_locked = pll_core_locked & pll_dragon_locked;
    wire    pll_core_locked_s;
synch_3 s01(pll_all_locked, pll_core_locked_s, clk_74a);

mf_pllbase mp1 (
    .refclk         ( clk_74a ),
    .rst            ( 0 ),
    
    .outclk_0       ( clk_core_12288 ),
    .outclk_1       ( clk_core_12288_90deg ),
    
    .locked         ( pll_core_locked )
);


    
endmodule
