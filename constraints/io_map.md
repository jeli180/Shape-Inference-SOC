# ULX3S IO map and top-level port guide

This project uses `constraints/ulx3s_v20.lpf`, an LPF constraint file for the ULX3S v2/v3 board. The LPF does not create HDL signals by itself. It only tells the place-and-route tool where your top-level HDL ports live on the FPGA package and what electrical settings to use.

The important pattern is:

```text
LOCATE COMP "led[0]" SITE "B2";
IOBUF  PORT "led[0]" PULLMODE=NONE IO_TYPE=LVCMOS33 DRIVE=4;
```

That means your synthesized top module must have a port named `led[0]`, usually as part of `output logic [7:0] led`. The tool connects `led[0]` to FPGA package site `B2`, with 3.3 V LVCMOS IO and 4 mA drive.

## Common top-level ports

Use the same names as the LPF in your top module:

```systemverilog
module top (
  input  logic       clk_25mhz,
  input  logic [6:0] btn,
  input  logic [3:0] sw,
  output logic [7:0] led
);
  logic rst;

  // btn[0] is BTN_PWRn and is active-low/inverted logic.
  // The other buttons use pulldowns and read high when pressed.
  assign rst = ~btn[0];

  always_ff @(posedge clk_25mhz or posedge rst) begin
    if (rst) begin
      led <= 8'h00;
    end else begin
      led[3:0] <= sw;
      led[6:4] <= btn[3:1];
      led[7]   <= btn[6];
    end
  end
endmodule
```

If you want to use the GPIO header as vectors, declare them as vectors:

```systemverilog
inout wire [27:0] gp,
inout wire [27:0] gn
```

If you want individual GPIO names instead, declare ports like `gp0`, `gn0`, etc. Do not use both styles for the same physical pins. The LPF intentionally lists both `gp[0]` and `gp0` as aliases for the same site.

## Direction guide

The LPF names and electrical settings do not tell SystemVerilog whether a port is an input or output; your top-level declaration does that.

| Board signal | Suggested HDL direction | Notes |
| --- | --- | --- |
| `clk_25mhz` | `input logic` | 25 MHz board clock. |
| `led[7:0]` | `output logic [7:0]` | User LEDs, generally active-high. |
| `btn[6:0]` | `input logic [6:0]` | `btn[0]` is active-low/inverted; others read high when pressed. |
| `sw[3:0]` | `input logic [3:0]` | DIP switches, pulldown. |
| `ftdi_rxd` | `output logic` | FPGA transmits to USB serial adapter. |
| `ftdi_txd` | `input logic` | FPGA receives from USB serial adapter. |
| `gp`/`gn` | `input`, `output`, or `inout` | Depends on what you plug into the header. |
| `sdram_d[15:0]` | `inout wire [15:0]` | SDRAM data bus is bidirectional. |
| `sdram_*` control/address | mostly `output logic` | Driven by an SDRAM controller. |
| Peripheral SPI signals | depends | `*_miso` is usually input, `*_mosi`/`*_clk`/`*_csn` usually outputs. |

## Complete active LPF port map

This table is generated from the active `LOCATE COMP` lines in `ulx3s_v20.lpf`. Commented-out dedicated/JTAG/configuration pins are not included.

