`timescale 1ns / 1ps
//
// hdmi_tx.v
//
// Serializes four 10-bit TMDS words (ch0/ch1/ch2 + clock) to HDMI
// differential pairs using Artix-7 OSERDESE2 in DDR 10:1 mode + OBUFDS.
//
// Clocking
//   clk_pixel : 25 MHz   – pixel / CLKDIV for OSERDESE2
//   clk_5x    : 125 MHz  – 5x DDR serial clock for OSERDESE2
//
// TMDS channels
//   tmds_ch0  : Blue  channel (carries HSYNC/VSYNC in control periods)
//   tmds_ch1  : Green channel
//   tmds_ch2  : Red   channel
//
// HDMI pins follow MicroPhase A7 Lite schematic naming.

module hdmi_tx (
    input        clk_pixel,
    input        clk_5x,
    input        reset,
    input  [9:0] tmds_ch0,
    input  [9:0] tmds_ch1,
    input  [9:0] tmds_ch2,
    output       hdmi_clk_p, hdmi_clk_n,
    output       hdmi_d0_p,  hdmi_d0_n,
    output       hdmi_d1_p,  hdmi_d1_n,
    output       hdmi_d2_p,  hdmi_d2_n
);

    wire hdmi_clk_se;

    ODDR #(
        .DDR_CLK_EDGE("SAME_EDGE"),
        .INIT        (1'b0),
        .SRTYPE      ("SYNC")
    ) u_clk_oddr (
        .Q  (hdmi_clk_se),
        .C  (clk_pixel),
        .CE (1'b1),
        .D1 (1'b1),
        .D2 (1'b0),
        .R  (reset),
        .S  (1'b0)
    );

    OBUFDS u_clk_obufds (
        .I  (hdmi_clk_se),
        .O  (hdmi_clk_p),
        .OB (hdmi_clk_n)
    );

    tmds_serdes u_ch0  (.clk_pixel(clk_pixel), .clk_5x(clk_5x), .reset(reset),
                        .tmds(tmds_ch0),
                        .out_p(hdmi_d0_p), .out_n(hdmi_d0_n));

    tmds_serdes u_ch1  (.clk_pixel(clk_pixel), .clk_5x(clk_5x), .reset(reset),
                        .tmds(tmds_ch1),
                        .out_p(hdmi_d1_p), .out_n(hdmi_d1_n));

    tmds_serdes u_ch2  (.clk_pixel(clk_pixel), .clk_5x(clk_5x), .reset(reset),
                        .tmds(tmds_ch2),
                        .out_p(hdmi_d2_p), .out_n(hdmi_d2_n));

endmodule


// ---------------------------------------------------------------------------
// tmds_serdes – single TMDS channel: 10:1 DDR serializer + OBUFDS
//
// Uses a cascaded OSERDESE2 master/slave pair (required for DATA_WIDTH > 8).
// DATA_RATE = DDR, DATA_WIDTH = 10  →  CLK = 5× pixel, CLKDIV = pixel clock.
// ---------------------------------------------------------------------------
module tmds_serdes (
    input        clk_pixel,
    input        clk_5x,
    input        reset,
    input  [9:0] tmds,
    output       out_p,
    output       out_n
);

    wire serial_out;
    wire shift1, shift2;

    OSERDESE2 #(
        .DATA_RATE_OQ   ("DDR"),
        .DATA_RATE_TQ   ("SDR"),
        .DATA_WIDTH     (10),
        .TRISTATE_WIDTH (1),
        .SERDES_MODE    ("MASTER")
    ) oserdes_master (
        .OQ       (serial_out),
        .OFB      (),
        .TQ       (), .TFB  (),
        .SHIFTOUT1(), .SHIFTOUT2(),
        .TBYTEOUT (),
        .CLK      (clk_5x),
        .CLKDIV   (clk_pixel),
        .D1       (tmds[0]),
        .D2       (tmds[1]),
        .D3       (tmds[2]),
        .D4       (tmds[3]),
        .D5       (tmds[4]),
        .D6       (tmds[5]),
        .D7       (tmds[6]),
        .D8       (tmds[7]),
        .TCE      (1'b0), .OCE (1'b1),
        .TBYTEIN  (1'b0), .RST (reset),
        .SHIFTIN1 (shift1),
        .SHIFTIN2 (shift2),
        .T1(1'b0), .T2(1'b0), .T3(1'b0), .T4(1'b0)
    );

    OSERDESE2 #(
        .DATA_RATE_OQ   ("DDR"),
        .DATA_RATE_TQ   ("SDR"),
        .DATA_WIDTH     (10),
        .TRISTATE_WIDTH (1),
        .SERDES_MODE    ("SLAVE")
    ) oserdes_slave (
        .OQ       (),
        .OFB      (),
        .TQ       (), .TFB  (),
        .SHIFTOUT1(shift1),
        .SHIFTOUT2(shift2),
        .TBYTEOUT (),
        .CLK      (clk_5x),
        .CLKDIV   (clk_pixel),
        .D1       (1'b0),
        .D2       (1'b0),
        .D3       (tmds[8]),
        .D4       (tmds[9]),
        .D5       (1'b0), .D6(1'b0), .D7(1'b0), .D8(1'b0),
        .TCE      (1'b0), .OCE (1'b1),
        .TBYTEIN  (1'b0), .RST (reset),
        .SHIFTIN1 (1'b0), .SHIFTIN2(1'b0),
        .T1(1'b0), .T2(1'b0), .T3(1'b0), .T4(1'b0)
    );

    OBUFDS obufds_inst (
        .I  (serial_out),
        .O  (out_p),
        .OB (out_n)
    );

endmodule
