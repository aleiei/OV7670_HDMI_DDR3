## -----------------------------------------------------------------------------
## MicroPhase A7 Lite – OV7670 → HDMI project
## - 50 MHz system clock from board oscillator
## - Active-low reset from on-board reset key
## - OV7670 camera routed on JP1 GPIO header
## -----------------------------------------------------------------------------

## Configuration bank voltage (fixes DRC CFGBVS-1)
## A7 Lite bank 0 powered at 3.3V via VCCO
set_property CFGBVS VCCO [current_design]
set_property CONFIG_VOLTAGE 3.3 [current_design]

## QSPI flash configuration (IS25LP128F – 4-bit bus, 33 MHz)
set_property BITSTREAM.CONFIG.SPI_BUSWIDTH 4 [current_design]
set_property BITSTREAM.CONFIG.CONFIGRATE  33 [current_design]
set_property BITSTREAM.CONFIG.SPI_FALL_EDGE YES [current_design]
set_property CONFIG_MODE SPIx4 [current_design]

## - HDMI TX on onboard connector (TMDS_33 differential pairs)
## -----------------------------------------------------------------------------

## System clock / reset
set_property PACKAGE_PIN J19 [get_ports sys_clk_pin]
set_property IOSTANDARD LVCMOS33 [get_ports sys_clk_pin]
create_clock -name sys_clk_pin -period 20.000 [get_ports sys_clk_pin]

set_property PACKAGE_PIN L18 [get_ports sys_rst_n_pin]
set_property IOSTANDARD LVCMOS33 [get_ports sys_rst_n_pin]
set_property PULLUP true [get_ports sys_rst_n_pin]

## Debug LEDs
set_property PACKAGE_PIN M18 [get_ports {led_pin[0]}]
set_property IOSTANDARD LVCMOS33 [get_ports {led_pin[0]}]
set_property PACKAGE_PIN N18 [get_ports {led_pin[1]}]
set_property IOSTANDARD LVCMOS33 [get_ports {led_pin[1]}]
set_property PACKAGE_PIN A15 [get_ports {led_pin[2]}]
set_property IOSTANDARD LVCMOS33 [get_ports {led_pin[2]}]
set_property PACKAGE_PIN A16 [get_ports {led_pin[3]}]
set_property IOSTANDARD LVCMOS33 [get_ports {led_pin[3]}]

## OV7670 camera on JP1
set_property PACKAGE_PIN A18 [get_ports siod]
set_property IOSTANDARD LVCMOS33 [get_ports siod]
set_property PULLUP true [get_ports siod]

set_property PACKAGE_PIN F14 [get_ports sioc]
set_property IOSTANDARD LVCMOS33 [get_ports sioc]

set_property PACKAGE_PIN E13 [get_ports href]
set_property IOSTANDARD LVCMOS33 [get_ports href]

set_property PACKAGE_PIN E14 [get_ports vsync]
set_property IOSTANDARD LVCMOS33 [get_ports vsync]

set_property PACKAGE_PIN D14 [get_ports xclk]
set_property IOSTANDARD LVCMOS33 [get_ports xclk]

set_property PACKAGE_PIN D15 [get_ports pclk]
set_property IOSTANDARD LVCMOS33 [get_ports pclk]
create_clock -name cam_pclk -period 40.000 [get_ports pclk]
# OV7670 PCLK enters from a non-CCIO pin on this board. Allow non-dedicated
# routing for the inferred pclk->BUFG path to avoid Place 30-574.
set_property CLOCK_DEDICATED_ROUTE FALSE [get_nets pclk]

set_property PACKAGE_PIN E16 [get_ports {data_pin[0]}]
set_property IOSTANDARD LVCMOS33 [get_ports {data_pin[0]}]
set_property PACKAGE_PIN D16 [get_ports {data_pin[1]}]
set_property IOSTANDARD LVCMOS33 [get_ports {data_pin[1]}]
set_property PACKAGE_PIN D17 [get_ports {data_pin[2]}]
set_property IOSTANDARD LVCMOS33 [get_ports {data_pin[2]}]
set_property PACKAGE_PIN C17 [get_ports {data_pin[3]}]
set_property IOSTANDARD LVCMOS33 [get_ports {data_pin[3]}]
set_property PACKAGE_PIN C13 [get_ports {data_pin[4]}]
set_property IOSTANDARD LVCMOS33 [get_ports {data_pin[4]}]
set_property PACKAGE_PIN B13 [get_ports {data_pin[5]}]
set_property IOSTANDARD LVCMOS33 [get_ports {data_pin[5]}]
set_property PACKAGE_PIN A13 [get_ports {data_pin[6]}]
set_property IOSTANDARD LVCMOS33 [get_ports {data_pin[6]}]
set_property PACKAGE_PIN A14 [get_ports {data_pin[7]}]
set_property IOSTANDARD LVCMOS33 [get_ports {data_pin[7]}]

