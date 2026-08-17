`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// // Engineer: Alessandro Orlando
// 
// Create Date: 2026/15/08 
// Design Name: 
// Module Name: ov7670_capture
// Project Name: OV7670_HDMI_DDR3
// Target Devices: 
// Tool Versions: 
// Description: 
// 
//////////////////////////////////////////////////////////////////////////////////

module ov7670_capture(
    input pclk,
    input vsync,
    input href,
    input[7:0] d,
    output[18:0] addr,
    output reg[15:0] dout,
    output reg wr
    );
    reg [15:0] d_latch;
    reg [18:0] address; 
    reg [1:0] wr_hold;  
    reg pd=0;
    initial dout = 16'b0000000000000000;
    initial d_latch = 16'b0;
    initial address = 19'b0;
    initial wr_hold = 2'b0;  
    assign addr = address?address-1:19'b0;

    always@(posedge pclk)
    begin
    if( vsync ==1) 
        begin
        address <=17'b0;
        wr_hold <=  2'b0;
        end
    else 
        begin
        if(address<307200)//640*480 framebuffer capacity
		      address<=address;
        else
            address <= 307200;   
        wr_hold <= {wr_hold[0] , (href &&( ! wr_hold[0])) };
        d_latch <= {d_latch[7:0] , d};
        wr <= 0;
        
        if (wr_hold[1] ==1 )
            begin
            pd=~pd;
           // if(pd)
            address<=address+1;
            dout[15:0]  <= {d_latch[15:11] , d_latch[10:5] , d_latch[4:0] };    
            wr <= 1; 
            end

        end
    end

endmodule

