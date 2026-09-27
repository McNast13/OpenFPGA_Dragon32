//
// USB HID -> Dragon 32 keyboard matrix decoder.
//
// Takes the raw HID report bytes apf2hid.sv already extracted from the
// Pocket's docked-USB-keyboard controller slot (one modifier byte, up to
// six simultaneous scancode slots) and drives kb_rows the same way a real
// Dragon 32's keyboard matrix would, given the currently-selected column
// (kb_cols, written by the CPU through PIA0 port B).
//
// Architecture: no PS/2 intermediate step, no per-key state, re-derived
// fresh every clk_sys cycle - same approach (and same reasoning) as
// ../../../../../OpenFPGA_ZX-Spectrum/src/fpga/core/usbkbd/README.md,
// which found that tracking discrete press/release *events* (the
// MiSTer-style ps2_key[10:0] toggle+strobe convention this project's own
// vendored dragon/keyboard.sv still uses) was the root cause of an entire
// class of stuck/dropped-key bugs: a 6-slot HID report reordering which
// slot holds which key on release, races getting a toggle bit safely
// across a clock boundary, etc. Re-deriving the whole matrix from a live
// snapshot every cycle has no persistent per-key state for any of that to
// corrupt - a torn or reordered sample just self-corrects on the very next
// cycle.
//
// Dragon 32 keyboard matrix (PIA0 port A = rows, port B = columns, both
// active-low - a key pulls its row line low only while its column is
// selected):
//
//        col0   col1   col2   col3   col4   col5   col6   col7
// row0:  0      1      2      3      4      5      6      7
// row1:  8      9      :      ;      ,      -      .      /
// row2:  @      A      B      C      D      E      F      G
// row3:  H      I      J      K      L      M      N      O
// row4:  P      Q      R      S      T      U      V      W
// row5:  X      Y      Z      UP     DOWN   LEFT   RIGHT  SPACE
// row6:  ENTER  CLEAR  BREAK  -      -      -      -      SHIFT
//
// This table is a hardware fact about real 1982 Dragon 32 keyboards (not
// an expression of anyone's code), cross-checked from two independent
// sources: the general PIA0-port-A-is-rows/port-B-is-columns description
// at https://www.6809.org.uk/dragon/hardware.shtml, and XRoar's own key
// value encoding scheme (https://github.com/humblehacker/xroar,
// src/dkbd.c/dkbd.h, GPLv3) - XRoar picks its internal DSCAN_* key
// constants so that "Key values are chosen so that they directly encode
// the crosspoint locations for a normal Dragon" (row = value>>3, col =
// value&7), which decodes to exactly the grid above, including the
// specific note that Dragon's BACKSPACE has no matrix position of its own
// and reuses LEFT's. Only that factual grid was taken from XRoar; the
// decode logic below is original, written fresh for this bridge's own
// architecture.
//
`default_nettype none

module dragon_keyboard (
    input  wire        clk_sys,
    input  wire        reset,

    // Raw HID report, already synchronized into clk_sys and extracted by
    // apf2hid.sv - modifier byte plus up to six simultaneous scancode slots.
    input  wire  [7:0] hid_mod,
    input  wire  [7:0] hid_sc1,
    input  wire  [7:0] hid_sc2,
    input  wire  [7:0] hid_sc3,
    input  wire  [7:0] hid_sc4,
    input  wire  [7:0] hid_sc5,
    input  wire  [7:0] hid_sc6,

    input  wire  [7:0] addr,      // kb_cols from PIA0 port B (active-low column select)
    output reg   [7:0] kb_rows,   // to PIA0 port A (active-low row readback)

    // Real Dragon hardware reads joystick fire buttons through these same
    // two PIA0 port A bits, unconditionally (not gated by column select) -
    // matches the vendored dragon/keyboard.sv's own behaviour, preserved
    // here so joystick support (phase 3, separate from this bridge) has
    // somewhere to land later.
    input  wire         joystick_1_button,
    input  wire         joystick_2_button,
    input  wire         joystick_hilo
);

    wire shift_held = hid_mod[1] | hid_mod[5]; // left or right Shift

    // Decodes one USB HID keyboard usage ID (USB HID Usage Tables, an open
    // industry standard - not vendor code) into a Dragon matrix position.
    // {valid, suppress_shift, row[2:0], col[2:0]}
    //   valid          - this scancode maps to a Dragon key at all
    //   suppress_shift - this key's Dragon position already produces the
    //                    shifted symbol on its own (only the ;/: pair
    //                    below), so don't also assert Dragon SHIFT for it
    function automatic [7:0] hid_to_dragon(input [7:0] sc, input shifted);
        reg [2:0] row, col;
        reg       valid, supp;
        begin
            valid = 1'b1;
            supp  = 1'b0;
            row   = 3'd0;
            col   = 3'd0;
            casez (sc)
                // A-Z: USB 0x04-0x1D, alphabetical -> row2 col1-7 (A-G),
                // row3 (H-O), row4 (P-W), row5 col0-2 (X-Z)
                8'h04: begin row = 3'd2; col = 3'd1; end // A
                8'h05: begin row = 3'd2; col = 3'd2; end // B
                8'h06: begin row = 3'd2; col = 3'd3; end // C
                8'h07: begin row = 3'd2; col = 3'd4; end // D
                8'h08: begin row = 3'd2; col = 3'd5; end // E
                8'h09: begin row = 3'd2; col = 3'd6; end // F
                8'h0A: begin row = 3'd2; col = 3'd7; end // G
                8'h0B: begin row = 3'd3; col = 3'd0; end // H
                8'h0C: begin row = 3'd3; col = 3'd1; end // I
                8'h0D: begin row = 3'd3; col = 3'd2; end // J
                8'h0E: begin row = 3'd3; col = 3'd3; end // K
                8'h0F: begin row = 3'd3; col = 3'd4; end // L
                8'h10: begin row = 3'd3; col = 3'd5; end // M
                8'h11: begin row = 3'd3; col = 3'd6; end // N
                8'h12: begin row = 3'd3; col = 3'd7; end // O
                8'h13: begin row = 3'd4; col = 3'd0; end // P
                8'h14: begin row = 3'd4; col = 3'd1; end // Q
                8'h15: begin row = 3'd4; col = 3'd2; end // R
                8'h16: begin row = 3'd4; col = 3'd3; end // S
                8'h17: begin row = 3'd4; col = 3'd4; end // T
                8'h18: begin row = 3'd4; col = 3'd5; end // U
                8'h19: begin row = 3'd4; col = 3'd6; end // V
                8'h1A: begin row = 3'd4; col = 3'd7; end // W
                8'h1B: begin row = 3'd5; col = 3'd0; end // X
                8'h1C: begin row = 3'd5; col = 3'd1; end // Y
                8'h1D: begin row = 3'd5; col = 3'd2; end // Z

                // 1-9,0: USB 0x1E-0x27 -> row0 col1-7 (1-7), row1 col0-1 (8-9)
                8'h1E: begin row = 3'd0; col = 3'd1; end // 1
                8'h1F: begin row = 3'd0; col = 3'd2; end // 2
                8'h20: begin row = 3'd0; col = 3'd3; end // 3
                8'h21: begin row = 3'd0; col = 3'd4; end // 4
                8'h22: begin row = 3'd0; col = 3'd5; end // 5
                8'h23: begin row = 3'd0; col = 3'd6; end // 6
                8'h24: begin row = 3'd0; col = 3'd7; end // 7
                8'h25: begin row = 3'd1; col = 3'd0; end // 8
                8'h26: begin row = 3'd1; col = 3'd1; end // 9
                8'h27: begin row = 3'd0; col = 3'd0; end // 0

                8'h28: begin row = 3'd6; col = 3'd0; end // Enter
                8'h29: begin row = 3'd6; col = 3'd2; end // Escape -> Break
                8'h2A: begin row = 3'd5; col = 3'd5; end // Backspace -> Left (matches Dragon hardware: no dedicated matrix position)
                8'h2C: begin row = 3'd5; col = 3'd7; end // Space
                8'h2D: begin row = 3'd1; col = 3'd5; end // -/_ -> Dragon MINUS
                8'h33: begin                              // ;/: -> Dragon has separate dedicated keys, no shift needed either way
                    if (shifted) begin row = 3'd1; col = 3'd2; supp = 1'b1; end // :
                    else         begin row = 3'd1; col = 3'd3; end             // ;
                end
                8'h36: begin row = 3'd1; col = 3'd4; end // , -> Dragon COMMA
                8'h37: begin row = 3'd1; col = 3'd6; end // . -> Dragon FULL_STOP
                8'h38: begin row = 3'd1; col = 3'd7; end // / -> Dragon SLASH

                8'h4C: begin row = 3'd6; col = 3'd1; end // Delete (Fn+Backspace on most keyboards) -> Clear
                8'h4F: begin row = 3'd5; col = 3'd6; end // Right arrow
                8'h50: begin row = 3'd5; col = 3'd5; end // Left arrow
                8'h51: begin row = 3'd5; col = 3'd4; end // Down arrow
                8'h52: begin row = 3'd5; col = 3'd3; end // Up arrow

                default: valid = 1'b0;
            endcase
            hid_to_dragon = {valid, supp, row, col};
        end
    endfunction

    reg [6:0] pressed [0:7]; // pressed[col][row], active-high while decoding

    integer c, r;
    reg [7:0] d1, d2, d3, d4, d5, d6;
    reg       any_shift_suppressed;

    always @(*) begin
        d1 = hid_to_dragon(hid_sc1, shift_held);
        d2 = hid_to_dragon(hid_sc2, shift_held);
        d3 = hid_to_dragon(hid_sc3, shift_held);
        d4 = hid_to_dragon(hid_sc4, shift_held);
        d5 = hid_to_dragon(hid_sc5, shift_held);
        d6 = hid_to_dragon(hid_sc6, shift_held);

        for (c = 0; c < 8; c = c + 1)
            pressed[c] = 7'h00;

        if (d1[7]) pressed[d1[2:0]][d1[5:3]] = 1'b1;
        if (d2[7]) pressed[d2[2:0]][d2[5:3]] = 1'b1;
        if (d3[7]) pressed[d3[2:0]][d3[5:3]] = 1'b1;
        if (d4[7]) pressed[d4[2:0]][d4[5:3]] = 1'b1;
        if (d5[7]) pressed[d5[2:0]][d5[5:3]] = 1'b1;
        if (d6[7]) pressed[d6[2:0]][d6[5:3]] = 1'b1;

        // Suppress Shift only when every currently-held key that cares
        // about shift is one of the self-contained ones (like ;/:) -
        // simplification: suppress whenever *any* held key requests it.
        // A shifted ;/: chorded with an unrelated shifted key at the same
        // instant is rare enough not to matter for typing BASIC.
        any_shift_suppressed = (d1[7] & d1[6]) | (d2[7] & d2[6]) | (d3[7] & d3[6])
                              | (d4[7] & d4[6]) | (d5[7] & d5[6]) | (d6[7] & d6[6]);

        if (shift_held && !any_shift_suppressed)
            pressed[7][6] = 1'b1; // Dragon SHIFT: row6 col7

        kb_rows = 8'hFF;
        for (r = 0; r < 7; r = r + 1)
            for (c = 0; c < 8; c = c + 1)
                if (pressed[c][r] && !addr[c])
                    kb_rows[r] = 1'b0;

        if (joystick_1_button) kb_rows[1] = 1'b0;
        if (joystick_2_button) kb_rows[0] = 1'b0;
        kb_rows[7] = joystick_hilo;
    end

endmodule
