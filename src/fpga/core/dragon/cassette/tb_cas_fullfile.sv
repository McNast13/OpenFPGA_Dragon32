// Full-file, bit-accurate regression test: encodes testdata/test.cas
// (see testdata/generate_test_cas.py for how it was built and why) and
// decodes casdout back into bytes by counting exact clk cycles between
// edges (not $realtime deltas - an earlier version of this test used
// those and had its own bug, producing false mismatches - see
// BUILD_LOG.md, 2026-09-27 "hardware test (dual-path diagnostic)").
// Confirms every byte of testdata/test.cas round-trips exactly (FILE_LEN
// below must match its current size in bytes).
//
// Run from this directory:
//   iverilog -g2012 -o tb.vvp tb_cas_fullfile.sv cas_player.sv
//   vvp tb.vvp
// (regenerate testdata/test_cas_bytes.hex after editing testdata/test.cas
// with: xxd -p testdata/test.cas | tr -d '\n' | fold -w2 > testdata/test_cas_bytes.hex
// - and update FILE_LEN below to match)
module tb_cas_fullfile;
    localparam FILE_LEN = 1396;

    reg clk = 0;
    always #10 clk = ~clk;

    reg reset = 1;
    reg motor_on = 0;
    reg new_file = 0;
    reg [15:0] cas_len = 0;
    wire [15:0] cas_addr;
    reg  [7:0]  mem [0:4095];
    wire [7:0]  cas_data = mem[cas_addr];
    wire        casdout;

    initial $readmemh("testdata/test_cas_bytes.hex", mem);

    cas_player dut (
        .clk(clk), .reset(reset), .motor_on(motor_on), .new_file(new_file),
        .cas_len(cas_len), .cas_addr(cas_addr), .cas_data(cas_data),
        .casdout(casdout)
    );

    localparam HALF_BIT1 = 11932;
    localparam HALF_BIT0 = 23864;
    localparam MID = (HALF_BIT1 + HALF_BIT0) / 2;

    reg        casdout_prev = 0;
    integer    cycles_since_edge = 0;
    integer    half_count = 0;
    integer    bit_idx = 0;
    reg [7:0]  byte_acc = 0;
    integer    byte_idx = 0;
    integer    mismatches = 0;
    integer    first_mismatch_byte = -1;
    integer    this_half_bit;
    reg        armed = 0; // ignore the first edge (no valid duration yet)
    reg        done = 0;

    always @(posedge clk) begin
        casdout_prev <= casdout;
        if (casdout !== casdout_prev) begin
            if (armed) begin
                this_half_bit = (cycles_since_edge < MID) ? 1 : 0;
                half_count = half_count + 1;
                if (half_count == 2) begin
                    half_count = 0;
                    byte_acc = {this_half_bit[0], byte_acc[7:1]};
                    bit_idx = bit_idx + 1;
                    if (bit_idx == 8) begin
                        bit_idx = 0;
                        if (byte_acc !== mem[byte_idx]) begin
                            mismatches = mismatches + 1;
                            if (first_mismatch_byte == -1) first_mismatch_byte = byte_idx;
                            $display("MISMATCH byte %0d: expected %02h got %02h", byte_idx, mem[byte_idx], byte_acc);
                        end
                        byte_idx = byte_idx + 1;
                        if (byte_idx == FILE_LEN && !done) begin
                            done = 1;
                            if (mismatches == 0) $display("ALL %0d BYTES MATCH - cas_player is bit-accurate", FILE_LEN);
                            else $display("%0d MISMATCH(ES), first at byte %0d", mismatches, first_mismatch_byte);
                            $finish;
                        end
                    end
                end
            end
            armed <= 1;
            cycles_since_edge <= 0;
        end else begin
            cycles_since_edge <= cycles_since_edge + 1;
        end
    end

    initial begin
        reset = 1; motor_on = 0; cas_len = 0;
        repeat (3) @(posedge clk);
        reset = 0;
        cas_len = FILE_LEN;
        motor_on = 1;

        #(20_000_000_000);
        $display("TIMEOUT - byte_idx reached %0d, mismatches=%0d, first at %0d", byte_idx, mismatches, first_mismatch_byte);
        $finish;
    end
endmodule
