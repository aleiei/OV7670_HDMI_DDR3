# OV7670 HDMI DDR3 – Artix-7 Video Capture Platform

## Overview

This project was born from two concurrent needs:

1. **Practical hardware validation:** Comprehensively test the **MicroPhase A7-Lite** development board (XC7A35T FPGA) using real hardware interfaces
2. **Documentation gap:** The official A7-Lite documentation lacks detailed pin mapping, constraints, and proper I/O configuration. This project fills that gap by **reverse-engineering the board schematic** to derive accurate FPGA pin assignments and electrical constraints.

The design integrates:

- **OV7670 camera module**: parallel 8-bit + HSYNC/VSYNC capture, I2C SCCB configuration
- **MIG 7-Series DDR3 controller**: framebuffer bridge (MT41K256M16XX-107, 1 Gb module)
- **HDMI output**: TMDS encoder, 640×480 @ 60 Hz display

The system demonstrates advanced FPGA concepts: **multi-clock synchronization (CDC)**, **async FIFOs with Gray-code pointers**, **soft IP integration**, and **deterministic hardware reset sequencing** for production-grade reliability.

### Key Features

✓ Parallel camera capture with configurable I2C register tuning  
✓ DDR3 framebuffer for full-resolution (640×480×16bpp) storage  
✓ HDMI output with test pattern + live camera fallback  
✓ Hardware soft-reset FSM: robust warm-boot camera initialization  
✓ Clock domain crossing (pclk, sys_clk, clk_pixel, ui_clk) with CDC synchronizers  
✓ Async write-side FIFO and dual ping-pong line buffers  
✓ I2C retry logic and camera-ready status indication (debug LEDs)

---

## Hardware Setup

### Target Platform

| Component | Specification |
|-----------|---------------|
| FPGA | Xilinx Artix-7 XC7A35TFGG484-1 (225 KB BRAM) |
| Board | MicroPhase A7-Lite development board |
| Memory | MT41K256M16XX-107 DDR3 SDRAM (1 Gb, 16-bit) |
| Oscillator | 50 MHz system clock (on-board) |
| Build Tool | Vivado 2024.1 (lin64) |

### Connections and Pin Mapping

**Note on pin derivation:** All pin assignments have been **reverse-engineered from the MicroPhase A7-Lite board schematic** due to incomplete official documentation. Each signal has been traced from the connector headers and on-board components to the Artix-7 die.

#### System Interface

| Signal | FPGA Pin | Type | Notes |
|--------|----------|------|-------|
| System clock (50 MHz) | J19 | LVCMOS33 In | On-board oscillator |
| Reset (active low) | L18 | LVCMOS33 In | On-board push button K3 |

#### OV7670 Camera – JP1 GPIO Header

| OV7670 Signal | FPGA Pin | JP1 Label | I/O | Notes |
|---------------|----------|-----------|-----|-------|
| SIOD (I2C data) | A18 | GPIO1_11P | Bidir | 4.7 kΩ pull-up to 3.3V (on-board) |
| SIOC (I2C clock) | F14 | GPIO1_0N | Out | 4.7 kΩ pull-up to 3.3V (on-board) |
| HREF | E13 | GPIO1_1P | In | Horizontal sync reference |
| VSYNC | E14 | GPIO1_1N | In | Vertical sync |
| XCLK | D14 | GPIO1_2P | Out | 25.2 MHz generated clock |
| PCLK | D15 | GPIO1_2N | In | Pixel clock (inbound data strobe) |
| D0 | E16 | GPIO1_3P | In | Data bit 0 |
| D1 | D16 | GPIO1_3N | In | Data bit 1 |
| D2 | D17 | GPIO1_4P | In | Data bit 2 |
| D3 | C17 | GPIO1_4N | In | Data bit 3 |
| D4 | C13 | GPIO1_5P | In | Data bit 4 |
| D5 | B13 | GPIO1_5N | In | Data bit 5 |
| D6 | A13 | GPIO1_6P | In | Data bit 6 |
| D7 | A14 | GPIO1_6N | In | Data bit 7 |
| PWDN (power down) | C14 | GPIO1_7P | Out | Active high (set 1 to shut down) |
| RESET (hard reset) | C15 | GPIO1_7N | Out | Active low; firmware-controlled FSM |
| 3V3 | – | JP1 VCC | Power | +3.3 V |
| GND | – | JP1 GND | Power | Ground |

