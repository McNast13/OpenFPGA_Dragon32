//
// .cas cassette tape playback engine.
//
// A .cas file (as loaded via the "Cassette" data slot - see data.json and
// core_top.v's second data_loader instance) already contains the exact
// decoded byte stream a real cassette recording would produce once played
// back through the machine's own tape-input comparator: leader bytes,
// magic bytes, block headers, data, checksums, all literally present as
// bytes. This module's only job is the reverse of what a real cassette
// deck's read head + comparator would do: turn each byte back into the
// bit-serial waveform on dragoncoco.sv's casdout input (which feeds PIA1
// port A bit 0 directly - see dragoncoco.sv's "porta_in({6'd0,casdout})").
//
// Real Color BASIC cassette encoding (source: Chris Lomont, "Color
// Computer 1/2/3 Hardware Programming" v0.82, a public hardware
// reference - not vendor/emulator code): each bit is one full cycle of a
// tone, LSB first. '1' = one cycle at 2400 Hz, '0' = one cycle at 1200 Hz.
// Bits are recognized by the real machine on a positive-to-negative zero
// crossing, so a clean digital square wave (which is what a comparator
// would produce from a real analog signal anyway) is exactly right - no
// DAC needed.
//
// Clock-relative timing, not wall-clock timing: this machine runs
// clk_dragon at 14.85 MHz, not the ~57.272727 MHz (16x NTSC colorburst)
// dragon_pll.v documents as the "real" target - a deliberate trade for
// timing closure (see NOTES.md/dragon_pll.v). Every other clock in the
// machine (SAM's E/Q generation, the CPU's own effective instruction
// rate) is *already* a fixed divide of clk_dragon, so the whole machine
// runs uniformly slower than real hardware, self-consistently - Color
// BASIC's cassette-reading routine measures tape bit timing by counting
// its own CPU cycles between edges, and that CPU cycle rate has already
// been scaled down by the same factor clk_dragon has. So the tape
// waveform needs the same treatment: expressed as a fixed number of
// clk_dragon *cycles* per bit derived from the original 57,272,727 Hz
// design frequency divided by the tone frequency - not literal 1200/2400
// Hz relative to clk_dragon's actual (slower) rate, which would make the
// tape run fast relative to what the slowed-down CPU is measuring it
// against. This also means nothing here needs revisiting if clk_dragon's
// frequency ever changes later (e.g. if timing closure improves) - it
// scales the same way the rest of the machine already does.
//
// End of file: loops back to the start rather than going silent. A real
// cassette, even on blank/run-out tape, never produces genuine, edge-free
// silence - there's always some signal to synchronize against, and it's
// the *software's* job (via block-type/checksum checks, already present
// in Color BASIC's own CLOAD routine) to recognize unexpected/repeated
// data and stop cleanly. An idealized, permanently flat signal (this
// module's original behavior) is not something real tape hardware ever
// produces, and real hardware tests with two independent files (an ASCII
// BASIC program and a real commercial machine-code game, each loaded
// with the command appropriate to its type) both hung identically at
// "fully delivered, then nothing further" - convergent evidence pointing
// at this generic end-of-file behavior rather than either file's own
// content. See BUILD_LOG.md's cassette entries for the full trail.
//
`default_nettype none

module cas_player (
    input  wire        clk,       // clk_dragon
    input  wire        reset,

    input  wire        motor_on,  // cas_relay - real tape motor control (PIA1 CA2 out).
                                   // Pausing here (not resetting position) matches a real
                                   // tape deck: stopping the motor doesn't rewind the tape.

    input  wire        new_file,  // one-cycle pulse: the platform just finished delivering
                                   // a (possibly different) file into this slot - rewind to
                                   // the start, same as swapping the cassette in a real deck

    input  wire [15:0] cas_len,   // valid byte count in cas_ram; 0 = no tape loaded/mid-load
    output reg  [15:0] cas_addr,  // read address into cas_ram (1-cycle registered-address latency)
    input  wire  [7:0] cas_data,  // cas_ram[cas_addr], one cycle after cas_addr changes

    output reg          casdout
);

    // Half-cycle counts: (57,272,727 Hz design reference) / (tone Hz) / 2,
    // rounded to the nearest integer. Sub-0.1% rounding error, utterly
    // negligible against Color BASIC's own tape-speed tolerance.
    localparam [15:0] HALF_PERIOD_BIT1 = 16'd11932; // 2400 Hz
    localparam [15:0] HALF_PERIOD_BIT0 = 16'd23864; // 1200 Hz

    localparam [1:0] ST_IDLE      = 2'd0; // no tape, or paused (motor off) - position held
    localparam [1:0] ST_FETCH     = 2'd1; // cas_addr just changed, waiting 1 cycle for cas_data
    localparam [1:0] ST_RUN       = 2'd2; // toggling casdout for the current bit

    reg  [1:0]  state;
    reg  [7:0]  shift_reg;
    reg  [2:0]  bit_idx;
    reg  [15:0] half_period;
    reg         half_num;      // 0 = first half of this bit's cycle, 1 = second half
    reg  [15:0] toggle_cnt;

    wire tape_present = (cas_len != 16'd0);

    always @(posedge clk) begin
        if (reset || new_file || !tape_present) begin
            state      <= ST_IDLE;
            cas_addr   <= 16'd0;
            bit_idx    <= 3'd0;
            toggle_cnt <= 16'd0;
            half_num   <= 1'b0;
            casdout    <= 1'b0;
        end else if (!motor_on) begin
            // Frozen exactly where it was - no state change at all, so
            // resuming continues mid-bit/mid-byte, same as a real deck.
        end else begin
            case (state)
                ST_IDLE: begin
                    // Just gained a tape and/or motor power - fetch the
                    // byte at the current (0 unless resuming) address.
                    state <= ST_FETCH;
                end

                ST_FETCH: begin
                    shift_reg   <= cas_data;
                    half_period <= cas_data[0] ? HALF_PERIOD_BIT1 : HALF_PERIOD_BIT0;
                    toggle_cnt  <= 16'd0;
                    half_num    <= 1'b0;
                    casdout     <= 1'b0; // each bit's cycle starts low->high->low
                    state       <= ST_RUN;
                end

                ST_RUN: begin
                    if (toggle_cnt == half_period) begin
                        toggle_cnt <= 16'd0;
                        casdout    <= ~casdout;
                        if (half_num == 1'b0) begin
                            half_num <= 1'b1;
                        end else begin
                            // Completed a full cycle for this bit - advance.
                            half_num <= 1'b0;
                            if (bit_idx == 3'd7) begin
                                bit_idx <= 3'd0;
                                // End of file: loop back to the start
                                // rather than going silent - see this
                                // file's header comment for why.
                                cas_addr <= (cas_addr + 16'd1 >= cas_len) ? 16'd0 : cas_addr + 16'd1;
                                state    <= ST_FETCH;
                            end else begin
                                bit_idx   <= bit_idx + 3'd1;
                                shift_reg <= shift_reg >> 1;
                                half_period <= shift_reg[1] ? HALF_PERIOD_BIT1 : HALF_PERIOD_BIT0;
                            end
                        end
                    end else begin
                        toggle_cnt <= toggle_cnt + 16'd1;
                    end
                end

                default: state <= ST_IDLE;
            endcase
        end
    end

endmodule
