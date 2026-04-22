//Copyright 1986-2022 Xilinx, Inc. All Rights Reserved.
//Copyright 2022-2025 Advanced Micro Devices, Inc. All Rights Reserved.
//--------------------------------------------------------------------------------
//Tool Version: Vivado v.2025.1 (win64) Build 6140274 Thu May 22 00:12:29 MDT 2025
//Date        : Wed Apr 22 14:27:59 2026
//Host        : SID3 running 64-bit major release  (build 9200)
//Command     : generate_target system_wrapper.bd
//Design      : system_wrapper
//Purpose     : IP block netlist
//--------------------------------------------------------------------------------
`timescale 1 ps / 1 ps

module system_wrapper
   (adc,
    adc_clk,
    adc_n_en,
    adc_ovf,
    adc_shdn,
    dac,
    led,
    reset_0,
    sys_clock,
    usb_uart_rxd,
    usb_uart_txd);
  input [9:0]adc;
  output adc_clk;
  output adc_n_en;
  input adc_ovf;
  output adc_shdn;
  output [7:0]dac;
  output [1:0]led;
  input reset_0;
  input sys_clock;
  input usb_uart_rxd;
  output usb_uart_txd;

  wire [9:0]adc;
  wire adc_clk;
  wire adc_n_en;
  wire adc_ovf;
  wire adc_shdn;
  wire [7:0]dac;
  wire [1:0]led;
  wire reset_0;
  wire sys_clock;
  wire usb_uart_rxd;
  wire usb_uart_txd;

  system system_i
       (.adc(adc),
        .adc_clk(adc_clk),
        .adc_n_en(adc_n_en),
        .adc_ovf(adc_ovf),
        .adc_shdn(adc_shdn),
        .dac(dac),
        .led(led),
        .reset_0(reset_0),
        .sys_clock(sys_clock),
        .usb_uart_rxd(usb_uart_rxd),
        .usb_uart_txd(usb_uart_txd));
endmodule