**Wiring checklist:**
- SIOD and SIOC pull-up resistors (4.7 kΩ to 3.3V) are already installed on the A7-Lite board (R104, R105)
- Ensure short, twisted-pair cables for PCLK and data lines (>50 MHz signal integrity)
- Camera power supply must be separate, well-decoupled 3V3 source

#### HDMI Output – Onboard Connector

| Signal | FPGA Pin+ | FPGA Pin− | IOSTANDARD | Channel |
|--------|-----------|-----------|------------|---------|
| HDMI_CLK | L19 | L20 | TMDS_33 | Clock |
| HDMI_D0 (Blue + sync) | K21 | K22 | TMDS_33 | Data lane 0 |
| HDMI_D1 (Green) | J20 | J21 | TMDS_33 | Data lane 1 |
| HDMI_D2 (Red) | G17 | G18 | TMDS_33 | Data lane 2 |
| HDMI_HPD | H15 | – | LVCMOS33 | Hot plug detect (input) |

**Output Format:** 640×480 @ 60 Hz, 24-bit RGB (8-bit per channel)

#### Debug LEDs

| LED | FPGA Pin | Signal | Meaning |
|-----|----------|--------|---------|
| LED1 (green) | M18 | `led_pin[0]` | ON = I2C camera config complete |
| LED2 (red) | N18 | `led_pin[1]` | Test mode: HDMI HPD status; Camera mode: HIGH after 1st pixel write |
| LED3 | A15 | `led_pin[2]` | Available for debug |
| LED4 | A16 | `led_pin[3]` | Available for debug |

**Diagnostic:**
- If LED1 is ON but LED2 stays OFF, the camera is configured but no pixels are reaching the capture logic. The HDMI output will display an internal test pattern instead of camera data.

---

## Architecture

### Clock Domains

The design uses four independent clock domains with careful CDC (clock domain crossing) to avoid metastability:

| Clock | Frequency | Source | Domain |
|-------|-----------|--------|--------|
| `sys_clk` | 50 MHz | Board oscillator → FPGA pin J19 | System (DDR3, camera init FSM) |
| `clk_pixel` | 25.2 MHz | PLL/MMCM (63÷125 multiplier/divider) | HDMI pixel stream |
| `clk_5x` | 126 MHz | PLL/MMCM (63÷25 multiplier/divider) | TMDS serializer |
| `pclk` | ~25 MHz (async) | OV7670 camera module | Camera capture data |

**CDC Synchronizers:**
- Camera-to-DDR3 sync: Gray-code pointers in async write FIFO + toggle-detect cross registers
- DDR3-to-HDMI sync: DDR3 bank-switch signaling synced via 2-stage flop chains
- All CDC signals marked with `set_false_path` in XDC constraints (timing analysis aware of clock domain independence)

### Framebuffer Pipeline

```
OV7670 (pclk domain)
  ↓
[HSYNC/VSYNC parser]
  ↓
[Async Write FIFO, pclk side]
  ↓
CDC [Gray-code pointer sync]
  ↓
[Line buffer BRAM, ui_clk domain]
  ↓
[DDR3 MIG Native Port, ui_clk @ 100 MHz]
  ↓
[Dual ping-pong row buffer]
  ↓
CDC [Row-ready sync]
  ↓
[Row reader, clk_pixel domain]
  ↓
[HDMI TMDS encoder]
  ↓
[Serializer (4 pixels @ clk_5x)]
  ↓
HDMI output
```

