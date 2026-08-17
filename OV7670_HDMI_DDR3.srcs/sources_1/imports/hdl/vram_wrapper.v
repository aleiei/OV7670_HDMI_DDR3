`timescale 1 ps / 1 ps
//
// vram_wrapper.v
//
// True dual-clock dual-port BRAM – 76800 x 12-bit (320x240 RGB444 frame buffer).
// Port A: write (camera capture), Port B: read (video output).
//
// Implemented as a plain behavioural RAM so that Vivado 2024.1 infers
// RAMB36E2 primitives automatically – no IP Catalog dependency.

module vram_wrapper (
    // Port A – write
    input  [16:0] BRAM_PORTA_addr,
    input         BRAM_PORTA_clk,
    input  [11:0] BRAM_PORTA_din,
    input         BRAM_PORTA_en,
    input  [ 0:0] BRAM_PORTA_we,
    // Port B – read
    input  [16:0] BRAM_PORTB_addr,
    input         BRAM_PORTB_clk,
    output [11:0] BRAM_PORTB_dout,
    input         BRAM_PORTB_en
);

    (* ram_style = "block" *)
    reg [11:0] mem [0:76799];

    // Port A – synchronous write
    always @(posedge BRAM_PORTA_clk) begin
        if (BRAM_PORTA_en && BRAM_PORTA_we)
            mem[BRAM_PORTA_addr] <= BRAM_PORTA_din;
    end

    // Port B – synchronous read with output register
    reg [11:0] doutb_reg = 12'b0;
    always @(posedge BRAM_PORTB_clk) begin
        if (BRAM_PORTB_en)
            doutb_reg <= mem[BRAM_PORTB_addr];
    end
    assign BRAM_PORTB_dout = doutb_reg;

endmodule