set_property PACKAGE_PIN C14 [get_ports pwdn]
set_property IOSTANDARD LVCMOS33 [get_ports pwdn]

set_property PACKAGE_PIN C15 [get_ports reset_pin]
set_property IOSTANDARD LVCMOS33 [get_ports reset_pin]

## HDMI TX – onboard connector (MicroPhase A7 Lite)
## TMDS_33 differential pairs; led_pin[2/3] repurposed for debug if needed
set_property PACKAGE_PIN K21 [get_ports hdmi_d0_p]
set_property PACKAGE_PIN K22 [get_ports hdmi_d0_n]
set_property PACKAGE_PIN J20 [get_ports hdmi_d1_p]
set_property PACKAGE_PIN J21 [get_ports hdmi_d1_n]
set_property PACKAGE_PIN G17 [get_ports hdmi_d2_p]
set_property PACKAGE_PIN G18 [get_ports hdmi_d2_n]
set_property PACKAGE_PIN L19 [get_ports hdmi_clk_p]
set_property PACKAGE_PIN L20 [get_ports hdmi_clk_n]
set_property IOSTANDARD TMDS_33 [get_ports {hdmi_d0_p hdmi_d0_n hdmi_d1_p hdmi_d1_n hdmi_d2_p hdmi_d2_n hdmi_clk_p hdmi_clk_n}]

## HDMI auxiliary control
set_property PACKAGE_PIN H15 [get_ports hdmi_hpdn]
set_property IOSTANDARD LVCMOS33 [get_ports hdmi_hpdn]
set_property PULLUP true [get_ports hdmi_hpdn]

## DDR3 SDRAM (U4, MT41K256M16XX-107) pin/electrical constraints now come from
## mig_7series_1's own scoped XDC (regenerated with Fixed Pin Out planning
## matching the real A7-LITE pinout + the correct 1.35V memory part, all in
## bank 35). See /memories/repo/ov7670_hdmi_ddr3.md for how it was rebuilt.

## Internal Vref for the single DDR3 SSTL135 bank (0.675V = Vddq/2).
set_property INTERNAL_VREF 0.675 [get_iobanks 35]

## Override MIG's stale CLOCK_DEDICATED_ROUTE=BACKBONE on sys_clk_i (left over
## from mig_a.prj's unused fictitious clock pin): here sys_clk_i is fed
## internally from clk_wiz_hdmi's MMCM, not a dedicated external pin, so no
## backbone route is used and the DRC (RTRES-1) blocks bitgen without this.
set_property CLOCK_DEDICATED_ROUTE FALSE [get_nets -hierarchical -filter {NAME =~ "*sys_clk_i"}]

## Generated clocks for timing analysis.
## Use MMCM CLKIN1 as the master source to avoid pessimistic source inference.
create_generated_clock -name clk_pixel -source [get_pins u_clk_hdmi/mmcm_inst/CLKIN1] \
    -multiply_by 63 -divide_by 125 [get_pins u_clk_hdmi/u_clkpx/O]
create_generated_clock -name clk_5x    -source [get_pins u_clk_hdmi/mmcm_inst/CLKIN1] \
    -multiply_by 63 -divide_by 25 [get_pins u_clk_hdmi/u_clk5x/O]

## Camera PCLK is asynchronous to board/system and MMCM-generated clocks.
set_clock_groups -asynchronous \
    -group [get_clocks {sys_clk_pin clk_pixel clk_5x}] \
    -group [get_clocks cam_pclk]

## CDC: ddr3_fb_bridge synchronizers (pclk/clk_pixel <-> ui_clk). These are
## the toggle/Gray-pointer first-stage synchronizer flops feeding the bridge's
## row-swap crossing and the write-side async FIFO; they are deliberately
## outside any single-clock timing relationship (see ddr3_fb_bridge/async_fifo
## in OV7670_top.v), so ordinary setup/hold analysis on them is meaningless.
set_false_path -to [get_pins -hierarchical -filter {NAME =~ "*u_fb_bridge/sync1_reg/D"}]
set_false_path -to [get_pins -hierarchical -filter {NAME =~ "*u_fb_bridge/completed_bank_sync1_reg/D"}]
set_false_path -to [get_pins -hierarchical -filter {NAME =~ "*u_fb_bridge/row_ready_sync1_reg/D"}]
set_false_path -to [get_pins -hierarchical -filter {NAME =~ "*u_fb_bridge/u_wfifo/wr_ptr_gray_s1_reg*/D"}]
set_false_path -to [get_pins -hierarchical -filter {NAME =~ "*u_fb_bridge/u_wfifo/rd_ptr_gray_s1_reg*/D"}]

## CDC: MIG init_calib_complete (ui_clk) -> clk_pixel, synchronized for the
## debug LED only; same async-crossing rationale as above.
set_false_path -to [get_pins -hierarchical -filter {NAME =~ "*calib_done_sync1_reg/D"}]