**Design rationale:**
- Small on-chip BRAM (225 KB) insufficient for 640×480×16b (768 KB); DDR3 provides persistent storage
- Async FIFO decouples camera (pclk, free-running) from DDR3 (bursty access, must not stall camera)
- Dual ping-pong buffers allow DDR3 to read one row while camera fills the next
- TMDS encoder + serializer handle the 5× clock upsampling for HDMI output

### Camera Soft-Reset FSM (Warm-Boot Reliability)

**Problem:** Bitstream reload via JTAG leaves PWDN/RESET pins floating during FPGA configuration, allowing 5V HDMI back-powering through I/O protection diodes. This causes intermittent OV7670 initialization failures.

**Solution:** Dedicated sys_clk-domain FSM that forces a deterministic power sequence **before** enabling I2C:

```
State: CAM_RST_HOLD (30 ms)
  PWDN ← 1 (power down)
  RESET ← 0 (hold reset)
  Cycle count: 1,500,000 @ 50 MHz

State: CAM_PWRUP_WAIT (10 ms)
  PWDN ← 0 (power up)
  RESET ← 0 (hold reset)
  Cycle count: 500,000 @ 50 MHz

State: CAM_POSTRST_WAIT (20 ms)
  PWDN ← 0 (power up)
  RESET ← 1 (release reset)
  Cycle count: 1,000,000 @ 50 MHz

State: CAM_READY
  cam_init_en ← 1 (allow I2C initialization to proceed)
```

The `ov7670_init` LUT is gated by `cam_init_en`; no I2C transactions occur until the FSM reaches CAM_READY.

**Result:** Camera initializes reliably on every bitstream reload, even with HDMI connected.

---

## Camera I2C Configuration

### Overview

The OV7670 is configured via I2C (called SCCB on the camera datasheet). The `ov7670_init.v` module strobes through a lookup table (LUT) of register writes at 10 kHz I2C clock rate.

**Base register set:**
- 168 tuples in `I2C_OV7670_RGB565_Config.v` (fixed configuration, no overrides)
- Initializes color matrix, gain, exposure, format (RGB565), output size (640×480), etc.

### Enabling Manual Overrides

To modify image behavior (orientation, brightness, contrast, color matrix, etc.), the LUT can be extended with 20 additional configuration slots. These are disabled by default.

**Step 1:** In `ov7670_init.v`, change:
```verilog
parameter LUT_SIZE = 168;
```
to:
```verilog
parameter LUT_SIZE = 188;
```

**Step 2:** Edit `I2C_OV7670_RGB565_Config2.v` (optional extension slots). Each slot contains a 16-bit I2C write: `{reg_addr[7:0], reg_data[7:0]}`.

**Step 3:** Rebuild and program the bitstream.

**Disabling overrides:** Restore `LUT_SIZE = 168`.

### Image Tuning Guide

#### Orientation

Use slot index `SET_OV7670 + 166` (register `0x1E`, MVFP):

| Transformation | Register Write | Bits |
|---|---|---|
| Normal | `16'h1e01` | Bit 0 = must stay 1 |
| Horizontal mirror | `16'h1e21` | Flip H = bit 5 |
| Vertical flip | `16'h1e11` | Flip V = bit 4 |
| Mirror + flip | `16'h1e31` | Both bits set |

**Important:** Bit 0 must remain set (part of working MVFP baseline).

#### Brightness and Contrast

**Brightness** — slot `SET_OV7670 + 167` (register `0x55`, BRIGHT):

| Effect | Register Write |
|---|---|
| Stronger darken | `16'h55a0` |
| Slight darken | `16'h5590` |
| Neutral | `16'h5500` |
| Slight brighten | `16'h5510` |
| Stronger brighten | `16'h5520` |

**Contrast** — slot `SET_OV7670 + 168` (register `0x56`, CONTRAS):
- Start: `16'h5640`
- Less contrast: `16'h5630`
- More contrast: `16'h5650`

**Tip:** Change one step at a time; module-to-module variation is common.

#### Exposure, Gain, and White Balance

**Automatic vs. Manual** — slot `SET_OV7670 + 169` (register `0x13`, COM8):