| Top-level port | FPGA site | Electrical settings | Notes |
| --- | --- | --- | --- |
| `clk_25mhz` | `G2` | `PULLMODE=NONE IO_TYPE=LVCMOS33` |  |
| `ftdi_rxd` | `L4` | `PULLMODE=UP IO_TYPE=LVCMOS33 DRIVE=4` | FPGA transmits to ftdi |
| `ftdi_txd` | `M1` | `PULLMODE=UP IO_TYPE=LVCMOS33` | FPGA receives from ftdi |
| `ftdi_nrts` | `M3` | `PULLMODE=UP IO_TYPE=LVCMOS33` | FPGA receives |
| `ftdi_ndtr` | `N1` | `PULLMODE=UP IO_TYPE=LVCMOS33` | FPGA receives |
| `ftdi_txden` | `L3` | `PULLMODE=UP IO_TYPE=LVCMOS33` | FPGA receives |
| `led[7]` | `H3` | `PULLMODE=NONE IO_TYPE=LVCMOS33 DRIVE=4` |  |
| `led[6]` | `E1` | `PULLMODE=NONE IO_TYPE=LVCMOS33 DRIVE=4` |  |
| `led[5]` | `E2` | `PULLMODE=NONE IO_TYPE=LVCMOS33 DRIVE=4` |  |
| `led[4]` | `D1` | `PULLMODE=NONE IO_TYPE=LVCMOS33 DRIVE=4` |  |
| `led[3]` | `D2` | `PULLMODE=NONE IO_TYPE=LVCMOS33 DRIVE=4` |  |
| `led[2]` | `C1` | `PULLMODE=NONE IO_TYPE=LVCMOS33 DRIVE=4` |  |
| `led[1]` | `C2` | `PULLMODE=NONE IO_TYPE=LVCMOS33 DRIVE=4` |  |
| `led[0]` | `B2` | `PULLMODE=NONE IO_TYPE=LVCMOS33 DRIVE=4` |  |
| `btn[0]` | `D6` | `PULLMODE=UP IO_TYPE=LVCMOS33 DRIVE=4` | BTN_PWRn (inverted logic) |
| `btn[1]` | `R1` | `PULLMODE=DOWN IO_TYPE=LVCMOS33 DRIVE=4` | FIRE1 |
| `btn[2]` | `T1` | `PULLMODE=DOWN IO_TYPE=LVCMOS33 DRIVE=4` | FIRE2 |
| `btn[3]` | `R18` | `PULLMODE=DOWN IO_TYPE=LVCMOS33 DRIVE=4` | UP W1->R18 |
| `btn[4]` | `V1` | `PULLMODE=DOWN IO_TYPE=LVCMOS33 DRIVE=4` | DOWN |
| `btn[5]` | `U1` | `PULLMODE=DOWN IO_TYPE=LVCMOS33 DRIVE=4` | LEFT |
| `btn[6]` | `H16` | `PULLMODE=DOWN IO_TYPE=LVCMOS33 DRIVE=4` | RIGHT Y2->H16 |
| `sw[0]` | `E8` | `PULLMODE=DOWN IO_TYPE=LVCMOS33 DRIVE=4` | SW1 |
| `sw[1]` | `D8` | `PULLMODE=DOWN IO_TYPE=LVCMOS33 DRIVE=4` | SW2 |
| `sw[2]` | `D7` | `PULLMODE=DOWN IO_TYPE=LVCMOS33 DRIVE=4` | SW3 |
| `sw[3]` | `E7` | `PULLMODE=DOWN IO_TYPE=LVCMOS33 DRIVE=4` | SW4 |
| `oled_clk` | `P4` | `PULLMODE=UP IO_TYPE=LVCMOS33 DRIVE=4` |  |
| `oled_mosi` | `P3` | `PULLMODE=UP IO_TYPE=LVCMOS33 DRIVE=4` |  |
| `oled_dc` | `P1` | `PULLMODE=UP IO_TYPE=LVCMOS33 DRIVE=4` |  |
| `oled_resn` | `P2` | `PULLMODE=UP IO_TYPE=LVCMOS33 DRIVE=4` |  |
| `oled_csn` | `N2` | `PULLMODE=UP IO_TYPE=LVCMOS33 DRIVE=4` |  |
| `flash_csn` | `R2` | `PULLMODE=UP IO_TYPE=LVCMOS33 DRIVE=4` |  |
| `flash_clk` | `U3` | `PULLMODE=DOWN IO_TYPE=LVCMOS33 DRIVE=4` |  |
| `flash_mosi` | `W2` | `PULLMODE=UP IO_TYPE=LVCMOS33 DRIVE=4` |  |
| `flash_miso` | `V2` | `PULLMODE=UP IO_TYPE=LVCMOS33 DRIVE=4` |  |
| `flash_holdn` | `W1` | `PULLMODE=UP IO_TYPE=LVCMOS33 DRIVE=4` |  |
| `flash_wpn` | `Y2` | `PULLMODE=UP IO_TYPE=LVCMOS33 DRIVE=4` |  |
| `sd_clk` | `H2` | `PULLMODE=UP IO_TYPE=LVCMOS33 DRIVE=4` | sd_clk WiFi_GPIO14 |
| `sd_cmd` | `J1` | `PULLMODE=UP IO_TYPE=LVCMOS33 DRIVE=4` | sd_cmd_di (MOSI) WiFi GPIO15 |
| `sd_d[0]` | `J3` | `PULLMODE=UP IO_TYPE=LVCMOS33 DRIVE=4` | sd_d0_do (MISO) WiFi GPIO2 |
| `sd_d[1]` | `H1` | `PULLMODE=UP IO_TYPE=LVCMOS33 DRIVE=4` | sd_d1_irq WiFi GPIO4 |
| `sd_d[2]` | `K1` | `PULLMODE=NONE IO_TYPE=LVCMOS33 DRIVE=4` | sd_d2 WiFi_GPIO12 |
| `sd_d[3]` | `K2` | `PULLMODE=UP IO_TYPE=LVCMOS33 DRIVE=4` | sd_d3_csn WiFi_GPIO13 |
| `sd_wp` | `P5` | `PULLMODE=UP IO_TYPE=LVCMOS33 DRIVE=4` | not connected |
| `sd_cdn` | `N5` | `PULLMODE=UP IO_TYPE=LVCMOS33 DRIVE=4` | not connected |
| `adc_csn` | `R17` | `PULLMODE=UP IO_TYPE=LVCMOS33 DRIVE=4` |  |
| `adc_mosi` | `R16` | `PULLMODE=UP IO_TYPE=LVCMOS33 DRIVE=4` |  |
| `adc_miso` | `U16` | `PULLMODE=UP IO_TYPE=LVCMOS33 DRIVE=4` |  |
| `adc_sclk` | `P17` | `PULLMODE=UP IO_TYPE=LVCMOS33 DRIVE=4` |  |
| `audio_l[3]` | `B3` | `PULLMODE=NONE IO_TYPE=LVCMOS33 DRIVE=16` | JACK TIP (left audio) |
| `audio_l[2]` | `C3` | `PULLMODE=NONE IO_TYPE=LVCMOS33 DRIVE=16` |  |
| `audio_l[1]` | `D3` | `PULLMODE=NONE IO_TYPE=LVCMOS33 DRIVE=16` |  |
| `audio_l[0]` | `E4` | `PULLMODE=NONE IO_TYPE=LVCMOS33 DRIVE=16` |  |
| `audio_r[3]` | `C5` | `PULLMODE=NONE IO_TYPE=LVCMOS33 DRIVE=16` | JACK RING1 (right audio) |
| `audio_r[2]` | `D5` | `PULLMODE=NONE IO_TYPE=LVCMOS33 DRIVE=16` |  |
| `audio_r[1]` | `B5` | `PULLMODE=NONE IO_TYPE=LVCMOS33 DRIVE=16` |  |
| `audio_r[0]` | `A3` | `PULLMODE=NONE IO_TYPE=LVCMOS33 DRIVE=16` |  |
| `audio_v[3]` | `E5` | `PULLMODE=NONE IO_TYPE=LVCMOS33 DRIVE=16` | JACK RING2 (video or digital audio) |
| `audio_v[2]` | `F5` | `PULLMODE=NONE IO_TYPE=LVCMOS33 DRIVE=16` |  |
| `audio_v[1]` | `F2` | `PULLMODE=NONE IO_TYPE=LVCMOS33 DRIVE=16` |  |
| `audio_v[0]` | `H5` | `PULLMODE=NONE IO_TYPE=LVCMOS33 DRIVE=16` |  |
| `wifi_en` | `F1` | `PULLMODE=UP IO_TYPE=LVCMOS33 DRIVE=4` | enable/reset WiFi |
| `wifi_rxd` | `K3` | `PULLMODE=UP IO_TYPE=LVCMOS33 DRIVE=4` | FPGA transmits to WiFi |
| `wifi_txd` | `K4` | `PULLMODE=UP IO_TYPE=LVCMOS33 DRIVE=4` | FPGA receives from WiFi |
| `wifi_gpio0` | `L2` | `PULLMODE=UP IO_TYPE=LVCMOS33 DRIVE=4` |  |
| `wifi_gpio5` | `N4` | `PULLMODE=DOWN IO_TYPE=LVCMOS33 DRIVE=4` | WIFI LED |
| `wifi_gpio16` | `L1` | `PULLMODE=UP IO_TYPE=LVCMOS33 DRIVE=4` | Serial1 RX |
| `wifi_gpio17` | `N3` | `PULLMODE=UP IO_TYPE=LVCMOS33 DRIVE=4` | Serial1 TX |
| `wifi_gpio2` | `J3` | `` | sd_d0_do (MISO) WiFi GPIO2 |
| `wifi_gpio4` | `H1` | `` | sd_d1_irq WiFi GPIO4 |
| `wifi_gpio12` | `K1` | `` | sd_d2 WiFi_GPIO12 |
| `wifi_gpio13` | `K2` | `` | sd_d3_csn WiFi_GPIO13 |
| `wifi_gpio14` | `H2` | `` | sd_clk WiFi_GPIO14 |
| `wifi_gpio15` | `J1` | `` | sd_cmd_di (MOSI) WiFi GPIO15 |
| `ant_433mhz` | `G1` | `PULLMODE=NONE IO_TYPE=LVCMOS33 DRIVE=4` |  |
| `usb_fpga_dp` | `E16` | `PULLMODE=NONE IO_TYPE=LVCMOS33D DRIVE=16` | single ended or differential input only |
| `usb_fpga_dn` | `F16` | `PULLMODE=NONE IO_TYPE=LVCMOS33D DRIVE=16` |  |
| `usb_fpga_bd_dp` | `D15` | `PULLMODE=NONE IO_TYPE=LVCMOS33 DRIVE=4` | single-ended bidirectional |
| `usb_fpga_bd_dn` | `E15` | `PULLMODE=NONE IO_TYPE=LVCMOS33 DRIVE=4` |  |
| `usb_fpga_pu_dp` | `B12` | `PULLMODE=NONE IO_TYPE=LVCMOS33 DRIVE=16` | pull up/down control |
| `usb_fpga_pu_dn` | `C12` | `PULLMODE=NONE IO_TYPE=LVCMOS33 DRIVE=16` |  |
| `sdram_clk` | `F19` | `PULLMODE=NONE IO_TYPE=LVCMOS33 DRIVE=4` |  |
| `sdram_cke` | `F20` | `PULLMODE=NONE IO_TYPE=LVCMOS33 DRIVE=4` |  |
| `sdram_csn` | `P20` | `PULLMODE=NONE IO_TYPE=LVCMOS33 DRIVE=4` |  |
| `sdram_wen` | `T20` | `PULLMODE=NONE IO_TYPE=LVCMOS33 DRIVE=4` |  |
| `sdram_rasn` | `R20` | `PULLMODE=NONE IO_TYPE=LVCMOS33 DRIVE=4` |  |
| `sdram_casn` | `T19` | `PULLMODE=NONE IO_TYPE=LVCMOS33 DRIVE=4` |  |
| `sdram_a[0]` | `M20` | `PULLMODE=NONE IO_TYPE=LVCMOS33 DRIVE=4` |  |
| `sdram_a[1]` | `M19` | `PULLMODE=NONE IO_TYPE=LVCMOS33 DRIVE=4` |  |
| `sdram_a[2]` | `L20` | `PULLMODE=NONE IO_TYPE=LVCMOS33 DRIVE=4` |  |
| `sdram_a[3]` | `L19` | `PULLMODE=NONE IO_TYPE=LVCMOS33 DRIVE=4` |  |
| `sdram_a[4]` | `K20` | `PULLMODE=NONE IO_TYPE=LVCMOS33 DRIVE=4` |  |
| `sdram_a[5]` | `K19` | `PULLMODE=NONE IO_TYPE=LVCMOS33 DRIVE=4` |  |
| `sdram_a[6]` | `K18` | `PULLMODE=NONE IO_TYPE=LVCMOS33 DRIVE=4` |  |
| `sdram_a[7]` | `J20` | `PULLMODE=NONE IO_TYPE=LVCMOS33 DRIVE=4` |  |
| `sdram_a[8]` | `J19` | `PULLMODE=NONE IO_TYPE=LVCMOS33 DRIVE=4` |  |
| `sdram_a[9]` | `H20` | `PULLMODE=NONE IO_TYPE=LVCMOS33 DRIVE=4` |  |
| `sdram_a[10]` | `N19` | `PULLMODE=NONE IO_TYPE=LVCMOS33 DRIVE=4` |  |
| `sdram_a[11]` | `G20` | `PULLMODE=NONE IO_TYPE=LVCMOS33 DRIVE=4` |  |
| `sdram_a[12]` | `G19` | `PULLMODE=NONE IO_TYPE=LVCMOS33 DRIVE=4` |  |
| `sdram_ba[0]` | `P19` | `PULLMODE=NONE IO_TYPE=LVCMOS33 DRIVE=4` |  |
| `sdram_ba[1]` | `N20` | `PULLMODE=NONE IO_TYPE=LVCMOS33 DRIVE=4` |  |
| `sdram_dqm[0]` | `U19` | `PULLMODE=NONE IO_TYPE=LVCMOS33 DRIVE=4` |  |
| `sdram_dqm[1]` | `E20` | `PULLMODE=NONE IO_TYPE=LVCMOS33 DRIVE=4` |  |
| `sdram_d[0]` | `J16` | `PULLMODE=NONE IO_TYPE=LVCMOS33 DRIVE=4` |  |
| `sdram_d[1]` | `L18` | `PULLMODE=NONE IO_TYPE=LVCMOS33 DRIVE=4` |  |
| `sdram_d[2]` | `M18` | `PULLMODE=NONE IO_TYPE=LVCMOS33 DRIVE=4` |  |
| `sdram_d[3]` | `N18` | `PULLMODE=NONE IO_TYPE=LVCMOS33 DRIVE=4` |  |
| `sdram_d[4]` | `P18` | `PULLMODE=NONE IO_TYPE=LVCMOS33 DRIVE=4` |  |
| `sdram_d[5]` | `T18` | `PULLMODE=NONE IO_TYPE=LVCMOS33 DRIVE=4` |  |
| `sdram_d[6]` | `T17` | `PULLMODE=NONE IO_TYPE=LVCMOS33 DRIVE=4` |  |
| `sdram_d[7]` | `U20` | `PULLMODE=NONE IO_TYPE=LVCMOS33 DRIVE=4` |  |
| `sdram_d[8]` | `E19` | `PULLMODE=NONE IO_TYPE=LVCMOS33 DRIVE=4` |  |
| `sdram_d[9]` | `D20` | `PULLMODE=NONE IO_TYPE=LVCMOS33 DRIVE=4` |  |
| `sdram_d[10]` | `D19` | `PULLMODE=NONE IO_TYPE=LVCMOS33 DRIVE=4` |  |
| `sdram_d[11]` | `C20` | `PULLMODE=NONE IO_TYPE=LVCMOS33 DRIVE=4` |  |
| `sdram_d[12]` | `E18` | `PULLMODE=NONE IO_TYPE=LVCMOS33 DRIVE=4` |  |
| `sdram_d[13]` | `F18` | `PULLMODE=NONE IO_TYPE=LVCMOS33 DRIVE=4` |  |
| `sdram_d[14]` | `J18` | `PULLMODE=NONE IO_TYPE=LVCMOS33 DRIVE=4` |  |
| `sdram_d[15]` | `J17` | `PULLMODE=NONE IO_TYPE=LVCMOS33 DRIVE=4` |  |
| `gpdi_dp[0]` | `A16` | `IO_TYPE=LVCMOS33D DRIVE=4` | Blue + |
| `gpdi_dn[0]` | `B16` | `IO_TYPE=LVCMOS33D DRIVE=4` | Blue - |
| `gpdi_dp[1]` | `A14` | `IO_TYPE=LVCMOS33D DRIVE=4` | Green + |
| `gpdi_dn[1]` | `C14` | `IO_TYPE=LVCMOS33D DRIVE=4` | Green - |
| `gpdi_dp[2]` | `A12` | `IO_TYPE=LVCMOS33D DRIVE=4` | Red + |
| `gpdi_dn[2]` | `A13` | `IO_TYPE=LVCMOS33D DRIVE=4` | Red - |
| `gpdi_dp[3]` | `A17` | `IO_TYPE=LVCMOS33D DRIVE=4` | Clock + |
| `gpdi_dn[3]` | `B18` | `IO_TYPE=LVCMOS33D DRIVE=4` | Clock - |
| `gpdi_util` | `A19` | `IO_TYPE=LVCMOS33 DRIVE=4` | add 10k parallel to C |
| `gpdi_hpd` | `B20` | `IO_TYPE=LVCMOS33 DRIVE=4` | add 549ohm parallel to C |
| `gpdi_cec` | `A18` | `PULLMODE=UP IO_TYPE=LVCMOS33 DRIVE=4` |  |
| `gpdi_sda` | `B19` | `PULLMODE=UP IO_TYPE=LVCMOS33 DRIVE=4` | I2C shared with RTC |
| `gpdi_scl` | `E12` | `PULLMODE=UP IO_TYPE=LVCMOS33 DRIVE=4` | I2C shared with RTC C12->E12 |
| `gp[0]` | `B11` | `PULLMODE=UP IO_TYPE=LVCMOS33 DRIVE=4` | PCLK |
| `gn[0]` | `C11` | `PULLMODE=UP IO_TYPE=LVCMOS33 DRIVE=4` | PCLK |
| `gp[1]` | `A10` | `PULLMODE=UP IO_TYPE=LVCMOS33 DRIVE=4` | PCLK |
| `gn[1]` | `A11` | `PULLMODE=UP IO_TYPE=LVCMOS33 DRIVE=4` | PCLK |
| `gp[2]` | `A9` | `PULLMODE=UP IO_TYPE=LVCMOS33 DRIVE=4` | GR_PCLK |
| `gn[2]` | `B10` | `PULLMODE=UP IO_TYPE=LVCMOS33 DRIVE=4` | GR_PCLK |
| `gp[3]` | `B9` | `PULLMODE=UP IO_TYPE=LVCMOS33 DRIVE=4` |  |
| `gn[3]` | `C10` | `PULLMODE=UP IO_TYPE=LVCMOS33 DRIVE=4` |  |
| `gp[4]` | `A7` | `PULLMODE=UP IO_TYPE=LVCMOS33 DRIVE=4` |  |
| `gn[4]` | `A8` | `PULLMODE=UP IO_TYPE=LVCMOS33 DRIVE=4` |  |
| `gp[5]` | `C8` | `PULLMODE=UP IO_TYPE=LVCMOS33 DRIVE=4` |  |
| `gn[5]` | `B8` | `PULLMODE=UP IO_TYPE=LVCMOS33 DRIVE=4` |  |
| `gp[6]` | `C6` | `PULLMODE=UP IO_TYPE=LVCMOS33 DRIVE=4` |  |
| `gn[6]` | `C7` | `PULLMODE=UP IO_TYPE=LVCMOS33 DRIVE=4` |  |
| `gp[7]` | `A6` | `PULLMODE=UP IO_TYPE=LVCMOS33 DRIVE=4` |  |
| `gn[7]` | `B6` | `PULLMODE=UP IO_TYPE=LVCMOS33 DRIVE=4` |  |
| `gp[8]` | `A4` | `PULLMODE=UP IO_TYPE=LVCMOS33 DRIVE=4` | DIFF |
| `gn[8]` | `A5` | `PULLMODE=UP IO_TYPE=LVCMOS33 DRIVE=4` | DIFF |
| `gp[9]` | `A2` | `PULLMODE=UP IO_TYPE=LVCMOS33 DRIVE=4` | DIFF |
| `gn[9]` | `B1` | `PULLMODE=UP IO_TYPE=LVCMOS33 DRIVE=4` | DIFF |
| `gp[10]` | `C4` | `PULLMODE=UP IO_TYPE=LVCMOS33 DRIVE=4` | DIFF |
| `gn[10]` | `B4` | `PULLMODE=UP IO_TYPE=LVCMOS33 DRIVE=4` | DIFF |
| `gp[11]` | `F4` | `PULLMODE=UP IO_TYPE=LVCMOS33 DRIVE=4` | DIFF wifi_gpio26 |
| `gn[11]` | `E3` | `PULLMODE=UP IO_TYPE=LVCMOS33 DRIVE=4` | DIFF wifi_gpio25 |
| `gp[12]` | `G3` | `PULLMODE=UP IO_TYPE=LVCMOS33 DRIVE=4` | DIFF wifi_gpio33 PCLK |
| `gn[12]` | `F3` | `PULLMODE=NONE IO_TYPE=LVCMOS33` | DIFF wifi_gpio32 PCLK |
| `gp[13]` | `H4` | `PULLMODE=UP IO_TYPE=LVCMOS33 DRIVE=4` | DIFF wifi_gpio35 |
| `gn[13]` | `G5` | `PULLMODE=UP IO_TYPE=LVCMOS33 DRIVE=4` | DIFF wifi_gpio34 |
| `gp[14]` | `U18` | `PULLMODE=UP IO_TYPE=LVCMOS33 DRIVE=4` | DIFF ADC AIN1 |
| `gn[14]` | `U17` | `PULLMODE=UP IO_TYPE=LVCMOS33 DRIVE=4` | DIFF ADC AIN0 |
| `gp[15]` | `N17` | `PULLMODE=UP IO_TYPE=LVCMOS33 DRIVE=4` | DIFF ADC AIN3 |
| `gn[15]` | `P16` | `PULLMODE=UP IO_TYPE=LVCMOS33 DRIVE=4` | DIFF ADC AIN2 |
| `gp[16]` | `N16` | `PULLMODE=UP IO_TYPE=LVCMOS33 DRIVE=4` | DIFF ADC AIN5 |
| `gn[16]` | `M17` | `PULLMODE=UP IO_TYPE=LVCMOS33 DRIVE=4` | DIFF ADC AIN4 |
| `gp[17]` | `L16` | `PULLMODE=UP IO_TYPE=LVCMOS33 DRIVE=4` | DIFF ADC AIN7 GR_PCLK |
| `gn[17]` | `L17` | `PULLMODE=UP IO_TYPE=LVCMOS33 DRIVE=4` | DIFF ADC AIN6 |
| `gp[18]` | `H18` | `PULLMODE=UP IO_TYPE=LVCMOS33 DRIVE=4` | DIFF |
| `gn[18]` | `H17` | `PULLMODE=UP IO_TYPE=LVCMOS33 DRIVE=4` | DIFF |
| `gp[19]` | `F17` | `PULLMODE=UP IO_TYPE=LVCMOS33 DRIVE=4` | DIFF |
| `gn[19]` | `G18` | `PULLMODE=UP IO_TYPE=LVCMOS33 DRIVE=4` | DIFF |
| `gp[20]` | `D18` | `PULLMODE=UP IO_TYPE=LVCMOS33 DRIVE=4` | DIFF |
| `gn[20]` | `E17` | `PULLMODE=UP IO_TYPE=LVCMOS33 DRIVE=4` | DIFF |
| `gp[21]` | `C18` | `PULLMODE=UP IO_TYPE=LVCMOS33 DRIVE=4` | DIFF |
| `gn[21]` | `D17` | `PULLMODE=UP IO_TYPE=LVCMOS33 DRIVE=4` | DIFF |
| `gp[22]` | `B15` | `PULLMODE=UP IO_TYPE=LVCMOS33 DRIVE=4` |  |
| `gn[22]` | `C15` | `PULLMODE=UP IO_TYPE=LVCMOS33 DRIVE=4` |  |
| `gp[23]` | `B17` | `PULLMODE=UP IO_TYPE=LVCMOS33 DRIVE=4` |  |
| `gn[23]` | `C17` | `PULLMODE=UP IO_TYPE=LVCMOS33 DRIVE=4` |  |
| `gp[24]` | `C16` | `PULLMODE=UP IO_TYPE=LVCMOS33 DRIVE=4` |  |
| `gn[24]` | `D16` | `PULLMODE=UP IO_TYPE=LVCMOS33 DRIVE=4` |  |
| `gp[25]` | `D14` | `PULLMODE=UP IO_TYPE=LVCMOS33 DRIVE=4` |  |
| `gn[25]` | `E14` | `PULLMODE=UP IO_TYPE=LVCMOS33 DRIVE=4` |  |
| `gp[26]` | `B13` | `PULLMODE=UP IO_TYPE=LVCMOS33 DRIVE=4` |  |
| `gn[26]` | `C13` | `PULLMODE=UP IO_TYPE=LVCMOS33 DRIVE=4` |  |
| `gp[27]` | `D13` | `PULLMODE=UP IO_TYPE=LVCMOS33 DRIVE=4` |  |
| `gn[27]` | `E13` | `PULLMODE=UP IO_TYPE=LVCMOS33 DRIVE=4` |  |
| `gp0` | `B11` | `PULLMODE=UP IO_TYPE=LVCMOS33 DRIVE=4` | PCLK |
| `gn0` | `C11` | `PULLMODE=UP IO_TYPE=LVCMOS33 DRIVE=4` | PCLK |
| `gp1` | `A10` | `PULLMODE=UP IO_TYPE=LVCMOS33 DRIVE=4` | PCLK |
| `gn1` | `A11` | `PULLMODE=UP IO_TYPE=LVCMOS33 DRIVE=4` | PCLK |
| `gp2` | `A9` | `PULLMODE=UP IO_TYPE=LVCMOS33 DRIVE=4` | GR_PCLK |
| `gn2` | `B10` | `PULLMODE=UP IO_TYPE=LVCMOS33 DRIVE=4` | GR_PCLK |
| `gp3` | `B9` | `PULLMODE=UP IO_TYPE=LVCMOS33 DRIVE=4` |  |
| `gn3` | `C10` | `PULLMODE=UP IO_TYPE=LVCMOS33 DRIVE=4` |  |
| `gp4` | `A7` | `PULLMODE=UP IO_TYPE=LVCMOS33 DRIVE=4` |  |
| `gn4` | `A8` | `PULLMODE=UP IO_TYPE=LVCMOS33 DRIVE=4` |  |
| `gp5` | `C8` | `PULLMODE=UP IO_TYPE=LVCMOS33 DRIVE=4` |  |
| `gn5` | `B8` | `PULLMODE=UP IO_TYPE=LVCMOS33 DRIVE=4` |  |
| `gp6` | `C6` | `PULLMODE=UP IO_TYPE=LVCMOS33 DRIVE=4` |  |
| `gn6` | `C7` | `PULLMODE=UP IO_TYPE=LVCMOS33 DRIVE=4` |  |
| `gp7` | `A6` | `PULLMODE=UP IO_TYPE=LVCMOS33 DRIVE=4` |  |
| `gn7` | `B6` | `PULLMODE=UP IO_TYPE=LVCMOS33 DRIVE=4` |  |
| `gp8` | `A4` | `PULLMODE=UP IO_TYPE=LVCMOS33 DRIVE=4` | DIFF |
| `gn8` | `A5` | `PULLMODE=UP IO_TYPE=LVCMOS33 DRIVE=4` | DIFF |
| `gp9` | `A2` | `PULLMODE=UP IO_TYPE=LVCMOS33 DRIVE=4` | DIFF |
| `gn9` | `B1` | `PULLMODE=UP IO_TYPE=LVCMOS33 DRIVE=4` | DIFF |
| `gp10` | `C4` | `PULLMODE=UP IO_TYPE=LVCMOS33 DRIVE=4` | DIFF |
| `gn10` | `B4` | `PULLMODE=UP IO_TYPE=LVCMOS33 DRIVE=4` | DIFF |
| `gp11` | `F4` | `PULLMODE=UP IO_TYPE=LVCMOS33 DRIVE=4` | DIFF wifi_gpio26 |
| `gn11` | `E3` | `PULLMODE=UP IO_TYPE=LVCMOS33 DRIVE=4` | DIFF wifi_gpio25 |
| `gp12` | `G3` | `PULLMODE=UP IO_TYPE=LVCMOS33 DRIVE=4` | DIFF wifi_gpio33 PCLK |
| `gn12` | `F3` | `PULLMODE=NONE IO_TYPE=LVCMOS33` | DIFF wifi_gpio32 PCLK |
| `gp13` | `H4` | `PULLMODE=UP IO_TYPE=LVCMOS33 DRIVE=4` | DIFF wifi_gpio35 |
| `gn13` | `G5` | `PULLMODE=UP IO_TYPE=LVCMOS33 DRIVE=4` | DIFF wifi_gpio34 |
| `gp14` | `U18` | `PULLMODE=UP IO_TYPE=LVCMOS33 DRIVE=4` | DIFF ADC AIN1 |
| `gn14` | `U17` | `PULLMODE=UP IO_TYPE=LVCMOS33 DRIVE=4` | DIFF ADC AIN0 |
| `gp15` | `N17` | `PULLMODE=UP IO_TYPE=LVCMOS33 DRIVE=4` | DIFF ADC AIN3 |
| `gn15` | `P16` | `PULLMODE=UP IO_TYPE=LVCMOS33 DRIVE=4` | DIFF ADC AIN2 |
| `gp16` | `N16` | `PULLMODE=UP IO_TYPE=LVCMOS33 DRIVE=4` | DIFF ADC AIN5 |
| `gn16` | `M17` | `PULLMODE=UP IO_TYPE=LVCMOS33 DRIVE=4` | DIFF ADC AIN4 |
| `gp17` | `L16` | `PULLMODE=UP IO_TYPE=LVCMOS33 DRIVE=4` | DIFF ADC AIN7 GR_PCLK |
| `gn17` | `L17` | `PULLMODE=UP IO_TYPE=LVCMOS33 DRIVE=4` | DIFF ADC AIN6 |
| `gp18` | `H18` | `PULLMODE=UP IO_TYPE=LVCMOS33 DRIVE=4` | DIFF |
| `gn18` | `H17` | `PULLMODE=UP IO_TYPE=LVCMOS33 DRIVE=4` | DIFF |
| `gp19` | `F17` | `PULLMODE=UP IO_TYPE=LVCMOS33 DRIVE=4` | DIFF |
| `gn19` | `G18` | `PULLMODE=UP IO_TYPE=LVCMOS33 DRIVE=4` | DIFF |
| `gp20` | `D18` | `PULLMODE=UP IO_TYPE=LVCMOS33 DRIVE=4` | DIFF |
| `gn20` | `E17` | `PULLMODE=UP IO_TYPE=LVCMOS33 DRIVE=4` | DIFF |
| `gp21` | `C18` | `PULLMODE=UP IO_TYPE=LVCMOS33 DRIVE=4` | DIFF |
| `gn21` | `D17` | `PULLMODE=UP IO_TYPE=LVCMOS33 DRIVE=4` | DIFF |
| `gp22` | `B15` | `PULLMODE=UP IO_TYPE=LVCMOS33 DRIVE=4` |  |
| `gn22` | `C15` | `PULLMODE=UP IO_TYPE=LVCMOS33 DRIVE=4` |  |
| `gp23` | `B17` | `PULLMODE=UP IO_TYPE=LVCMOS33 DRIVE=4` |  |
| `gn23` | `C17` | `PULLMODE=UP IO_TYPE=LVCMOS33 DRIVE=4` |  |
| `gp24` | `C16` | `PULLMODE=UP IO_TYPE=LVCMOS33 DRIVE=4` |  |
| `gn24` | `D16` | `PULLMODE=UP IO_TYPE=LVCMOS33 DRIVE=4` |  |
| `gp25` | `D14` | `PULLMODE=UP IO_TYPE=LVCMOS33 DRIVE=4` |  |
| `gn25` | `E14` | `PULLMODE=UP IO_TYPE=LVCMOS33 DRIVE=4` |  |
| `gp26` | `B13` | `PULLMODE=UP IO_TYPE=LVCMOS33 DRIVE=4` |  |
| `gn26` | `C13` | `PULLMODE=UP IO_TYPE=LVCMOS33 DRIVE=4` |  |
| `gp27` | `D13` | `PULLMODE=UP IO_TYPE=LVCMOS33 DRIVE=4` |  |
| `gn27` | `E13` | `PULLMODE=UP IO_TYPE=LVCMOS33 DRIVE=4` |  |
| `user_programn` | `M4` | `PULLMODE=UP IO_TYPE=LVCMOS33 DRIVE=4` |  |
| `shutdown` | `G16` | `PULLMODE=DOWN IO_TYPE=LVCMOS33 DRIVE=4` | FPGA receives |
