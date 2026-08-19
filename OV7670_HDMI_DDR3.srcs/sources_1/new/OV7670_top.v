`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// // Engineer: Alessandro Orlando
// 
// Create Date: 2026/15/08 
// Design Name: 
// Module Name: OV7670_top
// Project Name: OV7670_HDMI_DDR3
// Target Devices: 
// Tool Versions: 
// Description: 
// 
//////////////////////////////////////////////////////////////////////////////////


module OV7670_top(
    input sys_clk_pin,
    input sys_rst_n_pin,

    output               sioc,        // I2C clock
    inout                siod,        // I2C data

    input  pclk,
    input  vsync,
    input  href,
    input  [7:0] data_pin,

    output [3:0] led_pin,
    output xclk,
    output pwdn,
    output reset_pin,
    input hdmi_hpdn,

    // HDMI TX – MicroPhase A7 Lite onboard connector
    output hdmi_clk_p, hdmi_clk_n,
    output hdmi_d0_p,  hdmi_d0_n,   // Blue  (+ sync)
    output hdmi_d1_p,  hdmi_d1_n,   // Green
    output hdmi_d2_p,  hdmi_d2_n,   // Red

    // DDR3 SDRAM on the A7 Lite board
    output DDR3_A0,  output DDR3_A1,  output DDR3_A2,  output DDR3_A3,
    output DDR3_A4,  output DDR3_A5,  output DDR3_A6,  output DDR3_A7,
    output DDR3_A8,  output DDR3_A9,  output DDR3_A10, output DDR3_A11,
    output DDR3_A12, output DDR3_A13, output DDR3_A14,
    output DDR3_BA0, output DDR3_BA1, output DDR3_BA2,
    output DDR3_nCAS, output DDR3_nRAS, output DDR3_nWE,
    output DDR3_CKE, output DDR3_ODT, output DDR3_nRST,
    output DDR3_CK_P, output DDR3_CK_N,
    inout  DDR3_D0,  inout DDR3_D1,  inout DDR3_D2,  inout DDR3_D3,
    inout  DDR3_D4,  inout DDR3_D5,  inout DDR3_D6,  inout DDR3_D7,
    inout  DDR3_D8,  inout DDR3_D9,  inout DDR3_D10, inout DDR3_D11,
    inout  DDR3_D12, inout DDR3_D13, inout DDR3_D14, inout DDR3_D15,
    output DDR3_DM0, output DDR3_DM1,
    inout  DDR3_DQS_P0, inout DDR3_DQS_N0,
    inout  DDR3_DQS_P1, inout DDR3_DQS_N1
    );

    localparam TEST_PATTERN_ONLY = 1'b0;
    // Keep a stable, standards-compliant TMDS stream for monitor lock.
    localparam TMDS_LANE_SWEEP   = 1'b0;
    // Keep the bridge active, but disable the synthetic DDR3 test pattern so the
    // real OV7670 capture path is used for image acquisition.
    localparam DDR3_TEST_PATTERN = 1'b0;
    // Diagnostic mode: retain the OV7670 PCLK/HREF/VSYNC/write-address cadence,
    // but replace only its RGB565 payload with address-derived color bars.
    localparam CAPTURE_PATH_PATTERN = 1'b0;

    // ----------------------------------------------------------------
    // Clocking – MMCM from 50 MHz board oscillator
    //   clk_pixel : 25 MHz  (pixel clock / VGA timing / BRAM)
    //   clk_5x    : 125 MHz (TMDS serializer)
    // ----------------------------------------------------------------
    wire        wr;
    wire [18:0] capture_addr;
    wire [15:0] capture_data;
    wire [7:0]  i2c_rdata;
    wire clk_pixel, clk_5x, mig_clk, mig_ref200, pll_locked;

    wire        mig_init_calib_complete;
    wire        mig_ui_clk;
    wire        mig_ui_clk_sync_rst;
    wire        mig_app_rdy;
    wire        mig_app_wdf_rdy;
    wire [63:0] mig_app_rd_data;
    wire        mig_app_rd_data_end;
    wire        mig_app_rd_data_valid;
    wire        mig_app_sr_active;
    wire        mig_app_ref_ack;
    wire        mig_app_zq_ack;
    wire [11:0] mig_device_temp;

    // DDR3 framebuffer bridge <-> MIG native application interface
    wire [28:0] mig_app_addr;
    wire [2:0]  mig_app_cmd;
    wire        mig_app_en;
    wire [63:0] mig_app_wdf_data;
    wire        mig_app_wdf_end;
    wire        mig_app_wdf_wren;

    // DDR3 framebuffer bridge <-> VGA timing generator
    wire [9:0]  fb_col;
    wire        fb_next_row_pulse;
    wire [11:0] fb_pixel_out;

    clk_wiz_hdmi u_clk_hdmi (
        .clk_in    (sys_clk_pin),
        .clk_pixel (clk_pixel),
        .clk_5x    (clk_5x),
        .clk_mig   (mig_clk),
        .clk_ref200(mig_ref200),
        .locked    (pll_locked)
    );

    mig_7series_1 u_mig_7series_1 (
        .ddr3_dq            ({DDR3_D15, DDR3_D14, DDR3_D13, DDR3_D12, DDR3_D11, DDR3_D10, DDR3_D9, DDR3_D8,
                              DDR3_D7, DDR3_D6, DDR3_D5, DDR3_D4, DDR3_D3, DDR3_D2, DDR3_D1, DDR3_D0}),
        .ddr3_dqs_n         ({DDR3_DQS_N1, DDR3_DQS_N0}),
        .ddr3_dqs_p         ({DDR3_DQS_P1, DDR3_DQS_P0}),
        .ddr3_addr          ({DDR3_A14, DDR3_A13, DDR3_A12, DDR3_A11, DDR3_A10, DDR3_A9, DDR3_A8,
                              DDR3_A7, DDR3_A6, DDR3_A5, DDR3_A4, DDR3_A3, DDR3_A2, DDR3_A1, DDR3_A0}),
        .ddr3_ba            ({DDR3_BA2, DDR3_BA1, DDR3_BA0}),
        .ddr3_ras_n         (DDR3_nRAS),
        .ddr3_cas_n         (DDR3_nCAS),
        .ddr3_we_n          (DDR3_nWE),
        .ddr3_reset_n       (DDR3_nRST),
        .ddr3_ck_p          (DDR3_CK_P),
        .ddr3_ck_n          (DDR3_CK_N),
        .ddr3_cke           (DDR3_CKE),
        .ddr3_dm            ({DDR3_DM1, DDR3_DM0}),
        .ddr3_odt           (DDR3_ODT),
        .sys_clk_i          (mig_clk),
        .clk_ref_i          (mig_ref200),
        .app_addr           (mig_app_addr),
        .app_cmd            (mig_app_cmd),
        .app_en             (mig_app_en),
        .app_wdf_data       (mig_app_wdf_data),
        .app_wdf_end        (mig_app_wdf_end),
        .app_wdf_mask       (8'h00),
        .app_wdf_wren       (mig_app_wdf_wren),
        .app_sr_req         (1'b0),
        .app_ref_req        (1'b0),
        .app_zq_req         (1'b0),
        .device_temp_i      (12'd0),
        .device_temp        (mig_device_temp),
        .sys_rst            (sys_rst_n_pin),
        .app_rd_data        (mig_app_rd_data),
        .app_rd_data_end    (mig_app_rd_data_end),
        .app_rd_data_valid  (mig_app_rd_data_valid),
        .app_rdy            (mig_app_rdy),
        .app_wdf_rdy        (mig_app_wdf_rdy),
        .app_sr_active      (mig_app_sr_active),
        .app_ref_ack        (mig_app_ref_ack),
        .app_zq_ack         (mig_app_zq_ack),
        .ui_clk             (mig_ui_clk),
        .ui_clk_sync_rst    (mig_ui_clk_sync_rst),
        .init_calib_complete(mig_init_calib_complete)
    );

    // ----------------------------------------------------------------
    // Reset – wait for PLL lock and count a fixed delay
    // ----------------------------------------------------------------
    reg [15:0] reset_cnt = 0;
    reg rst = 0;

    always @(posedge sys_clk_pin) begin
        if (!sys_rst_n_pin || !pll_locked) begin
            reset_cnt <= 0;
            rst       <= 0;
        end else begin
            if (reset_cnt < 16'hFFFF) begin
                reset_cnt <= reset_cnt + 1'b1;
                rst       <= 0;
            end else begin
                rst <= 1;
            end
        end
    end

    // HDMI reset generated in pixel-clock domain to avoid sys->pixel reset timing crossings.
    reg [15:0] hdmi_reset_cnt = 16'd0;
    reg        hdmi_run = 1'b0;
    always @(posedge clk_pixel) begin
        if (!sys_rst_n_pin || !pll_locked) begin
            hdmi_reset_cnt <= 16'd0;
            hdmi_run       <= 1'b0;
        end else if (hdmi_reset_cnt < 16'hFFFF) begin
            hdmi_reset_cnt <= hdmi_reset_cnt + 16'd1;
            hdmi_run       <= 1'b0;
        end else begin
            hdmi_run <= 1'b1;
        end
    end
    wire hdmi_rst = !hdmi_run;

    // ----------------------------------------------------------------
    // Camera control
    // ----------------------------------------------------------------
    reg vsync_seen = 1'b0;
    reg capture_seen = 1'b0;
    always @(posedge pclk) begin
        if (!sys_rst_n_pin) begin
            vsync_seen <= 1'b0;
            capture_seen <= 1'b0;
        end else begin
            if (vsync)
                vsync_seen <= 1'b1;
            if (wr)
                capture_seen <= 1'b1;
        end
    end

    // CDC: bring camera-domain capture flag safely into pixel domain.
    (* ASYNC_REG = "TRUE" *) reg capture_seen_sync1 = 1'b0;
    (* ASYNC_REG = "TRUE" *) reg capture_seen_sync2 = 1'b0;
    always @(posedge clk_pixel) begin
        if (hdmi_rst) begin
            capture_seen_sync1 <= 1'b0;
            capture_seen_sync2 <= 1'b0;
        end else begin
            capture_seen_sync1 <= capture_seen;
            capture_seen_sync2 <= capture_seen_sync1;
        end
    end

    // CDC: bring MIG calibration status (ui_clk domain) into pixel domain for the debug LED.
    (* ASYNC_REG = "TRUE" *) reg calib_done_sync1 = 1'b0;
    (* ASYNC_REG = "TRUE" *) reg calib_done_sync2 = 1'b0;
    always @(posedge clk_pixel) begin
        if (hdmi_rst) begin
            calib_done_sync1 <= 1'b0;
            calib_done_sync2 <= 1'b0;
        end else begin
            calib_done_sync1 <= mig_init_calib_complete;
            calib_done_sync2 <= calib_done_sync1;
        end
    end
    wire video_rst = hdmi_rst || !calib_done_sync2;

    // On this board LEDs are wired active-low (FPGA drives low -> LED on).
    // `hdmi_hpdn` is active-low on this board: low means cable/sink detected.
    // LED2 temporarily repurposed to show DDR3 MIG calibration status while
    // debugging the framebuffer bridge (was: ~capture_seen_sync2).
    assign led_pin[1]  = TEST_PATTERN_ONLY ? hdmi_hpdn : ~calib_done_sync2;

    // Internal debug LEDs independent from camera pins.
    // LED3: PLL lock state, LED4: heartbeat from pixel clock.
    reg [24:0] hb_cnt = 25'd0;
    reg        hb_led = 1'b0;
    always @(posedge clk_pixel) begin
        if (hdmi_rst) begin
            hb_cnt <= 25'd0;
            hb_led <= 1'b0;
        end else if (hb_cnt == 25_000_000 - 1) begin
            hb_cnt <= 25'd0;
            hb_led <= ~hb_led;
        end else begin
            hb_cnt <= hb_cnt + 25'd1;
        end
    end

    // ----------------------------------------------------------------
    // OV7670 hard-reset sequencing (sys_clk domain)
    // ----------------------------------------------------------------
    localparam integer CAM_T_PWDN_RST_CYCLES  = 32'd1500000; // 30 ms @ 50 MHz
    localparam integer CAM_T_RELEASE_CYCLES   = 32'd500000;  // 10 ms @ 50 MHz
    localparam integer CAM_T_POST_RST_CYCLES  = 32'd1000000; // 20 ms @ 50 MHz

    localparam [1:0] CAM_RST_HOLD     = 2'd0;
    localparam [1:0] CAM_PWRUP_WAIT   = 2'd1;
    localparam [1:0] CAM_POSTRST_WAIT = 2'd2;
    localparam [1:0] CAM_READY        = 2'd3;

    reg [1:0]  cam_state = CAM_RST_HOLD;
    reg [31:0] cam_cnt = 32'd0;
    reg        cam_pwdn = 1'b1;
    reg        cam_reset_n = 1'b0;
    reg        cam_init_en = 1'b0;

    always @(posedge sys_clk_pin) begin
        if (!sys_rst_n_pin || !pll_locked || !rst) begin
            cam_state   <= CAM_RST_HOLD;
            cam_cnt     <= 32'd0;
            cam_pwdn    <= 1'b1;
            cam_reset_n <= 1'b0;
            cam_init_en <= 1'b0;
        end else begin
            case (cam_state)
                CAM_RST_HOLD: begin
                    cam_pwdn    <= 1'b1;
                    cam_reset_n <= 1'b0;
                    cam_init_en <= 1'b0;
                    if (cam_cnt < CAM_T_PWDN_RST_CYCLES - 1) begin
                        cam_cnt <= cam_cnt + 32'd1;
                    end else begin
                        cam_cnt   <= 32'd0;
                        cam_state <= CAM_PWRUP_WAIT;
                    end
                end

                CAM_PWRUP_WAIT: begin
                    cam_pwdn    <= 1'b0;
                    cam_reset_n <= 1'b0;
                    cam_init_en <= 1'b0;
                    if (cam_cnt < CAM_T_RELEASE_CYCLES - 1) begin
                        cam_cnt <= cam_cnt + 32'd1;
                    end else begin
                        cam_cnt   <= 32'd0;
                        cam_state <= CAM_POSTRST_WAIT;
                    end
                end

                CAM_POSTRST_WAIT: begin
                    cam_pwdn    <= 1'b0;
                    cam_reset_n <= 1'b1;
                    cam_init_en <= 1'b0;
                    if (cam_cnt < CAM_T_POST_RST_CYCLES - 1) begin
                        cam_cnt <= cam_cnt + 32'd1;
                    end else begin
                        cam_cnt   <= 32'd0;
                        cam_state <= CAM_READY;
                    end
                end

                default: begin
                    cam_pwdn    <= 1'b0;
                    cam_reset_n <= 1'b1;
                    cam_init_en <= 1'b1;
                    cam_cnt     <= 32'd0;
                    cam_state   <= CAM_READY;
                end
            endcase
        end
    end

    assign led_pin[2]  = pll_locked;
    assign led_pin[3]  = hb_led;
    assign xclk        = clk_pixel;   // 25 MHz to camera XCLK
    assign pwdn        = cam_pwdn;
    assign reset_pin   = cam_reset_n;

    // OV7670 I2C initialisation (uses 50 MHz system clock)
    ov7670_init #(
        .CLK_Freq(50_000000)
    ) u_ov7670_init (
        .iCLK       (sys_clk_pin),
        .iRST_N     (rst & cam_init_en),
        .I2C_SCLK   (sioc),
        .I2C_SDAT   (siod),
        .Config_Done(led_pin[0]),
        .I2C_RDATA  (i2c_rdata)
    );

    // ----------------------------------------------------------------
    // DDR3 framebuffer bridge: camera (pclk) -> MIG native i/f (ui_clk) ->
    // ping-pong line buffers -> VGA timing generator (clk_pixel).
    // Native 640x480 RGB565 from the OV7670 through DDR3 to HDMI.
    // ----------------------------------------------------------------
    // Synthetic write-side pattern generator (pclk domain): free-running
    // raster counter driving the bridge's write side in place of the real
    // camera. Encodes 3 independent diagnostic gradients into RGB444 (after
    // the bridge's own RGB565->444 truncation):
    //   5 flat-color vertical bars (coarse, moire-resistant) reveal
    //   burst/word-order and column-addressing bugs; inverting the colors
    //   in the bottom half of the frame reveals row-addressing bugs. No
    //   per-pixel gradient is used here since a fine repeating pattern
    //   photographs with unavoidable camera-sensor moire regardless of
    //   whether the underlying data is correct (seen in the first attempt).
    reg [9:0]  tp_col = 10'd0;
    reg [8:0]  tp_row = 9'd0;
    reg [18:0] tp_addr = 19'd0;
    always @(posedge pclk) begin
        if (!sys_rst_n_pin) begin
            tp_col  <= 10'd0;
            tp_row  <= 9'd0;
            tp_addr <= 19'd0;
        end else begin
            if (tp_col == 10'd639) begin
                tp_col <= 10'd0;
                tp_row <= (tp_row == 9'd479) ? 9'd0 : tp_row + 9'd1;
            end else begin
                tp_col <= tp_col + 10'd1;
            end
            tp_addr <= (tp_addr == 19'd307199) ? 19'd0 : tp_addr + 19'd1;
        end
    end
    wire tp_wr = sys_rst_n_pin;

    reg [3:0] band_r, band_g, band_b;
    always @(*) begin
        case (tp_col[9:7])                        // 5 flat 128px-wide bands
            3'd0: begin band_r = 4'hF; band_g = 4'h0; band_b = 4'h0; end // red
            3'd1: begin band_r = 4'hF; band_g = 4'h8; band_b = 4'h0; end // orange
            3'd2: begin band_r = 4'h0; band_g = 4'hF; band_b = 4'h0; end // green
            3'd3: begin band_r = 4'h0; band_g = 4'hF; band_b = 4'hF; end // cyan
            default: begin band_r = 4'h0; band_g = 4'h0; band_b = 4'hF; end // blue
        endcase
    end
    wire tp_row_half = tp_row[8];
    wire [3:0] tp_r4 = tp_row_half ? ~band_r : band_r;
    wire [3:0] tp_g4 = tp_row_half ? ~band_g : band_g;
    wire [3:0] tp_b4 = tp_row_half ? ~band_b : band_b;
    wire [15:0] tp_data = {tp_r4, 1'b0, tp_g4, 2'b0, tp_b4, 1'b0};

    reg [9:0] capture_pattern_col = 10'd0;
    always @(posedge pclk) begin
        if (!sys_rst_n_pin || vsync)
            capture_pattern_col <= 10'd0;
        else if (wr)
            capture_pattern_col <= (capture_pattern_col == 10'd639) ? 10'd0 : capture_pattern_col + 10'd1;
    end

    reg [15:0] capture_path_pattern_data;
    always @(*) begin
        case (capture_pattern_col[9:7])
            3'd0: capture_path_pattern_data = 16'hF800; // red
            3'd1: capture_path_pattern_data = 16'hFC00; // orange
            3'd2: capture_path_pattern_data = 16'h07E0; // green
            3'd3: capture_path_pattern_data = 16'h07FF; // cyan
            default: capture_path_pattern_data = 16'h001F; // blue
        endcase
    end

    wire [18:0] bridge_cap_addr = DDR3_TEST_PATTERN ? tp_addr : capture_addr;
    wire [15:0] bridge_cap_data = DDR3_TEST_PATTERN ? tp_data :
                                  (CAPTURE_PATH_PATTERN ? capture_path_pattern_data : capture_data);
    wire        bridge_cap_wr   = DDR3_TEST_PATTERN ? tp_wr   : wr;

    ddr3_fb_bridge #(
        .FRAME_WIDTH   (640),
        .FRAME_HEIGHT  (480),
        .LINE_BUF_WORDS(160)
    ) u_fb_bridge (
        .pclk       (pclk),
        .pclk_rst   (!sys_rst_n_pin),
        .cap_vsync  (vsync),
        .cap_addr   (bridge_cap_addr),
        .cap_data   (bridge_cap_data),
        .cap_wr     (bridge_cap_wr),

        .ui_clk             (mig_ui_clk),
        .ui_clk_rst         (mig_ui_clk_sync_rst),
        .app_addr           (mig_app_addr),
        .app_cmd            (mig_app_cmd),
        .app_en             (mig_app_en),
        .app_rdy            (mig_app_rdy),
        .app_wdf_data       (mig_app_wdf_data),
        .app_wdf_end        (mig_app_wdf_end),
        .app_wdf_wren       (mig_app_wdf_wren),
        .app_wdf_rdy        (mig_app_wdf_rdy),
        .app_rd_data        (mig_app_rd_data),
        .app_rd_data_valid  (mig_app_rd_data_valid),
        .app_rd_data_end    (mig_app_rd_data_end),
        .init_calib_complete(mig_init_calib_complete),

        .clk_pixel      (clk_pixel),
        .pixel_rst      (video_rst),
        .col            (fb_col),
        .next_row_pulse (fb_next_row_pulse),
        .pixel_out      (fb_pixel_out)
    );

    // ----------------------------------------------------------------
    // VGA timing generator
    // ----------------------------------------------------------------
    wire [3:0] vga_r, vga_g, vga_b;
    wire       vga_hs, vga_vs, vga_de;

    vga #(
        .FRAME_WIDTH (640),
        .FRAME_HEIGHT(480),
        .WIN_H_START (0),
        .WIN_V_START (0),
        .FB_LATENCY  (2)
    ) u_vga (
        .clk25      (clk_pixel),
        .reset      (video_rst),
        .vga_red    (vga_r),
        .vga_green  (vga_g),
        .vga_blue   (vga_b),
        .vga_hsync  (vga_hs),
        .vga_vsync  (vga_vs),
        .vga_de     (vga_de),
        .test_pattern_en(TEST_PATTERN_ONLY),
        .col            (fb_col),
        .next_row_pulse (fb_next_row_pulse),
        .frame_pixel    (fb_pixel_out)
    );

    // ----------------------------------------------------------------
    // TMDS encoding – 4-bit VGA channels padded to 8 bit
    // ----------------------------------------------------------------
    wire [9:0] tmds_ch0, tmds_ch1, tmds_ch2;

    // ch0 = Blue; carries HSYNC/VSYNC control during blanking
    tmds_encoder u_enc_b (
        .clk  (clk_pixel),
        .din  ({vga_b, vga_b}),        // 4→8 bit
        .ctrl ({vga_vs, vga_hs}),
        .de   (vga_de),
        .dout (tmds_ch0)
    );

    tmds_encoder u_enc_g (
        .clk  (clk_pixel),
        .din  ({vga_g, vga_g}),
        .ctrl (2'b00),
        .de   (vga_de),
        .dout (tmds_ch1)
    );

    tmds_encoder u_enc_r (
        .clk  (clk_pixel),
        .din  ({vga_r, vga_r}),
        .ctrl (2'b00),
        .de   (vga_de),
        .dout (tmds_ch2)
    );

    // Sweep TMDS mapping once per second:
    // - 6 lane permutations
    // - normal / bit-reversed / inverted / bit-reversed+inverted symbols
    // Total 24 modes to catch lane-order and polarity-related mismatches.
    reg [24:0] lane_sweep_cnt = 25'd0;
    reg [4:0]  lane_mode = 5'd0;

    wire [2:0] lane_perm = lane_mode[2:0];
    wire [1:0] sym_mode  = lane_mode[4:3];

    function [9:0] rev10;
        input [9:0] v;
        begin
            rev10 = {v[0], v[1], v[2], v[3], v[4], v[5], v[6], v[7], v[8], v[9]};
        end
    endfunction

    function [9:0] map_sym;
        input [9:0] v;
        input [1:0] m;
        begin
            case (m)
                2'b00: map_sym = v;
                2'b01: map_sym = rev10(v);
                2'b10: map_sym = ~v;
                default: map_sym = ~rev10(v);
            endcase
        end
    endfunction

    always @(posedge clk_pixel) begin
        if (hdmi_rst) begin
            lane_sweep_cnt <= 25'd0;
            lane_mode      <= 5'd0;
        end else if (TMDS_LANE_SWEEP) begin
            if (lane_sweep_cnt == 25_000_000 - 1) begin
                lane_sweep_cnt <= 25'd0;
                if (lane_mode == 5'd23)
                    lane_mode <= 5'd0;
                else
                    lane_mode <= lane_mode + 5'd1;
            end else begin
                lane_sweep_cnt <= lane_sweep_cnt + 25'd1;
            end
        end else begin
            lane_sweep_cnt <= 25'd0;
            lane_mode      <= 5'd0;
        end
    end

    reg [9:0] tmds_tx0, tmds_tx1, tmds_tx2;
    always @(*) begin
        case (lane_perm)
            3'd0: begin tmds_tx0 = map_sym(tmds_ch0, sym_mode); tmds_tx1 = map_sym(tmds_ch1, sym_mode); tmds_tx2 = map_sym(tmds_ch2, sym_mode); end
            3'd1: begin tmds_tx0 = map_sym(tmds_ch0, sym_mode); tmds_tx1 = map_sym(tmds_ch2, sym_mode); tmds_tx2 = map_sym(tmds_ch1, sym_mode); end
            3'd2: begin tmds_tx0 = map_sym(tmds_ch1, sym_mode); tmds_tx1 = map_sym(tmds_ch0, sym_mode); tmds_tx2 = map_sym(tmds_ch2, sym_mode); end
            3'd3: begin tmds_tx0 = map_sym(tmds_ch1, sym_mode); tmds_tx1 = map_sym(tmds_ch2, sym_mode); tmds_tx2 = map_sym(tmds_ch0, sym_mode); end
            3'd4: begin tmds_tx0 = map_sym(tmds_ch2, sym_mode); tmds_tx1 = map_sym(tmds_ch0, sym_mode); tmds_tx2 = map_sym(tmds_ch1, sym_mode); end
            default: begin tmds_tx0 = map_sym(tmds_ch2, sym_mode); tmds_tx1 = map_sym(tmds_ch1, sym_mode); tmds_tx2 = map_sym(tmds_ch0, sym_mode); end
        endcase
    end

    // ----------------------------------------------------------------
    // HDMI serialiser
    // ----------------------------------------------------------------
    hdmi_tx u_hdmi (
        .clk_pixel  (clk_pixel),
        .clk_5x     (clk_5x),
        .reset      (hdmi_rst),
        .tmds_ch0   (TMDS_LANE_SWEEP ? tmds_tx0 : tmds_ch0),
        .tmds_ch1   (TMDS_LANE_SWEEP ? tmds_tx1 : tmds_ch1),
        .tmds_ch2   (TMDS_LANE_SWEEP ? tmds_tx2 : tmds_ch2),
        .hdmi_clk_p (hdmi_clk_p), .hdmi_clk_n(hdmi_clk_n),
        .hdmi_d0_p  (hdmi_d0_p),  .hdmi_d0_n (hdmi_d0_n),
        .hdmi_d1_p  (hdmi_d1_p),  .hdmi_d1_n (hdmi_d1_n),
        .hdmi_d2_p  (hdmi_d2_p),  .hdmi_d2_n (hdmi_d2_n)
    );

    // ----------------------------------------------------------------
    // Camera capture
    // ----------------------------------------------------------------
    ov7670_capture u_capture (
        .pclk  (pclk),
        .vsync (vsync),
        .href  (href),
        .d     (data_pin),
        .addr  (capture_addr),
        .dout  (capture_data),
        .wr    (wr)
    );

endmodule

//////////////////////////////////////////////////////////////////////////////////
// Module Name: ddr3_fb_bridge
//
// Bridges the OV7670 capture path and the VGA display path through DDR3 (via
// MIG's native application interface), replacing the old BRAM framebuffer.
//
// Write side (pclk domain): accumulates 8 consecutive captured pixels (already
// truncated to RGB444) into one MIG burst (BL8 = 2 x 64-bit beats = 8 x 16-bit
// slots), then hands the group to an async FIFO for the ui_clk domain to drain.
// Camera and display share the same linear (row*FRAME_WIDTH+col)/8 burst
// address space, so no address translation is needed between the two sides.
//
// Read side (clk_pixel domain): two ping-pong line buffers (64-bit wide, 4
// pixels/word), one being scanned out by the VGA timing generator while the
// other is prefetched a full row ahead via DDR3 burst reads. `next_row_pulse`
// (once per active row, from `vga`) triggers the ping-pong swap and kicks off
// prefetch of the following row; crossed into ui_clk with a toggle synchroniser.
//
// Arbitration on the single MIG app port: pending read-prefetch bursts always
// win over queued camera writes (display continuity is latency critical; the
// camera write path has async-FIFO slack since capture is far slower than DDR3).
//
// NOTE: first-pass implementation, not yet hardware-validated; cycle-accurate
// pixel alignment (FB_LATENCY in `vga`) may need a small tweak after bring-up.
//////////////////////////////////////////////////////////////////////////////////
module ddr3_fb_bridge #(
    parameter FRAME_WIDTH    = 320,  // must be a multiple of 8
    parameter FRAME_HEIGHT   = 240,
    parameter LINE_BUF_WORDS = 160   // fixed alloc = 640/4, future-proofed for native VGA
)(
    // Camera capture write side (pclk domain)
    input             pclk,
    input             pclk_rst,
    input             cap_vsync,
    input      [18:0] cap_addr,
    input      [15:0] cap_data,
    input             cap_wr,

    // MIG native application interface (ui_clk domain)
    input             ui_clk,
    input             ui_clk_rst,
    output reg [28:0] app_addr,
    output reg [2:0]  app_cmd,
    output reg        app_en,
    input             app_rdy,
    output reg [63:0] app_wdf_data,
    output reg        app_wdf_end,
    output reg        app_wdf_wren,
    input             app_wdf_rdy,
    input      [63:0] app_rd_data,
    input             app_rd_data_valid,
    input             app_rd_data_end,
    input             init_calib_complete,

    // Display read side (clk_pixel domain)
    input             clk_pixel,
    input             pixel_rst,
    input      [9:0]  col,
    input             next_row_pulse,
    output     [11:0] pixel_out
);

    localparam BURSTS_PER_ROW = FRAME_WIDTH/8;
    localparam FRAME_BURSTS   = (FRAME_WIDTH*FRAME_HEIGHT)/8;

    reg cap_frame_bank;
    reg completed_frame_bank;
    reg cap_vsync_d;
    always @(posedge pclk) begin
        if (pclk_rst) begin
            cap_frame_bank       <= 1'b0;
            completed_frame_bank <= 1'b1;
            cap_vsync_d          <= 1'b0;
        end else begin
            cap_vsync_d <= cap_vsync;
            if (cap_vsync && !cap_vsync_d) begin
                completed_frame_bank <= cap_frame_bank;
                cap_frame_bank       <= ~cap_frame_bank;
            end
        end
    end

    // ------------------------------------------------------------------
    // WRITE SIDE (pclk domain): accumulate 8 pixels -> push one 144-bit
    // group {burst_addr[15:0], pix7,pix6,...,pix0 (16b each, RGB444 in low
    // 12 bits)} into the async FIFO.
    // ------------------------------------------------------------------
    reg [127:0] wgroup_shift;
    reg        group_push_r;
    reg [144:0] wfifo_din_r;
    wire [15:0] cap_rgb444 = {4'b0, cap_data[15:12], cap_data[10:7], cap_data[4:1]};

    always @(posedge pclk) begin
        if (pclk_rst) begin
            wgroup_shift <= 128'd0;
            group_push_r <= 1'b0;
        end else begin
            group_push_r <= 1'b0;
            if (cap_wr) begin
                wgroup_shift <= {cap_rgb444, wgroup_shift[127:16]};
                if (cap_addr[2:0] == 3'b111) begin
                    wfifo_din_r <= {cap_frame_bank, cap_addr[18:3],
                                    cap_rgb444, wgroup_shift[127:16]};
                    group_push_r <= 1'b1;
                end
            end
        end
    end

    wire         wfifo_full;
    wire         wfifo_empty;
    wire [144:0] wfifo_dout;
    reg          wfifo_rd_en;

    async_fifo #(.DATA_WIDTH(145), .ADDR_WIDTH(4)) u_wfifo (
        .wr_clk (pclk),
        .wr_rst (pclk_rst),
        .wr_en  (group_push_r),
        .din    (wfifo_din_r),
        .full   (wfifo_full),
        .rd_clk (ui_clk),
        .rd_rst (ui_clk_rst),
        .rd_en  (wfifo_rd_en),
        .dout   (wfifo_dout),
        .empty  (wfifo_empty)
    );

    // ------------------------------------------------------------------
    // Row-swap trigger: clk_pixel -> ui_clk (toggle + double-flop sync).
    // `active_buf_*` selects which line buffer is being SCANNED OUT; the
    // other one is always the prefetch target.
    // ------------------------------------------------------------------
    reg active_buf_px;
    reg row_ready_toggle_ui;
    (* ASYNC_REG = "TRUE" *) reg row_ready_sync1, row_ready_sync2, row_ready_sync3;
    always @(posedge clk_pixel) begin
        if (pixel_rst) begin
            active_buf_px <= 1'b0;
            row_ready_sync1 <= 1'b0;
            row_ready_sync2 <= 1'b0;
            row_ready_sync3 <= 1'b0;
        end else begin
            row_ready_sync1 <= row_ready_toggle_ui;
            row_ready_sync2 <= row_ready_sync1;
            row_ready_sync3 <= row_ready_sync2;
            if (row_ready_sync2 ^ row_ready_sync3)
                active_buf_px <= ~active_buf_px;
        end
    end

    reg toggle_px;
    always @(posedge clk_pixel) begin
        if (pixel_rst)
            toggle_px <= 1'b0;
        else if (next_row_pulse)
            toggle_px <= ~toggle_px;
    end

    (* ASYNC_REG = "TRUE" *) reg sync1, sync2, sync3;
    always @(posedge ui_clk) begin
        if (ui_clk_rst) begin
            sync1 <= 1'b0; sync2 <= 1'b0; sync3 <= 1'b0;
        end else begin
            sync1 <= toggle_px;
            sync2 <= sync1;
            sync3 <= sync2;
        end
    end
    wire row_trig_ui = sync2 ^ sync3;

    (* ASYNC_REG = "TRUE" *) reg completed_bank_sync1, completed_bank_sync2;
    always @(posedge ui_clk) begin
        if (ui_clk_rst) begin
            completed_bank_sync1 <= 1'b1;
            completed_bank_sync2 <= 1'b1;
        end else begin
            completed_bank_sync1 <= completed_frame_bank;
            completed_bank_sync2 <= completed_bank_sync1;
        end
    end

    reg        active_buf_ui;
    reg [9:0]  row_index_ui;      // 0..FRAME_HEIGHT-1, advances only when the FSM actually starts a new prefetch pass
    reg [28:0] row_base_latched;
    reg [3:0]  row_credits;       // rows triggered but not yet started; prevents a busy FSM from skipping/desyncing rows

    // ------------------------------------------------------------------
    // Combined write-drain / read-prefetch FSM on the single MIG app port.
    // Reads always take priority over pending writes. Row/buffer state only
    // advances when a new prefetch pass actually STARTS (S_IDLE->S_RCMD),
    // never merely on row_trig_ui arriving: doing it on every pulse (as a
    // first pass did) let a busy FSM (e.g. mid write-drain) silently skip
    // rows relative to what had really been prefetched, causing a persistent
    // one-row misalignment (found by simulation, see local testbench).
    //
    // S_RCHECK: entered after EVERY single read burst (not just at row end)
    // to drain one pending write group if the write FIFO is non-empty, then
    // resume via `return_st`. A whole 40-burst row-read used to run to
    // completion before writes could be serviced again; on real DDR3
    // (higher read latency than the earlier fake-MIG testbench modeled)
    // that window can exceed the small 16-entry write FIFO's capacity,
    // silently dropping camera pixel groups (real-hardware symptom: image
    // reacts to the scene but is full of incoherent noise).
    // ------------------------------------------------------------------
    localparam S_IDLE   = 0, S_WPOP  = 1, S_WLATCH = 2, S_WCMD  = 3,
               S_WBEAT0 = 4, S_WBEAT1= 5, S_RCMD   = 6, S_RWAIT = 7,
               S_RCHECK = 8;
    reg [3:0]   st;
    reg [3:0]   return_st;
    reg [127:0] wgroup_r;
    reg [16:0]  waddr_r;
    reg [9:0]   burst_idx;
    reg         beat_sel;
    reg         read_frame_bank;

    reg        lb_wr_en;
    reg [9:0]  lb_wr_addr;
    reg [63:0] lb_wr_data;
    reg        favor_write; // alternation flag: after servicing a read, prefer a pending write next (and vice versa)

    // Fair round-robin between read-prefetch and write-drain: strict
    // read-priority let a continuously-busy display starve the small write
    // FIFO indefinitely until it silently overflowed and dropped pixel
    // groups (found by simulation - the wraparound row's last burst was
    // never written). Now, if BOTH are pending, they strictly alternate;
    // if only one is pending, that one always goes.
    wire read_ready  = (row_credits != 4'd0) && init_calib_complete;
    wire write_ready = (!wfifo_empty) && init_calib_complete;
    wire do_read     = (st == S_IDLE) && read_ready  && (!write_ready || !favor_write);
    wire do_write    = (st == S_IDLE) && write_ready && !do_read;

    always @(posedge ui_clk) begin
        if (ui_clk_rst) begin
            st               <= S_IDLE;
            burst_idx        <= 10'd0;
            beat_sel         <= 1'b0;
            row_credits      <= 4'd0;
            active_buf_ui    <= 1'b0;
            row_index_ui     <= 10'd0;
            row_base_latched <= 29'd0;
            read_frame_bank  <= 1'b1;
            row_ready_toggle_ui <= 1'b0;
            favor_write      <= 1'b0;
            return_st        <= S_IDLE;
        end else begin
            if (row_trig_ui && !do_read)
                row_credits <= row_credits + 4'd1;
            else if (!row_trig_ui && do_read)
                row_credits <= row_credits - 4'd1;
            // both in the same cycle: net zero, credits unchanged

            case (st)
                S_IDLE: begin
                    burst_idx <= 10'd0;
                    beat_sel  <= 1'b0;
                    if (do_read) begin
                        if (row_index_ui == 10'd0)
                            read_frame_bank <= completed_bank_sync2;
                        active_buf_ui <= ~active_buf_ui;
                        if (row_index_ui == FRAME_HEIGHT-1) begin
                            row_index_ui     <= 10'd0;
                            row_base_latched <= 29'd0;
                        end else begin
                            row_index_ui     <= row_index_ui + 10'd1;
                            row_base_latched <= row_base_latched + BURSTS_PER_ROW;
                        end
                        st          <= S_RCMD;
                        favor_write <= 1'b1;
                    end else if (do_write) begin
                        st          <= S_WPOP;
                        favor_write <= 1'b0;
                        return_st   <= S_IDLE;
                    end
                end
                S_WPOP:   st <= S_WLATCH;
                S_WLATCH: begin
                    wgroup_r <= wfifo_dout[127:0];
                    waddr_r  <= wfifo_dout[144:128];
                    st       <= S_WCMD;
                end
                S_WCMD:   if (app_rdy)     st <= S_WBEAT0;
                S_WBEAT0: if (app_wdf_rdy) st <= S_WBEAT1;
                S_WBEAT1: if (app_wdf_rdy) st <= return_st;
                S_RCMD:   if (app_rdy)     st <= S_RWAIT;
                S_RWAIT: begin
                    if (app_rd_data_valid) begin
                        if (beat_sel == 1'b0) begin
                            beat_sel <= 1'b1;
                        end else begin
                            beat_sel <= 1'b0;
                            if (burst_idx == BURSTS_PER_ROW-1) begin
                                row_ready_toggle_ui <= ~row_ready_toggle_ui;
                                return_st <= S_IDLE;
                            end else begin
                                burst_idx <= burst_idx + 10'd1;
                                return_st <= S_RCMD;
                            end
                            st <= S_RCHECK;
                        end
                    end
                end
                S_RCHECK: begin
                    if (!wfifo_empty) st <= S_WPOP;   // drain one pending write group before resuming
                    else               st <= return_st;
                end
                default: st <= S_IDLE;
            endcase
        end
    end

    always @(*) begin
        app_addr     = 29'd0;
        app_cmd      = 3'd0;
        app_en       = 1'b0;
        app_wdf_data = 64'd0;
        app_wdf_end  = 1'b0;
        app_wdf_wren = 1'b0;
        wfifo_rd_en  = 1'b0;
        lb_wr_en     = 1'b0;
        lb_wr_addr   = 10'd0;
        lb_wr_data   = 64'd0;

        case (st)
            S_WPOP: wfifo_rd_en = 1'b1;
            S_WCMD: begin
                app_addr = ((waddr_r[16] ? FRAME_BURSTS : 0) + waddr_r[15:0]) << 3;
                app_cmd  = 3'b000; // write
                app_en   = 1'b1;
            end
            S_WBEAT0: begin
                app_wdf_data = wgroup_r[63:0];
                app_wdf_wren = 1'b1;
            end
            S_WBEAT1: begin
                app_wdf_data = wgroup_r[127:64];
                app_wdf_wren = 1'b1;
                app_wdf_end  = 1'b1;
            end
            S_RCMD: begin
                app_addr = ((read_frame_bank ? FRAME_BURSTS : 0) +
                            row_base_latched + burst_idx) << 3;
                app_cmd  = 3'b001; // read
                app_en   = 1'b1;
            end
            S_RWAIT: begin
                if (app_rd_data_valid) begin
                    lb_wr_en   = 1'b1;
                    lb_wr_addr = (burst_idx << 1) + {9'b0, beat_sel};
                    lb_wr_data = app_rd_data;
                end
            end
            default: ; // S_IDLE, S_WLATCH: no bus activity
        endcase
    end

    // ------------------------------------------------------------------
    // Line buffers: 2 x (LINE_BUF_WORDS x 64-bit), write=ui_clk, read=clk_pixel.
    // ------------------------------------------------------------------
    reg [63:0] linebuf0 [0:LINE_BUF_WORDS-1];
    reg [63:0] linebuf1 [0:LINE_BUF_WORDS-1];
    reg [63:0] buf0_rdata, buf1_rdata;

    always @(posedge ui_clk) begin
        if (lb_wr_en) begin
            if (active_buf_ui == 1'b0) linebuf0[lb_wr_addr] <= lb_wr_data;
            else                       linebuf1[lb_wr_addr] <= lb_wr_data;
        end
    end

    always @(posedge clk_pixel) begin
        buf0_rdata <= linebuf0[col[9:2]];
        buf1_rdata <= linebuf1[col[9:2]];
    end

    reg [1:0] sub_sel_d;
    always @(posedge clk_pixel) sub_sel_d <= col[1:0];

    wire [63:0] active_rdata = active_buf_px ? buf1_rdata : buf0_rdata;
    assign pixel_out = active_rdata[({sub_sel_d, 4'b0}) +: 12];

endmodule

//////////////////////////////////////////////////////////////////////////////////
// Module Name: async_fifo
//
// Generic dual-clock FIFO (Gray-code pointers, standard Cummings-style design).
// DEPTH = 2**ADDR_WIDTH. `dout` is registered and becomes valid the cycle after
// `rd_en` is asserted while `!empty`.
//////////////////////////////////////////////////////////////////////////////////
module async_fifo #(
    parameter DATA_WIDTH = 144,
    parameter ADDR_WIDTH = 4
)(
    input                       wr_clk,
    input                       wr_rst,
    input                       wr_en,
    input      [DATA_WIDTH-1:0] din,
    output                      full,

    input                       rd_clk,
    input                       rd_rst,
    input                       rd_en,
    output reg [DATA_WIDTH-1:0] dout,
    output                      empty
);
    localparam DEPTH = (1 << ADDR_WIDTH);

    reg [DATA_WIDTH-1:0] mem [0:DEPTH-1];

    reg [ADDR_WIDTH:0] wr_ptr_bin = 0, wr_ptr_gray = 0;
    reg [ADDR_WIDTH:0] rd_ptr_bin = 0, rd_ptr_gray = 0;

    // Must wrap at exactly ADDR_WIDTH+1 bits BEFORE the shift/XOR: with an
    // unsized literal, "wr_ptr_bin+1" is evaluated wider than the register,
    // so the Gray code came out wrong exactly at pointer wraparound (found
    // by simulation - broke only once every 2**(ADDR_WIDTH+1) pushes).
    wire [ADDR_WIDTH:0] wr_ptr_bin_next  = wr_ptr_bin + {{ADDR_WIDTH{1'b0}}, 1'b1};
    wire [ADDR_WIDTH:0] rd_ptr_bin_next  = rd_ptr_bin + {{ADDR_WIDTH{1'b0}}, 1'b1};
    wire [ADDR_WIDTH:0] wr_ptr_gray_next = (wr_ptr_bin_next >> 1) ^ wr_ptr_bin_next;
    wire [ADDR_WIDTH:0] rd_ptr_gray_next = (rd_ptr_bin_next >> 1) ^ rd_ptr_bin_next;

    (* ASYNC_REG = "TRUE" *) reg [ADDR_WIDTH:0] wr_ptr_gray_s1, wr_ptr_gray_s2;
    always @(posedge rd_clk) begin
        if (rd_rst) begin
            wr_ptr_gray_s1 <= 0;
            wr_ptr_gray_s2 <= 0;
        end else begin
            wr_ptr_gray_s1 <= wr_ptr_gray;
            wr_ptr_gray_s2 <= wr_ptr_gray_s1;
        end
    end

    (* ASYNC_REG = "TRUE" *) reg [ADDR_WIDTH:0] rd_ptr_gray_s1, rd_ptr_gray_s2;
    always @(posedge wr_clk) begin
        if (wr_rst) begin
            rd_ptr_gray_s1 <= 0;
            rd_ptr_gray_s2 <= 0;
        end else begin
            rd_ptr_gray_s1 <= rd_ptr_gray;
            rd_ptr_gray_s2 <= rd_ptr_gray_s1;
        end
    end

    always @(posedge wr_clk) begin
        if (wr_rst) begin
            wr_ptr_bin  <= 0;
            wr_ptr_gray <= 0;
        end else if (wr_en && !full) begin
            wr_ptr_bin  <= wr_ptr_bin_next;
            wr_ptr_gray <= wr_ptr_gray_next;
        end
    end
    // BRAM write kept in its own always block, enabled ONLY by wr_en/full
    // (no wr_rst term), so the inferred RAMB's WE control pin never traces
    // back to an asynchronously-reset register (fixes DRC REQP-1839/1840).
    always @(posedge wr_clk) begin
        if (wr_en && !full)
            mem[wr_ptr_bin[ADDR_WIDTH-1:0]] <= din;
    end
    assign full = (wr_ptr_gray_next == {~rd_ptr_gray_s2[ADDR_WIDTH:ADDR_WIDTH-1], rd_ptr_gray_s2[ADDR_WIDTH-2:0]});

    always @(posedge rd_clk) begin
        if (rd_rst) begin
            rd_ptr_bin  <= 0;
            rd_ptr_gray <= 0;
        end else if (rd_en && !empty) begin
            rd_ptr_bin  <= rd_ptr_bin_next;
            rd_ptr_gray <= rd_ptr_gray_next;
        end
    end
    // Same separation for the read port's ENARDEN control pin.
    always @(posedge rd_clk) begin
        if (rd_en && !empty)
            dout <= mem[rd_ptr_bin[ADDR_WIDTH-1:0]];
    end
    assign empty = (rd_ptr_gray == wr_ptr_gray_s2);

endmodule
