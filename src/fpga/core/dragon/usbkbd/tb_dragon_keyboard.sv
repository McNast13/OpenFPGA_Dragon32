module tb_dragon_keyboard;
    reg clk = 0;
    always #10 clk = ~clk;

    reg [7:0] hid_mod = 0;
    reg [7:0] sc1=0, sc2=0, sc3=0, sc4=0, sc5=0, sc6=0;
    reg [7:0] addr = 8'hFF;
    wire [7:0] kb_rows;
    reg        osd_valid = 0, osd_shift = 0;
    reg  [2:0] osd_row = 0, osd_col = 0;

    dragon_keyboard dut (
        .clk_sys(clk), .reset(1'b0),
        .hid_mod(hid_mod),
        .hid_sc1(sc1), .hid_sc2(sc2), .hid_sc3(sc3),
        .hid_sc4(sc4), .hid_sc5(sc5), .hid_sc6(sc6),
        .osd_key_valid(osd_valid), .osd_key_row(osd_row), .osd_key_col(osd_col), .osd_shift(osd_shift),
        .addr(addr), .kb_rows(kb_rows),
        .joystick_1_button(1'b0), .joystick_2_button(1'b0), .joystick_hilo(1'b0)
    );

    integer failures = 0;

    task check(input string name, input [7:0] col_select, input [7:0] expect_rows);
        begin
            addr = col_select;
            #20;
            if (kb_rows !== expect_rows) begin
                $display("FAIL %s: addr=%02h expected kb_rows=%08b got %08b", name, col_select, expect_rows, kb_rows);
                failures = failures + 1;
            end else begin
                $display("PASS %s", name);
            end
        end
    endtask

    initial begin
        #5;
        // 'A' key (USB 0x04) -> row2 col1. joystick_hilo=0 ties kb_rows[7] low always.
        sc1 = 8'h04;
        check("A pressed, col1 selected", 8'b11111101, 8'b01111011);
        check("A pressed, col0 selected (not A's col)", 8'b11111110, 8'b01111111);
        sc1 = 0;
        check("A released", 8'b11111101, 8'b01111111);

        // Space (0x2C) -> row5 col7
        sc1 = 8'h2C;
        check("Space, col7 selected", 8'b01111111, 8'b01011111);
        sc1 = 0;

        // Enter (0x28) -> row6 col0
        sc1 = 8'h28;
        check("Enter, col0 selected", 8'b11111110, 8'b00111111);
        sc1 = 0;

        // Shift alone -> row6 col7
        hid_mod = 8'h02; // left shift
        check("Shift alone, col7 selected", 8'b01111111, 8'b00111111);

        // Shift + ';' (0x33) -> ':' at row1 col2, WITHOUT asserting Dragon shift
        sc1 = 8'h33;
        check("Shift+; -> Dragon colon, col2 selected", 8'b11111011, 8'b01111101);
        check("Shift+; -> shift row (col7) suppressed, stays high", 8'b01111111, 8'b01111111);
        hid_mod = 0;
        sc1 = 0;

        // Unshifted ';' -> row1 col3 (semicolon)
        sc1 = 8'h33;
        check("Unshifted ; -> Dragon semicolon, col3 selected", 8'b11110111, 8'b01111101);
        sc1 = 0;

        // Multi-key: A (row2,col1) + Z (row5,col2) simultaneously
        sc1 = 8'h04; // A
        sc2 = 8'h1D; // Z
        check("A+Z held, col1 selected -> row2 low", 8'b11111101, 8'b01111011);
        check("A+Z held, col2 selected -> row5 low", 8'b11111011, 8'b01011111);
        sc1 = 0; sc2 = 0;

        // Backspace -> Left (row5 col5)
        sc1 = 8'h2A;
        check("Backspace -> Left, col5 selected", 8'b11011111, 8'b01011111);
        sc1 = 0;

        // '=' (0x2E, unshifted) -> Dragon Shift+MINUS: row1 col5 plus forced shift
        sc1 = 8'h2E;
        check("= -> MINUS, col5 selected", 8'b11011111, 8'b01111101);
        check("= -> Dragon shift forced, col7 selected", 8'b01111111, 8'b00111111);
        sc1 = 0;

        // Shift+'=' -> '+' = Dragon Shift+; (row1 col3), shift from PC Shift
        hid_mod = 8'h20; // right shift
        sc1 = 8'h2E;
        check("Shift+= -> semicolon, col3 selected", 8'b11110111, 8'b01111101);
        check("Shift+= -> Dragon shift held, col7 selected", 8'b01111111, 8'b00111111);
        check("Shift+= -> not MINUS, col5 selected", 8'b11011111, 8'b01111111);
        hid_mod = 0;
        sc1 = 0;

        // Keypad * (0x55) -> Dragon Shift+: (row1 col2)
        sc1 = 8'h55;
        check("KP* -> colon, col2 selected", 8'b11111011, 8'b01111101);
        check("KP* -> Dragon shift forced, col7 selected", 8'b01111111, 8'b00111111);
        sc1 = 0;

        // Keypad + (0x57) -> Dragon Shift+; (row1 col3)
        sc1 = 8'h57;
        check("KP+ -> semicolon, col3 selected", 8'b11110111, 8'b01111101);
        check("KP+ -> Dragon shift forced, col7 selected", 8'b01111111, 8'b00111111);
        sc1 = 0;

        // Released: no stray shift
        check("All released, col7 selected", 8'b01111111, 8'b01111111);

        // On-screen keyboard: '*' = matrix row1 col2 + shift
        osd_valid = 1; osd_row = 3'd1; osd_col = 3'd2; osd_shift = 1;
        check("OSD * -> colon, col2 selected", 8'b11111011, 8'b01111101);
        check("OSD * -> shift, col7 selected", 8'b01111111, 8'b00111111);
        osd_valid = 0; osd_shift = 0;
        check("OSD released, col2 selected", 8'b11111011, 8'b01111111);

        if (failures == 0) $display("ALL TESTS PASSED");
        else $display("%0d TEST(S) FAILED", failures);
        $finish;
    end
endmodule
