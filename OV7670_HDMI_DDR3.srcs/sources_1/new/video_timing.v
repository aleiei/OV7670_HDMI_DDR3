`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Module Name: vga
//
// 640x480@60Hz timing generator. Displays a FRAME_WIDTH x FRAME_HEIGHT source
// image (fed by the DDR3 framebuffer bridge) inside a window positioned at
// (WIN_H_START, WIN_V_START) on the 640x480 canvas; everything else is black.
//
// No rotation/crop here (removed vs. the old BRAM version): the DDR3 bridge's
// line-buffer read is burst/row oriented, incompatible with the old column-wise
// 90 deg rotation fetch. FRAME_WIDTH/HEIGHT are parameters so bumping to native
// 640x480 later (WIN_H_START=WIN_V_START=0) needs no further changes here.
//
// `col`/`next_row_pulse` drive the ddr3_fb_bridge; `frame_pixel` comes back
// FB_LATENCY clk25 cycles later (bridge's line-buffer read latency).
//////////////////////////////////////////////////////////////////////////////////

module vga #(
    parameter FRAME_WIDTH  = 320,
    parameter FRAME_HEIGHT = 240,
    parameter WIN_H_START  = 160,
    parameter WIN_V_START  = 120,
    parameter FB_LATENCY   = 2
)(
    input             clk25,
    input             reset,
    output reg [3:0]  vga_red,
    output reg [3:0]  vga_green,
    output reg [3:0]  vga_blue,
    output reg        vga_hsync,
    output reg        vga_vsync,
    output reg        vga_de,        // data-enable: high during the full 640x480 active region
    input             test_pattern_en,
    output reg [9:0]  col,           // column within the source frame, valid 0..FRAME_WIDTH-1
    output reg        next_row_pulse,// 1-cycle pulse, once per line, before the (possibly windowed) row begins
    input      [11:0] frame_pixel    // bridge readback, FB_LATENCY cycles behind `col`
    );

    localparam hRez        = 640;
    localparam hStartSync  = 640+16;
    localparam hEndSync    = 640+16+96;
    localparam hMaxCount   = 800;

    localparam vRez        = 480;
    localparam vStartSync  = 480+10;
    localparam vEndSync    = 480+10+2;
    localparam vMaxCount   = 480+10+2+33;

    localparam hsync_active = 0;
    localparam vsync_active = 0;

    localparam WIN_H_END = WIN_H_START + FRAME_WIDTH;
    localparam WIN_V_END = WIN_V_START + FRAME_HEIGHT;

    reg [9:0] hCounter = 10'b0;
    reg [9:0] vCounter = 10'b0;

    // Horizontal window test shifted FB_LATENCY cycles early so `frame_pixel`
    // lines up with the real hCounter once it comes back from the bridge.
    wire in_h_window_early = (hCounter + FB_LATENCY >= WIN_H_START) && (hCounter + FB_LATENCY < WIN_H_END);
    wire in_v_window       = (vCounter >= WIN_V_START) && (vCounter < WIN_V_END);
    wire [9:0] next_v_line = (vCounter == vMaxCount-1) ? 10'd0 : vCounter + 10'd1;

    reg [FB_LATENCY-1:0] win_pipe; // delayed in_h_window_early && in_v_window, aligned with frame_pixel

    always @(posedge clk25) begin
        if (reset) begin
            hCounter       <= 10'd0;
            vCounter       <= 10'd0;
            col            <= 10'd0;
            next_row_pulse <= 1'b0;
            win_pipe       <= {FB_LATENCY{1'b0}};
            vga_red        <= 4'd0;
            vga_green      <= 4'd0;
            vga_blue       <= 4'd0;
            vga_hsync      <= ~hsync_active;
            vga_vsync      <= ~vsync_active;
            vga_de         <= 1'b0;
        end else begin
        // ---- Horizontal/vertical counters ----
        if (hCounter == hMaxCount-1) begin
            hCounter <= 10'b0;
            if (vCounter == vMaxCount-1)
                vCounter <= 10'b0;
            else
                vCounter <= vCounter + 1'b1;
        end else begin
            hCounter <= hCounter + 1'b1;
        end

        // ---- Column fed to the bridge, valid ahead by FB_LATENCY ----
        if (in_h_window_early)
            col <= hCounter + FB_LATENCY - WIN_H_START;
        else
            col <= 10'b0;

        // ---- Row prefetch pulse: fires during horizontal blanking for every
        // displayed row, including the vertical wrap from vMaxCount-1 to 0. ----
        next_row_pulse <= 1'b0;
        if (hCounter == hRez-1) begin
            if (next_v_line >= WIN_V_START && next_v_line < WIN_V_END)
                next_row_pulse <= 1'b1;
        end

        // ---- Delay line aligning window validity with frame_pixel latency ----
        win_pipe <= {win_pipe[FB_LATENCY-2:0], (in_h_window_early && in_v_window)};

        // ---- Pixel output ----
        if (test_pattern_en) begin
            if (hCounter < hRez && vCounter < vRez) begin
                vga_red   <= {4{hCounter < (hRez / 3)}};
                vga_green <= {4{hCounter >= (hRez / 3) && hCounter < ((hRez * 2) / 3)}};
                vga_blue  <= {4{hCounter >= ((hRez * 2) / 3)}};
            end else begin
                vga_red   <= 4'b0;
                vga_green <= 4'b0;
                vga_blue  <= 4'b0;
            end
        end else if (win_pipe[FB_LATENCY-1]) begin
            vga_red   <= frame_pixel[11:8];
            vga_green <= frame_pixel[7:4];
            vga_blue  <= frame_pixel[3:0];
        end else begin
            vga_red   <= 4'b0;
            vga_green <= 4'b0;
            vga_blue  <= 4'b0;
        end

        // ---- Sync pulses ----
        if (hCounter > hStartSync && hCounter <= hEndSync)
            vga_hsync <= hsync_active;
        else
            vga_hsync <= ~hsync_active;

        if (vCounter >= vStartSync && vCounter < vEndSync)
            vga_vsync <= vsync_active;
        else
            vga_vsync <= ~vsync_active;

        // Data-enable: high during full 640x480 active region
        vga_de <= (hCounter < hRez) && (vCounter < vRez);
        end
    end
endmodule

