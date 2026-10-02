//
// dragon_pll.v
//
// Derives the Dragon 32 machine clock (clk_dragon) from the APF system
// reference clock (clk_74a, 74.25 MHz): 57.272727 MHz, 16x NTSC
// colorburst - the frequency the vendored CoCo2_MiSTer RTL is written
// for. The SAM (mc6883.vhd) divides it down to everything else, so the
// CPU runs at the real 0.895 MHz.
//
// Written by hand rather than generated via Quartus's MegaWizard/IP Catalog
// (not available in this environment - no local Quartus install). Follows
// the exact same pattern as the template's own mf_pllbase_0002.v: a direct
// instantiation of Quartus's altera_pll primitive with plain frequency
// strings as generics. Quartus's own Analysis & Synthesis resolves the
// actual PLL M/N/C counter values from those strings during a normal
// compile - no IP wizard needed.
//
// History: this ran at 14.85 MHz (~1/4 speed) for a while, because builds
// at 57.27 MHz failed timing by ~10 ns. Detailed reports (docs/
// SPEED_PLAN.md, BUILD_LOG.md 2026-10-02) showed that wasn't a speed
// ceiling: the failing paths were all in/around the 6809, whose registers
// only update once per 64-clock CPU cycle, being checked as if they had to
// settle in one clock. core_constraints.sdc's multicycle constraints
// describe the real timing, which closes at 57.27 MHz.
//
// Single output: an earlier 90-degree-shifted outclk_1 (for driving the
// scaler straight from clk_dragon) is gone - the scaler now runs from
// clk_core_12288 via video_frame_buffer.sv.
//
`default_nettype none

module dragon_pll (
    input  wire refclk,
    input  wire rst,
    output wire outclk_0,
    output wire locked
);

    altera_pll #(
        .fractional_vco_multiplier("true"),
        .reference_clock_frequency("74.25 MHz"),
        .operation_mode("normal"),
        .number_of_clocks(1),
        .output_clock_frequency0("57.272727 MHz"),
        .phase_shift0("0 ps"),
        .duty_cycle0(50),
        .output_clock_frequency1("0 MHz"), .phase_shift1("0 ps"), .duty_cycle1(50),
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
        .outclk   (outclk_0),
        .locked   (locked),
        .fboutclk (),
        .fbclk    (1'b0),
        .refclk   (refclk)
    );

endmodule
