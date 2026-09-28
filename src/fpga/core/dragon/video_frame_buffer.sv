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
// own native (slow) rate, and continuously re-scan that buffer out to the
// scaler on a separate, clean, fixed-rate clock (~46Hz here - comfortably
// inside the 30-62Hz window with margin both ways) derived from
// clk_core_12288 (already present in core_top.v for other purposes,
// previously unused for video - this is exactly what phase 0's original
// template test-pattern generator used before real Dragon video replaced
// it). The displayed image still only *updates* ~15 times a second (same
// as before - we're not making the machine itself faster), but the
// scaler now always sees a normal, lockable refresh rate.
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

    // read side - scaler output, fixed-rate. dot_clk (~3.072MHz, derived
    // from rd_ref_clk/4 below) is also the video_rgb_clock the scaler
    // should be given - see core_top.v's instantiation.
    input  wire        rd_ref_clk,   // clk_core_12288 - free-running, clean PLL output
    input  wire        rd_ref_clk_90,// clk_core_12288_90deg - same freq, 90 degrees offset
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

    always @(posedge wr_clk) begin
        wr_pixel_en_prev <= wr_pixel_en;
        wr_de_prev       <= wr_de;
        wr_vsync_prev    <= wr_vsync;
        fb_wren          <= 1'b0;

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
    // Read side: fixed-rate 256x192 active area scan-out. Totals chosen
    // so that dot_clk (rd_ref_clk/4) * H_TOTAL * V_TOTAL lands well inside
    // the Pocket's built-in screen's documented 30-62Hz range:
    //   dot_clk = 12.288MHz / 4 = 3.072MHz
    //   refresh = 3.072MHz / (320 * 210) = ~45.7Hz
    // ------------------------------------------------------------------
    localparam H_ACTIVE = 256, H_FRONT = 8, H_SYNC = 32, H_BACK = 24;
    localparam H_TOTAL  = H_ACTIVE + H_FRONT + H_SYNC + H_BACK; // 320
    localparam V_ACTIVE = 192, V_FRONT = 4, V_SYNC = 4, V_BACK = 10;
    localparam V_TOTAL  = V_ACTIVE + V_FRONT + V_SYNC + V_BACK; // 210

    reg [1:0] dot_div = 2'd0;
    always @(posedge rd_ref_clk) dot_div <= dot_div + 2'd1;
    assign dot_clk = dot_div[1];

    // Same division ratio, counted from the PLL's own 90-degree-shifted
    // output - since both PLL outputs are phase-locked at the same
    // frequency, this gives a genuine 90-degree-shifted dot_clk_90 rather
    // than reusing dot_clk for both (unlike the old dragon_vclk-based
    // video_rgb_clock_90, which had no true phase partner available).
    reg [1:0] dot_div_90 = 2'd0;
    always @(posedge rd_ref_clk_90) dot_div_90 <= dot_div_90 + 2'd1;
    assign dot_clk_90 = dot_div_90[1];

    reg [8:0] h_cnt = 9'd0, v_cnt = 9'd0;
    always @(posedge dot_clk) begin
        if (h_cnt == H_TOTAL - 1) begin
            h_cnt <= 9'd0;
            v_cnt <= (v_cnt == V_TOTAL - 1) ? 9'd0 : v_cnt + 9'd1;
        end else begin
            h_cnt <= h_cnt + 9'd1;
        end
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

    assign rd_de    = de_d1;
    assign rd_hsync = hsync_d1;
    assign rd_vsync = vsync_d1;

    dpram_1r1w #(49152, 16, 24) fb_ram (
        .wrclock  ( wr_clk ),
        .wren     ( fb_wren ),
        .wraddress( fb_wraddr ),
        .data     ( fb_wrdata ),

        .rdclock  ( dot_clk ),
        .rdaddress( fb_rdaddr ),
        .q        ( rd_rgb )
    );

endmodule
