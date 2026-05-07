`timescale 1ns / 1ps
`define HALF_PERIOD 5
module tb();

    parameter clk_freq = 100_000_000;
    parameter spl_rate = 5_000_000;
    
    parameter uart_baud = 1_000_000;

    reg clk;
    always #`HALF_PERIOD clk = (clk === 1'b0);
    wire en = 1;
    wire rst = 0;
    reg start = 0;

    wire [7:0] dac_out;
    wire [11:0] adc_in;
    wire adc_clk, adc_ovf;

    wire adc_n_en, adc_shdn;

    wire [2:0] led;

    wire interrupt;

    wire uart_rx, uart_tx;

    Radio UUT (
        .dac(dac_out),

        .adc(adc_in[11:2]),
        .adc_clk(adc_clk),
        .adc_ovf(adc_ovf),
        .adc_n_en(adc_n_en),
        .adc_shdn(adc_shdn),

        .led(led),

        .rst(rst),
        .start(start),
        .n_en(~en),
        .usb_uart_rxd(uart_tx),
        .usb_uart_txd(uart_rx),

        .clk(clk)
    );

    channel #(
        .ifreq(clk_freq),
        .DELAY(180)
    ) wireless_channel (
        .clk(clk),
        .dac_data(dac_out),
        .adc_clk(adc_clk),
        .adc_data(adc_in),
        .adc_ovf(adc_ovf)
    );

    wire [7:0] uart_rx_data;
    reg [7:0] uart_tx_data = 0;
    wire uart_busy;
    reg uart_en = 0;
    wire uart_valid;

    uarttx #(.BAUD(uart_baud)) uart_host_transmitter (
        .clk(clk), .en(uart_en), .rst(rst),
        .i_data(uart_tx_data),
        .tx(uart_tx),
        .busy(uart_busy)
    );

    uartrx #(.BAUD(uart_baud)) uart_host_receiver (
        .clk(clk), .en(en), .rst(rst),
        .rx(uart_rx),
        .rx_data(uart_rx_data),
        .valid(uart_valid)
    );
    
    // always @ ( posedge clk ) 
    //     if ( m_axis_tvalid && m_axis_tready ) begin 
    //         m_axis_tvalid <= 0;
    //         m_axis_tlast <= 0;
    //         m_axis_tkeep <= 0; 
    //     end
    
    // task write_m_axis (input string s);
    //     for ( int i = 0; i < s.len(); i++ ) begin
    //         m_axis_tdata = {24'b0, s[i]};
    //         m_axis_tvalid = 1;
    //         m_axis_tlast = i == (s.len() - 1);
    //         while ( m_axis_tvalid ) #1;
    //     end
    // endtask
    
    task write_uart ( input string s );
        for ( int i = 0; i < s.len(); i++ ) begin
            uart_tx_data = s[i];
            while ( !uart_busy ) #1 uart_en = 1;
            while ( uart_busy ) #1 uart_en = 0;
        end
        if ( s[s.len()-1] != "\n" ) begin
            uart_tx_data = "\n";
            while ( !uart_busy ) #1 uart_en = 1;
            while ( uart_busy ) #1 uart_en = 0;
        end
    endtask

    initial begin
        
        start = 1;
        #2_000_000 start = 0;
        #2_000_000 write_uart("A message that is nontrivial in size!!!");
    end
    
endmodule
