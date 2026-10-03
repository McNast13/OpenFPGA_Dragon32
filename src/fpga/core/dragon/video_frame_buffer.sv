//
// Frame buffer + fixed-rate scan-out generator, used to decouple the
// scaler's video_rgb_clock/hs/vs/de timing from the Dragon's own real,
// very slow pixel rate.
//
// Why this exists: dragoncoco.sv's real VDG pixel clock (vclk, ~1.86MHz -
// see core_top.v's old comment on video_rgb_clock=dragon_vclk) yields an
// actual frame rate around 15 FPS (H_TOTAL_PER_LINE=463 x
// V2_TOTAL_PER_FIELD=262 vclk ticks per frame in mc6847pace.vhd). Driving
// the scaler directly at that rate worked fine docked (HDMI, confirmed
// "looks perfect!" in phase 1), but undocked - the Pocket's own built-in
// LCD, which only supports 30-62Hz per Analogue's published specs - showed
// random static/no pattern, consistent with the scaler's receiver never
// achieving sync lock at a refresh rate that low.
//
// The fix: write every real Dragon pixel into a small frame buffer at its
// own native rate, and continuously re-scan that buffer out to the scaler
// with its own clean, regular timing.
//
// Since SPEED_PLAN steps 1-4 and 8 the machine runs at real speed with
// UK 50 Hz frames (49.93 Hz), so the read side now runs at exactly the
// Dragon's frame rate and is frame-locked to it (SPEED_PLAN step 6) - see
// the read-side comment below. It used to free-run at ~46 Hz from
// clk_core_12288, which dropped frames and tore.
//
// This mirrors the sibling OpenFPGA_ZX-Spectrum project's own approach
// (video_rgb_clock driven from a derived/gated pix_clk, not a raw PLL
// output) - a derived clock isn't itself the problem; too low a refresh
// rate is.
//
`default_nettype none

module video_frame_buffer (
    // write side - real Dragon video, clk_dragon domain
    input  wire        wr_clk,       // clk_dragon
    input  wire        wr_pixel_en,  // dragon's vclk - one tick per real pixel
    input  wire [7:0]  wr_red,
    input  wire [7:0]  wr_green,
    input  wire [7:0]  wr_blue,
    input  wire        wr_hblank,
    input  wire        wr_vblank,
    input  wire        wr_vsync,

    // optional per-pixel override, computed by the caller in the wr_clk
    // domain (e.g. core_top.v's cassette diagnostic patch) - applied here
    // rather than on the fixed-rate read side so callers can keep using
    // whatever real, already-validated coordinate scheme they already
    // have (dragon_h_count/v_count) instead of this module's internal
    // wr_x/wr_y.
    input  wire        wr_overlay_en,
    input  wire [23:0] wr_overlay_color,
    // the active-area position of the next pixel to be written, so a
    // caller can compute its overlay a few clocks ahead (pixels come every
    // 8 wr_clk cycles) - see osd_keyboard.sv
    output wire [7:0]  wr_next_x,
    output wire [7:0]  wr_next_y,

    // read side - scaler output. dot_clk (wr_clk/16, ~3.58MHz, below) is
    // also the video_rgb_clock the scaler should be given - see
    // core_top.v's instantiation.
    output wire        dot_clk,
    output wire        dot_clk_90,
    output wire [23:0] rd_rgb,
    output wire        rd_de,
    output wire        rd_hsync,
    output wire        rd_vsync
);

    // ------------------------------------------------------------------
    // Write side: capture each real pixel into the frame buffer at its
    // own native position. h/v position is tracked from hblank/vblank/
    // vsync directly (the same signals already proven correct on real
    // hardware via the docked video path), not from raw VDG counters, so
    // this needs no knowledge of mc6847pace's internal timing constants.
    // ------------------------------------------------------------------
    wire wr_de = ~(wr_hblank | wr_vblank);

    reg        wr_pixel_en_prev = 1'b0, wr_de_prev = 1'b0, wr_vsync_prev = 1'b0;
    reg [8:0]  wr_x = 9'd0, wr_y = 9'd0;
    reg        fb_wren = 1'b0;
    reg [15:0] fb_wraddr;
    reg [23:0] fb_wrdata;

    assign wr_next_x = wr_x[7:0];
    assign wr_next_y = wr_y[7:0];

    // Toggles as the first pixel of each frame's first active line is
    // written - the read side's frame lock (below) watches for it.
    reg        wr_frame_tgl = 1'b0;

    always @(posedge wr_clk) begin
        wr_pixel_en_prev <= wr_pixel_en;
        wr_de_prev       <= wr_de;
        wr_vsync_prev    <= wr_vsync;
        fb_wren          <= 1'b0;

        if (wr_de && ~wr_de_prev && wr_y == 9'd0)
            wr_frame_tgl <= ~wr_frame_tgl;

        if (~wr_de) begin
            wr_x <= 9'd0;
        end else if (wr_pixel_en && ~wr_pixel_en_prev) begin
            fb_wren   <= 1'b1;
            fb_wraddr <= {wr_y[7:0], wr_x[7:0]};
            fb_wrdata <= wr_overlay_en ? wr_overlay_color : {wr_red, wr_green, wr_blue};
            wr_x      <= wr_x + 9'd1;
        end

        if (wr_vsync && ~wr_vsync_prev) begin
            wr_y <= 9'd0;
        end else if (wr_de_prev && ~wr_de) begin
            wr_y <= wr_y + 9'd1;
        end
    end

    // ------------------------------------------------------------------
    // Read side: 256x192 active area scan-out at exactly the Dragon's
    // frame rate, frame-locked to the write side.
    //   dot_clk = wr_clk / 16 = 57.272727MHz / 16 = 3.5795MHz
    //   line    = 348 dots = 97.22 us
    //   frame   = 206 lines = 71,688 dots = 1,147,008 wr_clk cycles
    // A PAL Dragon frame is 309 lines x 464 ticks x 8 wr_clk cycles =
    // 1,147,008 wr_clk cycles too, so once locked every frame is exactly
    // 206 lines, forever. (A first version ran from clk_core_12288 and
    // kept up by making one frame in ~50 a line shorter; the scaler
    // blanked a frame each time, about once a second, docked and undocked.)
    //
    // Lock: a frame ends at the first line boundary after the write side
    // starts a new frame (wr_frame_tgl), as long as we're in its last two
    // lines; pulses earlier than that are ignored and the frame runs to
    // V_MAX. From power-on (or reset) that settles within ~10 frames, and
    // from then on the pulse arrives at the same point of line 205 every
    // frame. Only those settling frames differ in length.
    //
    // No tearing: our line 0 starts 0-1 lines after the Dragon's first
    // active line does, and both our lines (97.2 us vs 64.8 us) and our
    // pixels (0.28 us vs 0.14 us) are slower than the Dragon's, so the read
    // stays behind the write all frame and shows each frame whole.
    //
    // NTSC (PAL=0) frames are 263 x 464 x 8 - this would need different
    // totals (and the lock would not hold) if PAL is ever made switchable.
    // ------------------------------------------------------------------
    localparam H_ACTIVE = 256, H_FRONT = 16, H_SYNC = 32, H_BACK = 44;
    localparam H_TOTAL  = H_ACTIVE + H_FRONT + H_SYNC + H_BACK; // 348
    localparam V_ACTIVE = 192, V_FRONT = 4, V_SYNC = 4;
    localparam V_TOTAL  = 206;  // 49.93 Hz - H_TOTAL * V_TOTAL * 16 = one Dragon frame
    localparam V_MAX    = 230;  // 44.72 Hz, only while settling or in reset

    // dot_clk rises as dot_div goes 7 -> 8; dot_clk_90 rises 4 wr_clk
    // cycles (90 degrees) later, as it goes 11 -> 12. Both registered, so
    // glitch-free.
    reg [3:0] dot_div = 4'd0;
    reg       dot_clk_90_r = 1'b0;
    always @(posedge wr_clk) begin
        dot_div <= dot_div + 4'd1;
        if (dot_div == 4'd11)     dot_clk_90_r <= 1'b1;
        else if (dot_div == 4'd3) dot_clk_90_r <= 1'b0;
    end
    assign dot_clk    = dot_div[3];
    assign dot_clk_90 = dot_clk_90_r;

    // wr_frame_tgl crosses into dot_clk: two-flop synchroniser, then an
    // edge sets frame_pending until the current frame ends.
    reg [2:0] frame_tgl_sync = 3'd0;
    reg       frame_pending = 1'b0;

    reg [8:0] h_cnt = 9'd0, v_cnt = 9'd0;
    wire      frame_end = (v_cnt >= V_TOTAL - 2) && (frame_pending || v_cnt == V_MAX - 1);

    always @(posedge dot_clk) begin
        frame_tgl_sync <= {frame_tgl_sync[1:0], wr_frame_tgl};

        if (h_cnt == H_TOTAL - 1) begin
            h_cnt <= 9'd0;
            v_cnt <= frame_end ? 9'd0 : v_cnt + 9'd1;
        end else begin
            h_cnt <= h_cnt + 9'd1;
        end

        if (frame_tgl_sync[2] != frame_tgl_sync[1] && v_cnt >= V_TOTAL - 2)
            frame_pending <= 1'b1;
        else if (h_cnt == H_TOTAL - 1 && frame_end)
            frame_pending <= 1'b0;
    end

    wire de    = (h_cnt < H_ACTIVE) && (v_cnt < V_ACTIVE);
    wire hsync = (h_cnt >= H_ACTIVE + H_FRONT) && (h_cnt < H_ACTIVE + H_FRONT + H_SYNC);
    wire vsync = (v_cnt >= V_ACTIVE + V_FRONT) && (v_cnt < V_ACTIVE + V_FRONT + V_SYNC);

    // fb_rd's q output lags its rdaddress input by exactly one dot_clk
    // cycle (address_reg_b=CLOCK1, outdata_reg_b=UNREGISTERED - see
    // dpram_1r1w.vhd), so de/hsync/vsync are pipelined by one cycle here
    // to stay aligned with the pixel data they describe.
    wire [15:0] fb_rdaddr = {v_cnt[7:0], h_cnt[7:0]};

    reg de_d1 = 1'b0, hsync_d1 = 1'b0, vsync_d1 = 1'b0;
    always @(posedge dot_clk) begin
        de_d1    <= de;
        hsync_d1 <= hsync;
        vsync_d1 <= vsync;
    end

    // Outputs change on dot_clk's FALLING edge. apf_top.v's DDIO output
    // registers capture video_rgb/de/hs/vs on video_rgb_clock's (= dot_clk's)
    // RISING edge; launching from that same rising edge left a same-edge
    // race whose outcome depended on routing, and so on each build's fit -
    // one build came up with a blank/flickering picture from it. Half a
    // dot (140 ns) either side of the capture edge removes it.
    reg [23:0] rgb_o = 24'h000000;
    reg        de_o = 1'b0, hsync_o = 1'b0, vsync_o = 1'b0;
    wire [23:0] fb_q;
    always @(negedge dot_clk) begin
        rgb_o   <= fb_q;
        de_o    <= de_d1;
        hsync_o <= hsync_d1;
        vsync_o <= vsync_d1;
    end

    assign rd_rgb   = rgb_o;
    assign rd_de    = de_o;
    assign rd_hsync = hsync_o;
    assign rd_vsync = vsync_o;

    dpram_1r1w #(49152, 16, 24) fb_ram (
        .wrclock  ( wr_clk ),
        .wren     ( fb_wren ),
        .wraddress( fb_wraddr ),
        .data     ( fb_wrdata ),

        .rdclock  ( dot_clk ),
        .rdaddress( fb_rdaddr ),
        .q        ( fb_q )
    );

endmodule
