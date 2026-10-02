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

    reg             target_dataslot_read = 1'b0;
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
//
// WRITE_MEM_CLOCK_DELAY/WRITE_MEM_EN_CYCLE_LENGTH: originally copied
// PokemonMini's (12, 5) verbatim, but that core's clk_memory runs at
// 40MHz - ours (clk_dragon) is only 14.85MHz (see dragon_pll.v), so 12
// cycles there took ~808ns against APF's ~1010ns-per-word bridge cadence
// (data_loader.sv's own comment) - only ~20% margin. A hardware test
// showed the CPU stuck forever re-fetching its own reset vector
// ($FFFE/$FFFF, the very last 2 bytes of the 16KB ROM) - consistent with
// the transfer falling cumulatively behind and corrupting whatever
// arrived last. Dropped to (4, 1), data_loader.sv's own documented
// minimum, for maximum margin (~269ns, comfortably under 1010ns).

    wire            rom_wr;
    wire    [13:0]  rom_addr;
    wire    [7:0]   rom_data;

data_loader #(
    .ADDRESS_MASK_UPPER_4 ( 4'h0 ),
    .ADDRESS_SIZE         ( 14 ),
    .WRITE_MEM_CLOCK_DELAY( 4 ),
    .WRITE_MEM_EN_CYCLE_LENGTH( 1 )
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

// Cassette (.cas) loading. Two independent delivery paths, since a
// hardware test proved the platform doesn't always use the one the first
// two attempts assumed - see BUILD_LOG.md for the full trail. Whichever
// one actually fires for a given user action is the one that matters;
// both feed the same cas_ram/cas_len/cas_new_file downstream.
//
// Path 1 - boot-time / pre-selected file: mirrors the boot ROM's own
// mechanism exactly - plain bridge writes into this slot's own declared
// data.json address ("0x10000000"). A hardware test showed this is the
// path actually used (dataslot_update never fired at all, even before
// CLOAD was typed - the "red, right from boot" diagnostic result) when a
// cassette file is selected as part of launching the core, or remembered
// from a previous session. No clean "transfer complete" signal exists
// for this path, so cas_boot_len just tracks the highest written address
// seen + 1, continuously - harmless even though this "restarts" the file
// position on every single byte while it arrives, since cas_player stays
// idle (motor off, BASIC hasn't run CLOAD yet) for the whole, brief,
// very-early window this delivery actually happens in.
    wire            cas_boot_wr;
    wire    [15:0]  cas_boot_wr_addr;
    wire    [7:0]   cas_boot_wr_data;

data_loader #(
    .ADDRESS_MASK_UPPER_4 ( 4'h1 ),
    .ADDRESS_SIZE         ( 16 ),
    .WRITE_MEM_CLOCK_DELAY( 4 ),
    .WRITE_MEM_EN_CYCLE_LENGTH( 1 )
) cas_boot_data_loader (
    .clk_74a               ( clk_74a ),
    .clk_memory             ( clk_dragon ),

    .bridge_wr              ( bridge_wr ),
    .bridge_endian_little   ( bridge_endian_little ),
    .bridge_addr            ( bridge_addr ),
    .bridge_wr_data         ( bridge_wr_data ),

    .write_en   ( cas_boot_wr ),
    .write_addr ( cas_boot_wr_addr ),
    .write_data ( cas_boot_wr_data )
);

// Path 2 - live reload while the core is already running (this slot's
// "parameters": 11 sets the User Reloadable bit, for picking a different
// file from the running core's interact menu). Confirmed against
// Analogue's own host/target-command docs: for this case the platform
// does NOT push bytes via plain bridge writes - it only fires
// dataslot_update with the new file's size, and the core has to
// explicitly issue a target_dataslot_read request into a bridge scratch
// address of its own choosing, then wait for target_dataslot_ack and
// target_dataslot_done. This state machine runs on clk_74a, matching
// core_bridge_cmd's own domain. 0x60000000 is the scratch address chosen
// (arbitrary but conventional - e.g. OpenFPGA_ZX-Spectrum's own
// on-demand loader uses the same address for the same purpose). Requests
// the whole file in one shot - no documented hard per-request size
// limit, and real Dragon 32 tape files are nowhere near this buffer's
// 64KB.
    localparam CAS_LOAD_IDLE      = 2'd0;
    localparam CAS_LOAD_WAIT_ACK  = 2'd1;
    localparam CAS_LOAD_WAIT_DONE = 2'd2;

    reg [1:0]  cas_load_state = CAS_LOAD_IDLE;
    reg        dataslot_update_74a_prev = 1'b0;
    reg        cas_ready_toggle_74a = 1'b0;
    reg [31:0] cas_loaded_size_74a = 32'd0;

always @(posedge clk_74a) begin
    dataslot_update_74a_prev <= dataslot_update;

    case (cas_load_state)
        CAS_LOAD_IDLE: begin
            if (dataslot_update && !dataslot_update_74a_prev && dataslot_update_id == 16'd1) begin
                target_dataslot_id         <= 16'd1;
                target_dataslot_slotoffset <= 32'd0;
                target_dataslot_bridgeaddr <= 32'h60000000;
                target_dataslot_length     <= dataslot_update_size;
                cas_loaded_size_74a        <= dataslot_update_size;
                target_dataslot_read       <= 1'b1;
                cas_load_state             <= CAS_LOAD_WAIT_ACK;
            end
        end
        CAS_LOAD_WAIT_ACK: begin
            if (target_dataslot_ack) begin
                target_dataslot_read <= 1'b0;
                cas_load_state       <= CAS_LOAD_WAIT_DONE;
            end
        end
        CAS_LOAD_WAIT_DONE: begin
            if (target_dataslot_done) begin
                // Toggle (not a one-cycle pulse) crossing clk_74a ->
                // clk_dragon - a single-cycle pulse risks being missed
                // entirely by an asynchronous receiving clock domain;
                // an edge on a synchronized toggle bit can't be missed
                // the same way. cas_loaded_size_74a is plain multi-bit
                // synchronized below, safe here since it's held stable
                // from well before this toggle edge until well after.
                cas_ready_toggle_74a <= ~cas_ready_toggle_74a;
                cas_load_state       <= CAS_LOAD_IDLE;
            end
        end
        default: cas_load_state <= CAS_LOAD_IDLE;
    endcase
end

    wire        cas_ready_toggle_dragon;
    wire [31:0] cas_loaded_size_dragon;
synch_3 s_cas_ready (cas_ready_toggle_74a, cas_ready_toggle_dragon, clk_dragon);
synch_3 #(.WIDTH(32)) s_cas_size (cas_loaded_size_74a, cas_loaded_size_dragon, clk_dragon);

    reg         cas_ready_toggle_dragon_prev = 1'b0;
    wire        cas_live_new_file = (cas_ready_toggle_dragon != cas_ready_toggle_dragon_prev);

    wire            cas_live_wr;
    wire    [15:0]  cas_live_wr_addr;
    wire    [7:0]   cas_live_wr_data;

data_loader #(
    .ADDRESS_MASK_UPPER_4 ( 4'h6 ),
    .ADDRESS_SIZE         ( 16 ),
    .WRITE_MEM_CLOCK_DELAY( 4 ),
    .WRITE_MEM_EN_CYCLE_LENGTH( 1 )
) cas_live_data_loader (
    .clk_74a               ( clk_74a ),
    .clk_memory             ( clk_dragon ),

    .bridge_wr              ( bridge_wr ),
    .bridge_endian_little   ( bridge_endian_little ),
    .bridge_addr            ( bridge_addr ),
    .bridge_wr_data         ( bridge_wr_data ),

    .write_en   ( cas_live_wr ),
    .write_addr ( cas_live_wr_addr ),
    .write_data ( cas_live_wr_data )
);

// Both paths share one cas_ram write port and one cas_len/cas_new_file -
// only one path is ever actually active for a given real user action, so
// a simple priority mux (boot path first) is enough; there's no real
// scenario where both fire in the same cycle.
    wire        cas_wr      = cas_boot_wr | cas_live_wr;
    wire [15:0] cas_wr_addr = cas_boot_wr ? cas_boot_wr_addr : cas_live_wr_addr;
    wire [7:0]  cas_wr_data = cas_boot_wr ? cas_boot_wr_data : cas_live_wr_data;
    wire        cas_new_file = cas_boot_wr | cas_live_new_file;

    reg  [15:0] cas_len = 16'd0;
always @(posedge clk_dragon) begin
    if (cas_boot_wr && (cas_boot_wr_addr + 16'd1 > cas_len))
        cas_len <= cas_boot_wr_addr + 16'd1;
    else if (cas_live_new_file)
        cas_len <= cas_loaded_size_dragon[15:0];
end

    wire [15:0] cas_addr;
    wire [7:0]  cas_data;
    wire        dragon_casdout;
    wire        dragon_cas_relay;
    wire [11:0] dragon_sound;   // see "audio output" below
    wire        dragon_sndout;

cas_ram #(.ADDR_WIDTH(16)) u_cas_ram (
    .clk      ( clk_dragon  ),
    .wr_en    ( cas_wr      ),
    .wr_addr  ( cas_wr_addr ),
    .wr_data  ( cas_wr_data ),
    .rd_addr  ( cas_addr    ),
    .rd_data  ( cas_data    )
);

cas_player u_cas_player (
    .clk       ( clk_dragon       ),
    .reset     ( ~reset_n_dragon  ),
    .motor_on  ( dragon_cas_relay ),
    .new_file  ( cas_new_file     ),
    .cas_len   ( cas_len          ),
    .cas_addr  ( cas_addr         ),
    .cas_data  ( cas_data         ),
    .casdout   ( dragon_casdout   )
);

// The Dragon 32 machine itself - ported from MiSTer's CoCo2_MiSTer as-is
// (see NOTES.md for the full inventory). Phase 1 scope only: get it
// booting to the BASIC prompt with a real picture. Audio is the 6-bit DAC
// plus 1-bit sound, see "audio output" below. Keyboard input (phase 3) uses the Pocket's docked
// USB keyboard, via apf2hid.sv + dragon/usbkbd/dragon_keyboard.sv - see
// that file's header for the full architecture writeup (why it doesn't
// use dragoncoco.sv's own ps2_key port).

    wire [7:0]  dragon_red, dragon_green, dragon_blue;
    wire        dragon_hblank, dragon_vblank, dragon_hsync, dragon_vsync;
    wire        dragon_vclk;

// cont3_key/cont3_joy/cont3_trig are APF bridge inputs, not natively in
// clk_dragon's domain (documented "synchronous to clk_74a" at this file's
// own port list) - synchronized the same way reset_n is above, before
// apf2hid.sv re-registers them again internally. A torn/mid-transition
// sample here just self-corrects on the next clk_dragon cycle once the
// source has settled, since dragon_keyboard.sv re-derives the whole
// matrix from the live snapshot every cycle rather than tracking discrete
// press/release events - no persistent state for a torn sample to corrupt.
    wire [31:0] cont3_key_s;
    wire [31:0] cont3_joy_s;
    wire [15:0] cont3_trig_s;
synch_3 #(.WIDTH(32)) s_cont3_key  (cont3_key,  cont3_key_s,  clk_dragon);
synch_3 #(.WIDTH(32)) s_cont3_joy  (cont3_joy,  cont3_joy_s,  clk_dragon);
synch_3 #(.WIDTH(16)) s_cont3_trig (cont3_trig, cont3_trig_s, clk_dragon);

    wire [7:0] hid_mod, hid_sc1, hid_sc2, hid_sc3, hid_sc4, hid_sc5, hid_sc6;

apf2hid u_apf2hid (
    .clk        ( clk_dragon    ),
    .reset      ( ~reset_n_dragon ),
    .cont3_key  ( cont3_key_s   ),
    .cont3_joy  ( cont3_joy_s   ),
    .cont3_trig ( cont3_trig_s  ),
    .usb_kb_hid (               ),
    .usb_kb_mod ( hid_mod       ),
    .usb_kb_sc1 ( hid_sc1       ),
    .usb_kb_sc2 ( hid_sc2       ),
    .usb_kb_sc3 ( hid_sc3       ),
    .usb_kb_sc4 ( hid_sc4       ),
    .usb_kb_sc5 ( hid_sc5       ),
    .usb_kb_sc6 ( hid_sc6       )
);

// Joystick support: dragoncoco.sv's own vendored dac.sv module already
// emulates the real DAC+comparator timing protocol Dragon software's
// joystick-read routine expects (a 6-bit DAC value walked up until it
// exceeds the joystick's position, time-multiplexed across both sticks'
// axes via SELA/SELB - see dac.sv's own header table) - this only needs
// to keep joya1/joya2 continuously fed with a plain 0-255-per-axis
// position (dac.sv only ever compares the top 6 bits) and a fire-button
// bit, matching exactly what dragoncoco.sv's own joy_use_dpad branch
// already does internally for digital-only input. cont1_key/cont1_joy
// etc. are APF bridge inputs, not natively in clk_dragon's domain - same
// synchronization treatment as cont3_key/joy/trig above.
    wire [31:0] cont1_key_s, cont2_key_s;
    wire [31:0] cont1_joy_s, cont2_joy_s;
synch_3 #(.WIDTH(32)) s_cont1_key (cont1_key, cont1_key_s, clk_dragon);
synch_3 #(.WIDTH(32)) s_cont2_key (cont2_key, cont2_key_s, clk_dragon);
synch_3 #(.WIDTH(32)) s_cont1_joy (cont1_joy, cont1_joy_s, clk_dragon);
synch_3 #(.WIDTH(32)) s_cont2_joy (cont2_joy, cont2_joy_s, clk_dragon);

// D-pad presses drive the axis to a hard extreme, overriding the analog
// stick - lets either control method work with no menu setting. Pocket's
// own dpad_up/down/left/right bit order (key bitmap comment at this
// file's own port list, above) doesn't match dragoncoco's right/left/
// down/up joy_use_dpad convention, but that mode isn't used here at all
// (joy_use_dpad tied to 0 below) - only this file's own mux matters.
    wire [7:0] joy1_x = cont1_key_s[3] ? 8'd255 : cont1_key_s[2] ? 8'd0 : cont1_joy_s[7:0];
    wire [7:0] joy1_y = cont1_key_s[1] ? 8'd255 : cont1_key_s[0] ? 8'd0 : cont1_joy_s[15:8];
    wire [7:0] joy2_x = cont2_key_s[3] ? 8'd255 : cont2_key_s[2] ? 8'd0 : cont2_joy_s[7:0];
    wire [7:0] joy2_y = cont2_key_s[1] ? 8'd255 : cont2_key_s[0] ? 8'd0 : cont2_joy_s[15:8];

// TEMPORARY DIAGNOSTIC - cassette load still hangs on CLOAD after the
// target_dataslot_read fix (see BUILD_LOG.md). The first hardware test
// with this diagnostic came back solid red, even before CLOAD ran -
// meaning dataslot_update (the live-reload path) never fired at all,
// which is what led to adding the boot-time path back above. Small
// top-right corner patch, real video everywhere else, so the hang
// itself stays visible the whole time this is checked.
//
// Sticky "ever happened" latches, checked in priority order (earliest
// failure wins) - primary/neutral colors only:
//   RED    - neither delivery path ever triggered at all - the file
//            select action itself never reached here, via either path
//   ORANGE - the live-reload path (dataslot_update) is the one that
//            triggered, but target_dataslot_ack never came back
//   YELLOW - ack came back, but target_dataslot_done never fired
//   BLUE   - the file arrived (either path), but cas_new_file never
//            reached clk_dragon - a CDC bug in the toggle crossing
//   WHITE  - cas_new_file fired (cas_len should be set), but motor_on
//            (cas_relay) never asserts - BASIC never turned the tape
//            motor on, unrelated to loading itself
//   BLACK  - motor asserted, but casdout never toggled - a cas_player bug
//   GREEN  - casdout did toggle - the pipeline is fine, so the remaining
//            problem is in the file's own content/format, or how CLOAD
//            interprets it, not in delivery
// cas_boot_wr is itself already in the clk_dragon domain (data_loader's
// write_en is driven inside its own "always @(posedge clk_memory)", not
// clk_74a - confirmed by reading pocket_utils/data_loader.sv directly),
// so its sticky latch belongs with the other clk_dragon-domain latches
// below, not synchronized from a clk_74a copy that would never see it.
    reg dbg_update_seen_74a  = 1'b0;
    reg dbg_ack_seen_74a     = 1'b0;
    reg dbg_done_seen_74a    = 1'b0;
always @(posedge clk_74a) begin
    if (dataslot_update && dataslot_update_id == 16'd1) dbg_update_seen_74a <= 1'b1;
    if (target_dataslot_ack)  dbg_ack_seen_74a  <= 1'b1;
    if (target_dataslot_done) dbg_done_seen_74a <= 1'b1;
end

    wire dbg_update_seen, dbg_ack_seen, dbg_done_seen;
synch_3 s_dbg_update  (dbg_update_seen_74a,  dbg_update_seen,  clk_dragon);
synch_3 s_dbg_ack     (dbg_ack_seen_74a,     dbg_ack_seen,     clk_dragon);
synch_3 s_dbg_done    (dbg_done_seen_74a,    dbg_done_seen,    clk_dragon);

    reg dbg_boot_wr_seen  = 1'b0;
    reg dbg_new_file_seen = 1'b0;
    reg dbg_motor_seen    = 1'b0;
    reg dbg_casdout_toggled = 1'b0;
    reg dbg_casdout_prev  = 1'b0;
always @(posedge clk_dragon) begin
    if (cas_boot_wr) dbg_boot_wr_seen <= 1'b1;
    if (cas_new_file) dbg_new_file_seen <= 1'b1;
    if (dragon_cas_relay) dbg_motor_seen <= 1'b1;
    dbg_casdout_prev <= dragon_casdout;
    if (dragon_casdout != dbg_casdout_prev) dbg_casdout_toggled <= 1'b1;
end

// The checks above are all sticky ("did this ever happen") - fine for
// catching a pipeline that never starts, but a hardware test showed
// CLOAD progressing further this time (reaching "F TEST", i.e. finding
// the filename) then hanging with no further progress - a stall
// *partway through*, which a purely sticky "casdout toggled at least
// once" check can't distinguish from "still actively working". This
// watchdog resets whenever cas_addr (the tape player's read position)
// changes, and flags a stall if it hasn't moved in ~1 second despite the
// motor being on and the read not yet having reached the end of the file.
    reg  [15:0] cas_addr_prev = 16'hFFFF;
    reg  [23:0] cas_stall_watchdog = 24'd0;
always @(posedge clk_dragon) begin
    cas_addr_prev <= cas_addr;
    if (cas_addr != cas_addr_prev) begin
        cas_stall_watchdog <= 24'd0;
    end else if (cas_stall_watchdog != {24{1'b1}}) begin
        cas_stall_watchdog <= cas_stall_watchdog + 1'b1;
    end
end
    // Distinguishes "fully consumed the whole file" from "still working" -
    // a hardware test came back green (not cyan) after 60+ seconds with no
    // visible screen change, which the old green branch couldn't tell
    // apart: it means either one. If cas_addr has actually reached the
    // last valid position, the tape side is done and the real hang is in
    // whatever Color BASIC does *after* reading the data (EOF detection,
    // returning to the "OK" prompt) - not in cas_player/cas_ram at all.
    wire dbg_cas_at_end = (cas_len != 16'd0) && (cas_addr >= cas_len - 16'd1);
    wire dbg_cas_stalled = dbg_motor_seen && (cas_len != 16'd0) && !dbg_cas_at_end
                         && (cas_stall_watchdog > 24'd14_850_000); // ~1s @ clk_dragon

    wire dbg_arrived = dbg_boot_wr_seen | dbg_update_seen;
    // ack/done are only meaningful for the live-reload path - skip them
    // (fall straight through to the new_file/motor/casdout checks) if
    // the boot-time path is the one that actually delivered the file.
    wire [23:0] cas_diag_color =
        ~dbg_arrived                                          ? 24'hFF0000 : // red
        (dbg_update_seen && !dbg_boot_wr_seen && ~dbg_ack_seen)  ? 24'hFF8000 : // orange
        (dbg_update_seen && !dbg_boot_wr_seen && ~dbg_done_seen) ? 24'hFFFF00 : // yellow
        ~dbg_new_file_seen ? 24'h0000FF : // blue
        ~dbg_motor_seen    ? 24'hFFFFFF : // white
        ~dbg_casdout_toggled ? 24'h000000 : // black
        dbg_cas_stalled      ? 24'h00FFFF : // cyan: started, then stalled mid-file
        dbg_cas_at_end       ? 24'hFF00FF : // magenta: fully read the whole file already
                               24'h00FF00;  // green: still actively progressing, below the end

    wire [8:0] dragon_h_count, dragon_v_count;
    // dragon_h_count/v_count are RAW mc6847pace counters spanning the
    // whole raster (front porch/sync/back porch/border/video/border), not
    // relative to the active video window - H_LEFT_BORDER=148/H_VIDEO=404
    // and V2_TOP_BORDER=43/V2_VIDEO=235 (mc6847pace.vhd's own constants)
    // mark where the real 256x192 active area starts/ends. This patch is
    // the top-right 32x32 corner OF THE ACTIVE AREA: h in [372,403], v in
    // [43,74].
    wire cas_diag_patch = (dragon_h_count >= 9'd372) && (dragon_h_count < 9'd404)
                        && (dragon_v_count >= 9'd43)  && (dragon_v_count < 9'd75);

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

    .vclk           ( dragon_vclk ),
    .clk_Q_out      (  ),

    .artifact_phase ( 1'b0 ),
    .artifact_enable( 1'b0 ),
    .overscan       ( 1'b0 ),

    .uart_din       ( 1'b0 ),

    // ps2_key is unused - see dragon_keyboard's instantiation inside
    // dragoncoco.sv for the real (USB HID) keyboard input path
    .ps2_key        ( 11'b0 ),
    .hid_mod        ( hid_mod ),
    .hid_sc1        ( hid_sc1 ),
    .hid_sc2        ( hid_sc2 ),
    .hid_sc3        ( hid_sc3 ),
    .hid_sc4        ( hid_sc4 ),
    .hid_sc5        ( hid_sc5 ),
    .hid_sc6        ( hid_sc6 ),

    // controller input - joy1[4]/joy2[4] are the only bits dragoncoco.sv
    // reads unconditionally (the fire button, wired through to
    // dragon_keyboard.sv's joystick_1_button/joystick_2_button); joy1/2's
    // other bits are only consulted when joy_use_dpad=1, which isn't the
    // case here (joy1_x/y above already fold the d-pad into the analog
    // value), so they're left 0.
    .joy1           ( {11'b0, cont1_key_s[4], 4'b0} ),
    .joy2           ( {11'b0, cont2_key_s[4], 4'b0} ),
    .joya1          ( {joy1_x, joy1_y} ),
    .joya2          ( {joy2_x, joy2_y} ),
    .joy_use_dpad   ( 1'b0 ),

    .ioctl_data     ( rom_data ),
    .ioctl_addr     ( {2'b00, rom_addr} ),
    .ioctl_download ( 1'b0 ),
    .ioctl_wr       ( rom_wr ),
    .ioctl_index    ( 16'h0040 ),
    .roms_loaded    (  ),
    .roms_reset     ( ~reset_n_dragon ),

    // tape (.cas loading) - see cassette/cas_player.sv above
    .casdout        ( dragon_casdout   ),
    .cas_relay      ( dragon_cas_relay ),

    // audio - mixed and sent to the Pocket below (see "audio output")
    .cass_snd       ( 12'b0 ),
    .sound          ( dragon_sound  ),
    .sndout         ( dragon_sndout ),

    .v_count        ( dragon_v_count ),
    .h_count        ( dragon_h_count ),
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

// Real video, via a frame buffer that decouples the scaler's output
// timing from the Dragon's own real, very slow pixel rate (~1.86MHz
// vclk, ~15 FPS - see video_frame_buffer.sv's header). Driving
// video_rgb_clock from clk_dragon directly (an earlier version of this
// file did) made the scaler sample 8x faster than real pixels change,
// showing up as severely oversized/stretched text. Driving it straight
// from dragon_vclk (a later version did) fixed that, and worked fine
// docked - but undocked, the Pocket's built-in screen (30-62Hz minimum,
// per Analogue's published specs) showed random static/no pattern, since
// the real ~15Hz frame rate is below what its scaler can achieve sync
// lock on at all. video_frame_buffer.sv captures each real pixel at its
// native rate and re-scans it out at a clean, fixed ~46Hz instead - see
// that file for the full writeup.
wire        video_dot_clk, video_dot_clk_90;
wire [23:0] video_fb_rgb;
wire        video_fb_de, video_fb_hsync, video_fb_vsync;

video_frame_buffer vid_fb (
    .wr_clk         ( clk_dragon ),
    .wr_pixel_en    ( dragon_vclk ),
    .wr_red         ( dragon_red ),
    .wr_green       ( dragon_green ),
    .wr_blue        ( dragon_blue ),
    .wr_hblank      ( dragon_hblank ),
    .wr_vblank      ( dragon_vblank ),
    .wr_vsync       ( dragon_vsync ),

    .wr_overlay_en    ( cas_diag_patch ),
    .wr_overlay_color ( cas_diag_color ),

    .rd_ref_clk     ( clk_core_12288 ),
    .rd_ref_clk_90  ( clk_core_12288_90deg ),
    .dot_clk        ( video_dot_clk ),
    .dot_clk_90     ( video_dot_clk_90 ),
    .rd_rgb         ( video_fb_rgb ),
    .rd_de          ( video_fb_de ),
    .rd_hsync       ( video_fb_hsync ),
    .rd_vsync       ( video_fb_vsync )
);

assign video_rgb_clock = video_dot_clk;
assign video_rgb_clock_90 = video_dot_clk_90;
assign video_rgb = video_fb_rgb;
assign video_de = video_fb_de;
assign video_skip = 1'b0;
assign video_vs = video_fb_vsync;
assign video_hs = video_fb_hsync;




//
// audio output
//
// Two real Dragon sound sources, summed: the 6-bit DAC (PIA1 port A
// bits 7:2, routed through the analog mux when SND is enabled and
// SELA/SELB=00 - dac.sv puts it in dragon_sound[11:6]) and the 1-bit
// "beeper" (PIA1 port B bit 1). Sent as unsigned 15-bit mono: DAC full
// scale = 4095<<2 = 16380, beeper adds 4096, so max 20476 - headroom
// left, no clipping.
//
// Pitch caveat: the whole machine runs at ~1/4 real speed (clk_dragon
// 14.85MHz vs the 57.27MHz design reference - see dragon_pll.v), and
// Dragon software makes tones with CPU timing loops, so everything will
// sound ~2 octaves low until the machine runs at full speed.
//

    reg  [14:0] audio_sample;
always @(posedge clk_dragon) begin
    audio_sample <= {1'b0, dragon_sound, 2'b00} + (dragon_sndout ? 15'd4096 : 15'd0);
end

sound_i2s #(
    .CHANNEL_WIDTH ( 15 ),
    .SIGNED_INPUT  ( 0 )
) u_sound_i2s (
    .clk_74a    ( clk_74a      ),
    .clk_audio  ( clk_dragon   ),
    .audio_l    ( audio_sample ),
    .audio_r    ( audio_sample ),
    .audio_mclk ( audio_mclk   ),
    .audio_lrck ( audio_lrck   ),
    .audio_dac  ( audio_dac    )
);


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