| Mode | Register Write | Meaning |
|---|---|---|
| Automatic (all) | `16'h13ff` | AGC, AWB, AEC enabled |
| Manual white balance only | `16'h13fd` | Manual WB + Auto gain/exposure |
| Manual gain only | `16'h13fb` | Manual gain + Auto WB/exposure |
| Manual exposure only | `16'h13fe` | Manual exposure + Auto gain/WB |
| Manual (all) | `16'h13f8` | AGC, AWB, AEC disabled |

**Critical:** Do not enable manual control while its corresponding automatic control is active; the DSP will continuously override your values.

##### Manual Gain

1. Disable AGC in slot `+169` (set `16'h13fb` or `16'h13f8`)
2. Enable slot `+170` (register `0x00`, GAIN)
3. Start with `16'h0040` and adjust in small increments
   - Lower values = less gain, less noise
   - Higher values = more gain, more brightness

##### Manual Exposure

1. Disable AEC in slot `+169` (set `16'h13fe` or `16'h13f8`)
2. Enable all three slots `+171` through `+173`

The OV7670 assembles exposure time from three registers:
```
Exposure = {AECHH[5:0], AECH[7:0], COM1[1:0]}
           (16-bit total, range 0–65535 × 50 µs ≈ 0–3.3 s)
```

Starter writes:
```verilog
16'h0400  // COM1, exposure bits 1:0
16'h1040  // AECH, exposure bits 9:2
16'h0700  // AECHH, exposure bits 15:10
```

**Adjustment strategy:**
- Increase `AECH` (slot +172) for longer/brighter exposure
- Decrease `AECH` for shorter/darker exposure
- Very long exposures may reduce frame rate

##### Manual White Balance

1. Disable AWB in slot `+169` (set `16'h13fd` or `16'h13f8`)
2. Enable slots `+174` through `+176`

Starter writes:
```verilog
16'h0140  // Blue gain
16'h0240  // Red gain
16'h6a40  // Green gain
```

**Tuning:**
- Increase blue gain if image is too yellow
- Increase red gain if image is too cyan
- Change in steps of `0x04` per test

#### Color Matrix and Saturation

Slots `+177` through `+183` control the 3×3 color transformation matrix (7 registers total). Enable all seven together:

```verilog
16'h4f80  // MTX1 (row 0, col 0)
16'h5080  // MTX2 (row 0, col 1)
16'h5100  // MTX3 (row 0, col 2)
16'h5222  // MTX4 (row 1, col 0)
16'h535e  // MTX5 (row 1, col 1)
16'h5480  // MTX6 (row 1, col 2)
16'h589e  // MTXS (row 2, sign bits)
```

**Workflow:**
- Keep `MTXS = 0x9E` while tuning saturation
- Change coefficient magnitudes by `0x04` or `0x08` per iteration
- **Record each complete matrix** and its visual result
- Coefficients interact; changing one may introduce color cast

The matrix values shown restore the current (neutral) color response.

#### Edge Enhancement

Enable slots `+184` and `+185` together:

```verilog
16'h4138  // COM16: edge enhancement enabled
16'h3f00  // EDGE strength
```

**Adjustment:**
- Low byte of `0x3F` controls strength
- Try increments of `0x08`, `0x10`, `0x20`
- Excessive values create bright outlines and amplify noise

### Recommended Tuning Order

1. **Select orientation** (slot +166)
2. **Leave automatic gain, exposure, white balance enabled** (default COM8 setting)
3. **Tune brightness and contrast** (+167, +168)
4. **Tune edge enhancement** (slots +184/185) only if image needs sharper details
5. **Adjust color matrix** (slots +177–183) only after previous controls are satisfactory
6. **Switch to manual modes** (slots +170–176) only for fixed-lighting scenarios

**Best practice:** Change one control group per build, record the value and visual result, and validate on your target lighting condition before moving to the next group.

---

## Building and Programming

### Prerequisites

- **Vivado 2024.1** (lin64) installed and sourced
- **Artix-7 A7-Lite board** connected via USB (JTAG)
- **QSPI flash** (IS25LP128F) on board for bitstream storage

