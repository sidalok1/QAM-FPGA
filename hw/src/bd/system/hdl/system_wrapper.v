//Copyright 1986-2022 Xilinx, Inc. All Rights Reserved.
//Copyright 2022-2025 Advanced Micro Devices, Inc. All Rights Reserved.
//--------------------------------------------------------------------------------
//Tool Version: Vivado v.2025.1 (win64) Build 6140274 Thu May 22 00:12:29 MDT 2025
//Date        : Sun Feb  8 18:08:49 2026
//Host        : SID3 running 64-bit major release  (build 9200)
//Command     : generate_target system_wrapper.bd
//Design      : system_wrapper
//Purpose     : IP block netlist
//--------------------------------------------------------------------------------
`timescale 1 ps / 1 ps

module system_wrapper
   (cs,
    dac,
    led,
    reset_0,
    sclk,
    sdo,
    sys_clock,
    usb_uart_rxd,
    usb_uart_txd);
  output cs;
  output [7:0]dac;
  output [1:0]led;
  input reset_0;
  output sclk;
  input sdo;
  input sys_clock;
  input usb_uart_rxd;
  output usb_uart_txd;

  wire cs;
  wire [7:0]dac;
  wire [1:0]led;
  wire reset_0;
  wire sclk;
  wire sdo;
  wire sys_clock;
  wire usb_uart_rxd;
  wire usb_uart_txd;

  system system_i
       (.cs(cs),
        .dac(dac),
        .led(led),
        .reset_0(reset_0),
        .sclk(sclk),
        .sdo(sdo),
        .sys_clock(sys_clock),
        .usb_uart_rxd(usb_uart_rxd),
        .usb_uart_txd(usb_uart_txd));
endmodule
