// Controller test for osd_keyboard.sv (navigation, key presses, Shift
// latch, hold-repeat, open/close) with short fake frames. Drawing is
// checked separately by rendering through video_frame_buffer.sv.
//
//   iverilog -g2012 -o tb.vvp tb_osd_keyboard.sv osd_keyboard.sv osd_keyboard_tables.sv
//   vvp tb.vvp
`timescale 1ns/1ns
module tb_osd_keyboard;
  reg clk=0; always #5 clk=~clk;
  reg vsync=0; integer frame=0; always begin #4000 vsync=1; frame=frame+1; #200 vsync=0; end
  reg [15:0] btn=0;
  wire oven, active, kv, ksh; wire [23:0] ovc; wire [2:0] kr,kc;
  osd_keyboard osd(.clk(clk), .btn(btn), .vsync(vsync), .px_x(8'd0), .px_y(8'd0),
    .ov_en(oven), .ov_color(ovc), .active(active), .key_valid(kv), .key_row(kr), .key_col(kc), .key_shift(ksh));
  task frames(input integer n); integer i; begin for (i=0;i<n;i=i+1) @(posedge vsync); end endtask
  task tap(input integer b, input integer hold); begin btn[b]=1; frames(hold); btn[b]=0; frames(2); end endtask
  integer fails=0;
  task expect_cursor(input [5:0] id, input string what);
    if (osd.cursor !== id) begin $display("FAIL %s: cursor %0d, expected %0d", what, osd.cursor, id); fails++; end
    else $display("PASS %s (cursor %0d)", what, id);
  endtask
  // key presses as the Dragon sees them
  reg kv_p=0; integer kv_start=0; integer nkeys=0; reg [6:0] lastkey;
  always @(posedge clk) begin
    kv_p <= kv;
    if (kv && !kv_p) begin kv_start = frame; nkeys++; lastkey={kr,kc,ksh}; $display("  key down: matrix row %0d col %0d shift %0d", kr, kc, ksh); end
    if (!kv && kv_p) $display("  key up after %0d frames, shift now %0d", frame-kv_start, ksh);
  end
  task expect_key(input [2:0] r, input [2:0] c, input s, input string what);
    if (lastkey !== {r,c,s}) begin $display("FAIL %s: got row %0d col %0d shift %0d", what, lastkey[6:4], lastkey[3:1], lastkey[0]); fails++; end
    else $display("PASS %s", what);
  endtask
  integer moves=0; reg [5:0] cur_p=0;
  always @(posedge clk) begin cur_p<=osd.cursor; if (osd.cursor!=cur_p) moves=moves+1; end

  initial begin
    frames(4);
    tap(4,2); tap(0,2);
    if (active || nkeys) begin $display("FAIL closed panel reacted"); fails++; end else $display("PASS closed: buttons ignored");
    tap(14, 2);
    if (!active) begin $display("FAIL not open"); fails++; end else $display("PASS opened");
    expect_cursor(0, "starts on '1'");
    tap(3, 2); expect_cursor(1, "right -> '2'");
    tap(1, 2); expect_cursor(14, "down -> 'Q'");
    tap(5, 2);
    if (!ksh) begin $display("FAIL shift not latched"); fails++; end else $display("PASS B latches shift");
    tap(4, 1); frames(4);
    expect_key(4, 1, 1, "A on Q with shift -> matrix Q + shift");
    if (ksh) begin $display("FAIL shift still latched after key"); fails++; end else $display("PASS shift released after key");
    tap(0, 2); expect_cursor(1, "up -> '2'");
    tap(2, 2); tap(2, 2); tap(2, 2); tap(2, 2); expect_cursor(10, "left x4 (wraps) -> ':'");
    tap(5, 2); tap(4, 2); frames(4);
    expect_key(1, 2, 1, "shift + ':' -> '*'");
    // hold A: key stays down while held
    btn[4]=1; frames(10); if (!kv) begin $display("FAIL key not held"); fails++; end else $display("PASS key held while A held");
    tap(3,2); expect_cursor(10, "d-pad ignored while key held");
    btn[4]=0; frames(2); if (kv) begin $display("FAIL key stuck"); fails++; end else $display("PASS key released");
    // SHF key via A toggles latch, no matrix key
    nkeys=0;
    tap(1,2); tap(1,2); tap(1,2); $display("  cursor after down x3 from ':' = %0d", osd.cursor);
    expect_cursor(50, "down x3 from ':' -> P, ENT, '/'");
    tap(3,2); expect_cursor(51, "right -> SHF");
    tap(4,2); if (!ksh || nkeys) begin $display("FAIL A on SHF"); fails++; end else $display("PASS A on SHF latches shift, no key");
    tap(4,2); if (ksh) begin $display("FAIL A on SHF again"); fails++; end else $display("PASS A on SHF again unlatches");
    // hold-repeat
    moves=0; btn[3]=1; frames(41); btn[3]=0; frames(2);
    if (moves==6) $display("PASS hold right 41 frames: %0d moves", moves); else begin $display("FAIL hold repeat: %0d moves", moves); fails++; end
    tap(1,2); expect_cursor(52, "down -> SPACE");
    tap(1,2); $display("  down from SPACE wraps to row 0: cursor %0d", osd.cursor);
    tap(0,2); expect_cursor(52, "up from row 0 -> SPACE");
    tap(4,2); expect_key(5, 7, 0, "SPACE");
    tap(6,2); if (!osd.at_top) begin $display("FAIL X"); fails++; end else $display("PASS X moves panel to top");
    tap(5,2); tap(14,2);
    if (active || ksh) begin $display("FAIL close"); fails++; end else $display("PASS closed, shift cleared");
    if (fails) $display("%0d FAILURES", fails); else $display("ALL PASSED");
    $finish;
  end
endmodule