### Build Flow

```bash
# Open project in Vivado GUI
vivado OV7670_HDMI_DDR3.xpr &

# Or batch build (in Vivado Tcl console or script):
open_project OV7670_HDMI_DDR3.xpr
reset_run synth_1
launch_runs synth_1 -jobs 4
wait_on_run synth_1
launch_runs impl_1 -to_step write_bitstream -jobs 4
wait_on_run impl_1
```

### Programming via JTAG

In Vivado Hardware Manager:
1. Auto-connect to the FPGA (or specify by cable/device number)
2. Program bitstream: `OV7670_HDMI_DDR3.runs/impl_1/OV7670_top.bit`
3. Reset the board (push button K3 or unplug/replug USB)

### Programming via QSPI Flash (Boot)

For standalone operation (no Vivado), write the bitstream to QSPI flash (IS25LP128F, 128 Mb capacity):

```bash
# Generate .bin from .bit (in Vivado)
write_cfgmem -format bin -disablebitswap -size 16 -interface spix4 \
  -loadbit "up 0 OV7670_top.bit" OV7670_top.bin

# Program flash via JTAG + Vivado:
# 1. Add QSPI SPI flash (IS25LP128F) to Hardware dialog
# 2. Add configuration bitstream file
# 3. Select "Verify" if desired
# 4. Program device
```

---

## Known Issues and Workarounds

### DRC Warnings (Non-Critical)

**PLCK-12:** Poor IBUF-to-BUFG placement on `pclk` (camera pixel clock)
- Cause: `pclk` is routed to a non clock-capable (CC) I/O pin on this board
- Impact: None observed at runtime; `CLOCK_DEDICATED_ROUTE` override set to `FALSE` to allow implementation
- Recommendation: Would require reassigning the camera clock to a CC-capable pin at the board level to fully eliminate

**REQP-1709:** PLLE2_ADV buffer type mismatch (MIG IP core)
- Cause: MIG's internal buffering configuration
- Impact: None observed at runtime
- Recommendation: Monitor in future builds; typical on certified IP

### Warm-Start Failures (Resolved)

**Symptom:** OV7670 initialization fails after bitstream reload (JTAG), but succeeds after full power cycle.

**Root cause:** HDMI connector supplies 5V back-power through FPGA I/O protection diodes during FPGA configuration, biasing undriven PWDN/RESET pins.

**Solution:** Implemented camera soft-reset FSM (see Architecture section). Verified over 5+ consecutive rapid boot cycles.

### HDMI Signal Integrity

- Keep TMDS differential pairs short (<10 cm) and well-matched length
- Use 100 Ω terminated twisted-pair cables or PCB traces
- If experiencing video artifacts or HDCP errors, verify connector pin contact

---

## Troubleshooting

### LEDs

| Symptom | Probable Cause | Action |
|---------|---|---|
| All LEDs dark | FPGA not programmed / bitstream failed | Check JTAG connection, re-program |
| LED1 OFF, LED2 OFF | Camera I2C not responding | Verify SIOC/SIOD cables; check pull-ups; ensure 3.3V power to camera |
| LED1 ON, LED2 OFF | Camera config complete, no pixels | Check PCLK/HSYNC/VSYNC/data cables; verify lens focus; check camera orientation |
| LED1 ON, LED2 ON | Camera operational, pixels flowing | Normal operation; if no video on HDMI, check monitor HPD and TMDS cables |

### No HDMI Video

1. **Monitor not detecting signal:**
   - Verify TMDS cables (L19, L20, K21, K22, J20, J21, G17, G18)
   - Check HDMI_HPD pull-up on H15 (should be pulled up to 3.3V)
   - Try a different HDMI cable and monitor

2. **Test pattern visible but camera not:**
   - LED1 should be ON (camera config)
   - LED2 should be ON (pixels flowing)
   - If only test pattern: check DDR3 MIG calibration (see runme.log) and async FIFO gray-code logic

