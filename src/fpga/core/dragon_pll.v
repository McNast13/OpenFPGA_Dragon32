//
// dragon_pll.v
//
// Derives the Dragon 32 machine clock (~57.272727 MHz, 16x NTSC colorburst -
// a hardware constant of the real machine, unrelated to the Pocket's own
// clocking) from the APF system reference clock (clk_74a, 74.25 MHz).
//
// Written by hand rather than generated via Quartus's MegaWizard/IP Catalog
// (not available in this environment - no local Quartus install). Follows
// the exact same pattern as the template's own mf_pllbase_0002.v: a direct
// instantiation of Quartus's altera_pll primitive with plain frequency
// strings as generics ("74.25 MHz", "57.272727 MHz"). Quartus's own
// Analysis & Synthesis resolves the actual PLL M/N/C counter values from
// those strings during a normal compile - this is the same fractional-N
// synthesis the wizard would have produced, just without needing the wizard.
//
// Bit-exactness to 57.272727... MHz isn't required for phase 1 (booting to
// BASIC) - that precision matters for phase 2's video/audio timing gate,
// not this one.
//
// fractional_vco_multiplier is "false" (integer-N mode) rather than "true":
// the first attempt at this file used fractional-N synthesis to hit the
// target frequency more precisely, but CI's fitter reported a real timing
// violation inside the PLL's own internal counter hardware (worst case
// -10.1 ns setup slack on `PLL_OUTPUT_COUNTER|divclk`, vs. +77 ns on the
// template's own mf_pllbase for the equivalent node) - the delta-sigma
// fractional modulator appears to be tight at this output frequency.
// Integer-N mode has simpler internal counter logic and no such modulator.
//
// Switching modes alone wasn't enough, though: integer-N mode outright
// rejected 57.272727 MHz as an "illegal value" - that frequency reduces to
// a 280/363 ratio of the 74.25 MHz reference, not representable by small
// integer PLL counters. So the target here is deliberately 57.75 MHz
// instead: 74.25 MHz x 7/9 exactly, a clean small-integer ratio integer-N
// mode can hit precisely. That's about 0.83% faster than the real
// hardware's 57.272727 MHz - irrelevant for phase 1's gate (booting to
// BASIC), which is why this precision was never required in the first
// place (see above). Revisit this whole file in phase 2, where video/audio
// timing precision actually starts to matter.
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
    // (a quarter period at 57.75 MHz = 1e12/57750000/4 ps = ~4329 ps).
    // Needed for the scaler's DDIO output clock - see core_top.v.

    altera_pll #(
        .fractional_vco_multiplier("false"),
        .reference_clock_frequency("74.25 MHz"),
        .operation_mode("normal"),
        .number_of_clocks(2),
        .output_clock_frequency0("57.75 MHz"),
        .phase_shift0("0 ps"),
        .duty_cycle0(50),
        .output_clock_frequency1("57.75 MHz"), .phase_shift1("4329 ps"), .duty_cycle1(50),
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
