//
// dragon_pll.v
//
// Derives the Dragon 32 machine clock from the APF system reference clock
// (clk_74a, 74.25 MHz). Real hardware wants ~57.272727 MHz (16x NTSC
// colorburst) here - see below for why this drives 14.85 MHz instead, for
// now.
//
// Written by hand rather than generated via Quartus's MegaWizard/IP Catalog
// (not available in this environment - no local Quartus install). Follows
// the exact same pattern as the template's own mf_pllbase_0002.v: a direct
// instantiation of Quartus's altera_pll primitive with plain frequency
// strings as generics. Quartus's own Analysis & Synthesis resolves the
// actual PLL M/N/C counter values from those strings during a normal
// compile - no IP wizard needed.
//
// History (see BUILD_LOG.md for the full trail of CI attempts): this PLL's
// two output clocks were missing from core_constraints.sdc's asynchronous
// clock-group declaration, which caused some (not all) of a run of
// apparent timing violations - fixed there. What was left, after trying
// both fractional and integer-N synthesis at frequencies from 57.27 to
// 57.75 MHz, was real: -10ns-ish worst-case setup slack against a ~17.3ns
// period implies an actual critical path around 27ns somewhere in the
// machine (most likely mc6809i.v's combinational instruction decoder) -
// i.e. a genuine ~36MHz ceiling on this part, not a PLL configuration
// problem. That tracks: the Pocket's Cyclone V (5CEBA4F23C8, speed grade
// C8) is a smaller, slower-graded part than the Cyclone V on MiSTer's
// DE10-Nano (speed grade C6) this RTL was written against, so timing that
// closes there isn't guaranteed to close here.
//
// 14.85 MHz (74.25 MHz x 1/5, an easy ratio) gives generous headroom below
// that ~36MHz ceiling - about a quarter of the machine's intended speed,
// which only affects how fast it runs and its video refresh rate, not
// functional correctness (this is synchronous digital logic; it works the
// same at any clock rate it can meet timing at). That's an acceptable
// trade for phase 1's actual gate (booting to BASIC - digital correctness,
// not real-time speed). Revisit this in phase 2, which is explicitly about
// getting video/audio timing right (matching XRoar) - by then, a proper
// report_timing pass (this file's earlier attempts only had access to
// summary-level slack numbers, not the actual critical path) should show
// how much margin is really available and how close to 57.27MHz is safe.
//

// SPEED_PLAN.md step 1 (branch speed/step1-timing-report only): back at
// the real 57.272727 MHz, expecting timing to FAIL - this build exists to
// get detailed failing-path reports, not to be installed.
//
`default_nettype none

module dragon_pll (
    input  wire refclk,
    input  wire rst,
    output wire outclk_0,
    output wire outclk_1,
    output wire locked
);

    // outclk_1: same frequency as outclk_0, phase-shifted 90 degrees
    // (a quarter period at 57.272727 MHz = ~4365 ps).
    // Needed for the scaler's DDIO output clock - see core_top.v.

    altera_pll #(
        .fractional_vco_multiplier("true"),
        .reference_clock_frequency("74.25 MHz"),
        .operation_mode("normal"),
        .number_of_clocks(2),
        .output_clock_frequency0("57.272727 MHz"),
        .phase_shift0("0 ps"),
        .duty_cycle0(50),
        .output_clock_frequency1("57.272727 MHz"), .phase_shift1("4365 ps"), .duty_cycle1(50),
        .output_clock_frequency2("0 MHz"), .phase_shift2("0 ps"), .duty_cycle2(50),
        .output_clock_frequency3("0 MHz"), .phase_shift3("0 ps"), .duty_cycle3(50),
        .output_clock_frequency4("0 MHz"), .phase_shift4("0 ps"), .duty_cycle4(50),
        .output_clock_frequency5("0 MHz"), .phase_shift5("0 ps"), .duty_cycle5(50),
        .output_clock_frequency6("0 MHz"), .phase_shift6("0 ps"), .duty_cycle6(50),
        .output_clock_frequency7("0 MHz"), .phase_shift7("0 ps"), .duty_cycle7(50),
        .output_clock_frequency8("0 MHz"), .phase_shift8("0 ps"), .duty_cycle8(50),
        .output_clock_frequency9("0 MHz"), .phase_shift9("0 ps"), .duty_cycle9(50),
        .output_clock_frequency10("0 MHz"), .phase_shift10("0 ps"), .duty_cycle10(50),
        .output_clock_frequency11("0 MHz"), .phase_shift11("0 ps"), .duty_cycle11(50),
        .output_clock_frequency12("0 MHz"), .phase_shift12("0 ps"), .duty_cycle12(50),
        .output_clock_frequency13("0 MHz"), .phase_shift13("0 ps"), .duty_cycle13(50),
        .output_clock_frequency14("0 MHz"), .phase_shift14("0 ps"), .duty_cycle14(50),
        .output_clock_frequency15("0 MHz"), .phase_shift15("0 ps"), .duty_cycle15(50),
        .output_clock_frequency16("0 MHz"), .phase_shift16("0 ps"), .duty_cycle16(50),
        .output_clock_frequency17("0 MHz"), .phase_shift17("0 ps"), .duty_cycle17(50),
        .pll_type("General"),
        .pll_subtype("General")
    ) altera_pll_i (
        .rst      (rst),
        .outclk   ({outclk_1, outclk_0}),
        .locked   (locked),
        .fboutclk (),
        .fbclk    (1'b0),
        .refclk   (refclk)
    );

endmodule