3. **Periodic freezes or color glitches:**
   - May indicate DDR3 timing closure issues or CDC synchronizer metastability
   - Check Vivado timing report (WNS ≥ 0)
   - Review CDC false-path constraints in XDC

### I2C Communication Failures

- Verify both SIOC (F14) and SIOD (A18) are connected and not shorted
- SIOC must have external 4.7 kΩ pull-up to 3.3V (on harness)
- SIOD has internal FPGA pull-up (no external resistor needed, but does not hurt)
- I2C clock frequency: 10 kHz (should be robust; timing not critical)

---

## File Structure

```
OV7670_HDMI_DDR3/
├── OV7670_HDMI_DDR3.xpr                    # Vivado project file
├── README.md                                # This file
├── LICENSE                                  # Project license
│
├── OV7670_HDMI_DDR3.srcs/
│   ├── sources_1/
│   │   ├── new/
│   │   │   ├── OV7670_top.v                 # Top-level: camera, DDR3, HDMI
│   │   │   ├── ov7670_init.v                # I2C LUT strobing
│   │   │   ├── I2C_OV7670_RGB565_Config.v   # Base config registers
│   │   │   ├── I2C_OV7670_RGB565_Config2.v  # Optional overrides (ext. slots)
│   │   │   ├── I2C_Controller2.v            # I2C master (bit-level sequencer)
│   │   │   ├── vga_timings.v                # VGA/QVGA timing generator
│   │   │   └── tmds_encoder.v               # HDMI TMDS 8b/10b encoder
│   │   └── ip/
│   │       ├── mig_7series_1/               # MIG DDR3 controller (generated)
│   │       └── clk_wiz_hdmi/                # Clock wizard (generated)
│   │
│   └── constrs_1/
│       ├── imports/ConstrainFiles/
│       │   └── ov7670_hdmi_ddr3_pins.xdc    # Pin and timing constraints
│       └── ...
│
├── OV7670_HDMI_DDR3.runs/
│   ├── synth_1/                             # Synthesis output
│   └── impl_1/                              # Implementation output (bit, bin, mcs)
│
├── doc/
│   └── ...                                  # Reference materials (if any)
│
└── patches/
    ├── 2026-08-17_clock_drc_cleanup.diff    # Constraint and RTL patches
    ├── 2026-08-17_clock_drc_cleanup.rollback.sh
    └── *.pre_patch                          # Pre-patch snapshots (rollback)
```

---

## References

- **OV7670 Datasheet:** https://datasheetspdf.com/pdf/file/779621/OmniVision/OV7670.html
- **Xilinx Artix-7 FPGA:** https://www.xilinx.com/support/documentation.html
- **MicroPhase A7-Lite Documentation:** https://github.com/MicroPhase/A7-LITE
- **TMDS/HDMI Encoding:** CEA-861-D standard
- **CDC Design Patterns:** *Synchronization Techniques for Multiclocking* (Xilinx Whitepaper XAPP552)

---

## License

See LICENSE file in this repository.

---

## Notes for Future Development

1. **Simulation Testbench:** Async FIFO and gray-code pointer math benefit from simulation verification before hardware testing. Consider adding a standalone Vivado simulation project targeting the async_fifo module.

2. **Optional Hardware Reset Bias:** For production designs, add explicit pull-down on PWDN and pull-up on RESET to ensure safe idle state even if FPGA is unpowered.

3. **MIG Regeneration:** If DDR3 capacity or bus width changes, regenerate MIG core via Vivado IP Catalog. Export new XDC with correct pin/electrical settings and import into project.

4. **Higher-Resolution Output:** The current design targets 640×480. For 1280×1024 or higher, either:
   - Increase DDR3 module size (MB85 or larger)
   - Implement ring buffer with read-ahead and higher I/O clock (e.g., 200 MHz DDR mode)
   - Reduce color depth (RGB444 or grayscale)

5. **Warm-Boot Reliability Testing:** Periodically verify camera init success over 10+ JTAG reloads and/or repeated power cycles to catch intermittent failures early.
