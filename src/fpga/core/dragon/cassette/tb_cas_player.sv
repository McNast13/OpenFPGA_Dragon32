module tb_cas_player;
    reg clk = 0;
    always #10 clk = ~clk; // arbitrary sim clock period, doesn't need to match real clk_dragon

    reg reset = 1;
    reg motor_on = 0;
    reg [15:0] cas_len = 0;
    wire [15:0] cas_addr;
    reg  [7:0]  mem [0:15];
    wire [7:0]  cas_data = mem[cas_addr[3:0]];
    wire        casdout;

    cas_player dut (
        .clk(clk), .reset(reset), .motor_on(motor_on),
        .new_file(1'b0), .cas_len(cas_len), .cas_addr(cas_addr), .cas_data(cas_data),
        .casdout(casdout)
    );

    integer failures = 0;
    real    t_prev;
    real    delta;

    task expect_delta(input string name, input real expect_cycles);
        real got_cycles;
        begin
            @(casdout);
            delta = $realtime - t_prev;
            t_prev = $realtime;
            got_cycles = delta / 20.0; // clk period = 20 (see always #10)
            // allow +-1 cycle for the off-by-one noted in cas_player.sv
            if (got_cycles < expect_cycles - 1.0 || got_cycles > expect_cycles + 1.0) begin
                $display("FAIL %s: expected ~%0.1f cycles, got %0.1f", name, expect_cycles, got_cycles);
                failures = failures + 1;
            end else begin
                $display("PASS %s (%0.1f cycles)", name, got_cycles);
            end
        end
    endtask

    initial begin
        mem[0] = 8'h01; // bit0=1 (2400Hz), bits1-7=0 (1200Hz each)
        mem[1] = 8'h02; // bit0=0 (1200Hz), bit1=1 (2400Hz), bits2-7=0

        reset = 1; motor_on = 0; cas_len = 0;
        repeat (3) @(posedge clk);
        reset = 0;
        repeat (3) @(posedge clk);

        // --- Test 1: single byte 0x01, bit0='1' -> first half-cycle should be HALF_PERIOD_BIT1 (11932) ---
        cas_len = 16'd1;
        motor_on = 1;
        t_prev = $realtime;
        expect_delta("byte 0x01 bit0='1' first half-cycle (incl. startup fill)", 11934.0);
        expect_delta("byte 0x01 bit0='1' second half-cycle", 11932.0);
        // bit1 (still byte 0x01, value 0) -> HALF_PERIOD_BIT0 (23864)
        expect_delta("byte 0x01 bit1='0' first half-cycle", 23864.0);
        expect_delta("byte 0x01 bit1='0' second half-cycle", 23864.0);

        // --- Test 2: motor pause mid-toggle should freeze, not skip or restart ---
        @(posedge clk); @(posedge clk); @(posedge clk); // let a few cycles pass into bit2's cycle
        motor_on = 0;
        begin : pause_check
            reg cd_before;
            integer i;
            cd_before = casdout;
            for (i = 0; i < 500; i = i + 1) begin
                @(posedge clk);
                if (casdout !== cd_before) begin
                    $display("FAIL motor pause: casdout changed while motor_on=0");
                    failures = failures + 1;
                    i = 500;
                end
            end
            $display("PASS motor pause holds casdout steady");
        end
        motor_on = 1;
        t_prev = $realtime;
        // resuming bit2 (value 0, HALF_PERIOD_BIT0) - whatever partial count had
        // already elapsed before the pause, the remaining wait should still finish
        // at some point <= a full fresh half-period from here; just confirm it
        // still eventually toggles at a 1200Hz-consistent scale (bounded check)
        @(casdout);
        delta = ($realtime - t_prev) / 20.0;
        if (delta > 23864.0 + 1.0) begin
            $display("FAIL motor resume: took %0.1f cycles, longer than a full fresh half-period", delta);
            failures = failures + 1;
        end else begin
            $display("PASS motor resume toggles within expected bound (%0.1f cycles)", delta);
        end

        // --- Test 3: end of tape (cas_len=1) - after byte 0x01 finishes (8 bits),
        // cas_addr should wrap back to 0 and playback should keep going (loop),
        // not go silent - see cas_player.sv's header for why real tape never
        // produces genuine silence and this module shouldn't either ---
        reset = 1; motor_on = 0; cas_len = 0;
        repeat (3) @(posedge clk);
        reset = 0;
        cas_len = 16'd1;
        motor_on = 1;
        // run long enough to finish all 8 bits of byte 0x01 comfortably:
        // 1 bit@2400Hz (2*11932) + 7 bits@1200Hz (7*2*23864) = ~358,872 cycles
        repeat (380000) @(posedge clk);
        if (cas_addr !== 16'd0) begin
            $display("FAIL end of tape: cas_addr should have wrapped back to 0, got %0d", cas_addr);
            failures = failures + 1;
        end else begin
            $display("PASS end of tape: cas_addr wrapped back to 0");
        end
        begin : keeps_toggling_check
            reg cd2;
            integer j;
            reg saw_toggle;
            cd2 = casdout;
            saw_toggle = 0;
            for (j = 0; j < 100000; j = j + 1) begin
                @(posedge clk);
                if (casdout !== cd2) saw_toggle = 1;
            end
            if (!saw_toggle) begin
                $display("FAIL end of tape: casdout never toggled again after wrapping - shouldn't go silent");
                failures = failures + 1;
            end else begin
                $display("PASS end of tape: casdout keeps toggling (looping), not silent");
            end
        end

        // --- Test 4: two-byte file, cas_addr should advance from 0 to 1 ---
        reset = 1; motor_on = 0; cas_len = 0;
        repeat (3) @(posedge clk);
        reset = 0;
        cas_len = 16'd2;
        motor_on = 1;
        repeat (380000) @(posedge clk); // finish byte 0
        if (cas_addr !== 16'd1) begin
            $display("FAIL cas_addr should be 1 after finishing byte 0, got %0d", cas_addr);
            failures = failures + 1;
        end else begin
            $display("PASS cas_addr advanced to 1 after byte 0 finished");
        end

        if (failures == 0) $display("ALL TESTS PASSED");
        else $display("%0d TEST(S) FAILED", failures);
        $finish;
    end
endmodule
