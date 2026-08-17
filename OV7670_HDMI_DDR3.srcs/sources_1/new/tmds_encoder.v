`timescale 1ns / 1ps
//
// tmds_encoder.v
//
// TMDS 8b10b encoder – DVI 1.0 Appendix A.
//
// Inputs
//   clk  : pixel clock (25 MHz)
//   din  : 8-bit pixel data for the channel
//   ctrl : 2-bit control word used during blanking (ch0: {vsync, hsync})
//   de   : data-enable; high = active-video, low = blanking/sync period
//
// Output
//   dout : 10-bit TMDS-encoded word

module tmds_encoder (
    input            clk,
    input      [7:0] din,
    input      [1:0] ctrl,
    input            de,
    output reg [9:0] dout
);

    // ---- count ones helper (combinational) ----
    function [3:0] ones;
        input [7:0] d;
        integer i;
        begin
            ones = 4'd0;
            for (i = 0; i < 8; i = i + 1)
                ones = ones + {3'b0, d[i]};
        end
    endfunction

    wire [3:0] n1d = ones(din);

    // ---- Step 1: build q_m ----
    // Choose XOR (q_m[8]=1) or XNOR (q_m[8]=0) encoding
    wire use_xnor = (n1d > 4) || (n1d == 4 && din[0] == 1'b0);

    wire [8:0] qm;
    assign qm[0] = din[0];
    assign qm[1] = use_xnor ? (qm[0] ~^ din[1]) : (qm[0] ^ din[1]);
    assign qm[2] = use_xnor ? (qm[1] ~^ din[2]) : (qm[1] ^ din[2]);
    assign qm[3] = use_xnor ? (qm[2] ~^ din[3]) : (qm[2] ^ din[3]);
    assign qm[4] = use_xnor ? (qm[3] ~^ din[4]) : (qm[3] ^ din[4]);
    assign qm[5] = use_xnor ? (qm[4] ~^ din[5]) : (qm[4] ^ din[5]);
    assign qm[6] = use_xnor ? (qm[5] ~^ din[6]) : (qm[5] ^ din[6]);
    assign qm[7] = use_xnor ? (qm[6] ~^ din[7]) : (qm[6] ^ din[7]);
    assign qm[8] = ~use_xnor;

    // ---- Step 2: disparity correction ----
    wire [3:0] n1qm = ones(qm[7:0]);
    wire [3:0] n0qm = 4'd8 - n1qm;

    // signed running disparity counter (range -8..+8, 5 bits)
    reg signed [4:0] cnt = 5'sd0;

    always @(posedge clk) begin
        if (!de) begin
            // Control period – use reserved TMDS control tokens
            case (ctrl)
                2'b00: dout <= 10'b1101010100;
                2'b01: dout <= 10'b0010101011;
                2'b10: dout <= 10'b0101010100;
                2'b11: dout <= 10'b1010101011;
            endcase
            cnt <= 5'sd0;
        end else begin
            if (cnt == 5'sd0 || n1qm == n0qm) begin
                // No accumulated disparity bias: invert data if qm[8]=0
                dout[9]   <= ~qm[8];
                dout[8]   <=  qm[8];
                dout[7:0] <= qm[8] ? qm[7:0] : ~qm[7:0];
                if (!qm[8])
                    cnt <= cnt + $signed({1'b0, n0qm}) - $signed({1'b0, n1qm});
                else
                    cnt <= cnt + $signed({1'b0, n1qm}) - $signed({1'b0, n0qm});
            end else begin
                if ((cnt > 5'sd0 && n1qm > n0qm) ||
                    (cnt < 5'sd0 && n0qm > n1qm)) begin
                    dout[9]   <= 1'b1;
                    dout[8]   <= qm[8];
                    dout[7:0] <= ~qm[7:0];
                    cnt <= cnt + (qm[8] ? 5'sd2 : 5'sd0)
                               + $signed({1'b0, n0qm})
                               - $signed({1'b0, n1qm});
                end else begin
                    dout[9]   <= 1'b0;
                    dout[8]   <= qm[8];
                    dout[7:0] <= qm[7:0];
                    cnt <= cnt - (~qm[8] ? 5'sd2 : 5'sd0)
                               + $signed({1'b0, n1qm})
                               - $signed({1'b0, n0qm});
                end
            end
        end
    end

endmodule
