`timescale 1ps / 1ps
//
// clk_wiz_hdmi.v
//
// MMCM wrapper for MicroPhase A7 Lite (50 MHz input).
// Generates the two clocks required for HDMI TMDS serialisation:
//
//   clk_pixel : 25.2 MHz – pixel clock, CLKDIV for OSERDESE2, also drives VGA timing
//   clk_5x    : 126 MHz  – 5× DDR serial clock for OSERDESE2
//
// MMCM settings (Artix-7, VCO range 600–1200 MHz)
//   CLKIN1_PERIOD   = 20.000 ns  (50 MHz)
//   CLKFBOUT_MULT_F = 63          → VCO = 630 MHz
//   DIVCLK_DIVIDE   = 5
//   CLKOUT0 ÷ 5    = 126 MHz  (clk_5x)
//   CLKOUT1 ÷ 25   = 25.2 MHz (clk_pixel)

module clk_wiz_hdmi (
    input  clk_in,      // 50 MHz board oscillator
    output clk_pixel,   // 25.2 MHz
    output clk_5x,      // 126 MHz
    output clk_mig,     // 310.078 MHz for MIG sys_clk_i
    output clk_ref200,  // 200 MHz for MIG clk_ref_i / IDELAYCTRL
    output locked
);

    wire clkfbout, clkfbout_buf;
    wire clk_5x_raw, clk_pixel_raw;
    wire locked_hdmi;

    wire clkfbout_mig, clkfbout_mig_buf;
    wire clk_mig_raw;
    wire locked_mig;

    wire clkfbout_ref, clkfbout_ref_buf;
    wire clk_ref200_raw;
    wire locked_ref;

    MMCME2_ADV #(
        .BANDWIDTH            ("OPTIMIZED"),
        .CLKOUT4_CASCADE      ("FALSE"),
        .COMPENSATION         ("ZHOLD"),
        .STARTUP_WAIT         ("FALSE"),
        .DIVCLK_DIVIDE        (5),
        .CLKFBOUT_MULT_F      (63.000),
        .CLKFBOUT_PHASE       (0.000),
        .CLKFBOUT_USE_FINE_PS ("FALSE"),
        .CLKIN1_PERIOD        (20.000),   // 50 MHz input
        // CLKOUT0 → 126 MHz (5× pixel)
        .CLKOUT0_DIVIDE_F     (5.000),
        .CLKOUT0_PHASE        (0.000),
        .CLKOUT0_DUTY_CYCLE   (0.500),
        .CLKOUT0_USE_FINE_PS  ("FALSE"),
        // CLKOUT1 → 25.2 MHz (pixel clock)
        .CLKOUT1_DIVIDE       (25),
        .CLKOUT1_PHASE        (0.000),
        .CLKOUT1_DUTY_CYCLE   (0.500),
        .CLKOUT1_USE_FINE_PS  ("FALSE"),
        .REF_JITTER1          (0.010),
        .REF_JITTER2          (0.010),
        .SS_EN                ("FALSE"),
        .SS_MODE              ("CENTER_HIGH"),
        .SS_MOD_PERIOD        (10000)
    ) mmcm_inst (
        // Feedback
        .CLKFBIN     (clkfbout_buf),
        .CLKFBOUT    (clkfbout),
        .CLKFBOUTB   (),
        // Outputs
        .CLKOUT0     (clk_5x_raw),
        .CLKOUT0B    (),
        .CLKOUT1     (clk_pixel_raw),
        .CLKOUT1B    (),
        .CLKOUT2     (), .CLKOUT2B  (),
        .CLKOUT3     (), .CLKOUT3B  (),
        .CLKOUT4     (),
        .CLKOUT5     (),
        .CLKOUT6     (),
        // Input
        .CLKIN1      (clk_in),
        .CLKIN2      (1'b0),
        .CLKINSEL    (1'b1),
        // DRP (unused)
        .DADDR       (7'h0), .DCLK(1'b0), .DEN(1'b0),
        .DI          (16'h0), .DO(), .DRDY(), .DWE(1'b0),
        // Dynamic phase shift (unused)
        .PSCLK       (1'b0), .PSEN(1'b0),
        .PSINCDEC    (1'b0), .PSDONE(),
        // Status
        .LOCKED      (locked_hdmi),
        .CLKINSTOPPED(), .CLKFBSTOPPED(),
        .PWRDWN      (1'b0),
        .RST         (1'b0)
    );

    // MIG system clock @ 310.078 MHz from 50 MHz input.
    // VCO = 50 * (62 / 5) = 620 MHz, CLKOUT0 = 620 / 2 = 310 MHz.
    MMCME2_ADV #(
        .BANDWIDTH            ("OPTIMIZED"),
        .CLKOUT4_CASCADE      ("FALSE"),
        .COMPENSATION         ("ZHOLD"),
        .STARTUP_WAIT         ("FALSE"),
        .DIVCLK_DIVIDE        (5),
        .CLKFBOUT_MULT_F      (62.000),
        .CLKFBOUT_PHASE       (0.000),
        .CLKFBOUT_USE_FINE_PS ("FALSE"),
        .CLKIN1_PERIOD        (20.000),
        .CLKOUT0_DIVIDE_F     (2.000),
        .CLKOUT0_PHASE        (0.000),
        .CLKOUT0_DUTY_CYCLE   (0.500),
        .CLKOUT0_USE_FINE_PS  ("FALSE"),
        .CLKOUT1_DIVIDE       (1),
        .CLKOUT1_PHASE        (0.000),
        .CLKOUT1_DUTY_CYCLE   (0.500),
        .CLKOUT1_USE_FINE_PS  ("FALSE"),
        .REF_JITTER1          (0.010),
        .REF_JITTER2          (0.010),
        .SS_EN                ("FALSE"),
        .SS_MODE              ("CENTER_HIGH"),
        .SS_MOD_PERIOD        (10000)
    ) mmcm_mig_inst (
        .CLKFBIN     (clkfbout_mig_buf),
        .CLKFBOUT    (clkfbout_mig),
        .CLKFBOUTB   (),
        .CLKOUT0     (clk_mig_raw),
        .CLKOUT0B    (),
        .CLKOUT1     (), .CLKOUT1B(),
        .CLKOUT2     (), .CLKOUT2B(),
        .CLKOUT3     (), .CLKOUT3B(),
        .CLKOUT4     (),
        .CLKOUT5     (),
        .CLKOUT6     (),
        .CLKIN1      (clk_in),
        .CLKIN2      (1'b0),
        .CLKINSEL    (1'b1),
        .DADDR       (7'h0), .DCLK(1'b0), .DEN(1'b0),
        .DI          (16'h0), .DO(), .DRDY(), .DWE(1'b0),
        .PSCLK       (1'b0), .PSEN(1'b0), .PSINCDEC(1'b0), .PSDONE(),
        .LOCKED      (locked_mig),
        .CLKINSTOPPED(), .CLKFBSTOPPED(),
        .PWRDWN      (1'b0),
        .RST         (1'b0)
    );

    // MIG reference clock @ 200.000 MHz from 50 MHz input.
    // VCO = 50 * (12 / 1) = 600 MHz, CLKOUT0 = 600 / 3 = 200 MHz.
    MMCME2_ADV #(
        .BANDWIDTH            ("OPTIMIZED"),
        .CLKOUT4_CASCADE      ("FALSE"),
        .COMPENSATION         ("ZHOLD"),
        .STARTUP_WAIT         ("FALSE"),
        .DIVCLK_DIVIDE        (1),
        .CLKFBOUT_MULT_F      (12.000),
        .CLKFBOUT_PHASE       (0.000),
        .CLKFBOUT_USE_FINE_PS ("FALSE"),
        .CLKIN1_PERIOD        (20.000),
        .CLKOUT0_DIVIDE_F     (3.000),
        .CLKOUT0_PHASE        (0.000),
        .CLKOUT0_DUTY_CYCLE   (0.500),
        .CLKOUT0_USE_FINE_PS  ("FALSE"),
        .CLKOUT1_DIVIDE       (1),
        .CLKOUT1_PHASE        (0.000),
        .CLKOUT1_DUTY_CYCLE   (0.500),
        .CLKOUT1_USE_FINE_PS  ("FALSE"),
        .REF_JITTER1          (0.010),
        .REF_JITTER2          (0.010),
        .SS_EN                ("FALSE"),
        .SS_MODE              ("CENTER_HIGH"),
        .SS_MOD_PERIOD        (10000)
    ) mmcm_ref_inst (
        .CLKFBIN     (clkfbout_ref_buf),
        .CLKFBOUT    (clkfbout_ref),
        .CLKFBOUTB   (),
        .CLKOUT0     (clk_ref200_raw),
        .CLKOUT0B    (),
        .CLKOUT1     (), .CLKOUT1B(),
        .CLKOUT2     (), .CLKOUT2B(),
        .CLKOUT3     (), .CLKOUT3B(),
        .CLKOUT4     (),
        .CLKOUT5     (),
        .CLKOUT6     (),
        .CLKIN1      (clk_in),
        .CLKIN2      (1'b0),
        .CLKINSEL    (1'b1),
        .DADDR       (7'h0), .DCLK(1'b0), .DEN(1'b0),
        .DI          (16'h0), .DO(), .DRDY(), .DWE(1'b0),
        .PSCLK       (1'b0), .PSEN(1'b0), .PSINCDEC(1'b0), .PSDONE(),
        .LOCKED      (locked_ref),
        .CLKINSTOPPED(), .CLKFBSTOPPED(),
        .PWRDWN      (1'b0),
        .RST         (1'b0)
    );

    BUFG u_fbk    (.I(clkfbout),     .O(clkfbout_buf));
    BUFG u_clk5x  (.I(clk_5x_raw),   .O(clk_5x));
    BUFG u_clkpx  (.I(clk_pixel_raw),.O(clk_pixel));
    BUFG u_fbk_mig   (.I(clkfbout_mig),    .O(clkfbout_mig_buf));
    BUFG u_clk_mig   (.I(clk_mig_raw),     .O(clk_mig));
    BUFG u_fbk_ref   (.I(clkfbout_ref),    .O(clkfbout_ref_buf));
    BUFG u_clk_ref   (.I(clk_ref200_raw),  .O(clk_ref200));

    assign locked = locked_hdmi & locked_mig & locked_ref;

endmodule
