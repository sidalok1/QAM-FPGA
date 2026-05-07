module Radio(
    output wire [7:0] dac,
    
    input wire [9:0] adc,
    input wire adc_ovf,
    output wire adc_n_en,
    output wire adc_shdn,
    output wire adc_clk,

    input wire rst,
    
    input wire start,
    input wire n_en,

    input wire usb_uart_rxd,
    output wire usb_uart_txd,
    
    output wire [3:0] led,
    
    input wire clk
    );
    
    parameter symb_width = 16;
    parameter symb_frac = 12;
    parameter clk_freq = 100_000_000;
    parameter spl_rate = 5_000_000;
    parameter carrier_frq = 1_000_000;
    parameter baud_rate = 50_000;
    parameter order = 4;
    parameter uart_baud = 1_000_000;
    
    

    wire rst_debounce;
    debouncer #(
        .N(15)
    ) rst_debouncer (
        .clk(clk),
        .rst(1'b0),
        .in(rst),
        .out(rst_debounce)
    );
    
    wire n_en_debounce;
    wire en = ~n_en_debounce;
    debouncer #(
        .N(15)
    ) en_debouncer (
        .clk(clk), .rst(rst_debounce),
        .in(n_en),
        .out(n_en_debounce)
    ); 

    wire start_debounce;
    debouncer #(
        .N(15)
    ) start_debouncer (
        .clk(clk),
        .rst(rst_debounce),
        .in(start),
        .out(start_debounce)
    );
    
    wire new_sample;
    clockdiv #(
        .I_CLK_FRQ(clk_freq),
        .FREQUENCY(spl_rate)
    ) sample_rate_generator (
        .rst(rst_debounce),
        .en(en),
        .i_clk(clk),
        .o_clk(new_sample)
    );
    
    pulse_generator #(
        .pulse_width(1000)
    ) adc_overflow_pulse_generator (
        .clk(clk), .rst(rst_debounce), .start(adc_ovf),
        .sig(led[2])
    );
    wire signal_detected;
    
    wire signed [symb_width-1:0] sym_gen_I, sym_gen_Q;
    wire signed [symb_width:0] mod_out;
    
    
    wire new_symbol;
    wire [$clog2(order)-1:0] rx_symbol;
    wire interrupt;
    
    wire tx_start;
    pulse_generator #(
        .pulse_width(1000)
    ) tx_start_pulse_generator (
        .clk(clk), .rst(rst_debounce), .start(tx_start),
        .sig(led[3])
    );
    
    Controller #(
        .DWIDTH(symb_width),
        .DFRAC(symb_frac),
        .SAMPLE_RATE(spl_rate),
        .SYMBOL_RATE(baud_rate),
        .MODULATION_ORDER(order),
        .UART_BAUD(uart_baud)
        
    ) main_controller (
        .clk(clk),
        .en(en),
        .rst(rst_debounce),
        .start(start_debounce),
        .new_sample(new_sample),
        .signal_detected(signal_detected),
        .I(sym_gen_I),
        .Q(sym_gen_Q),
        .tx_started(tx_start),
        
        .uart_rx(usb_uart_rxd),
        .uart_tx(usb_uart_txd),
        
        .new_symbol(new_symbol),
        .rx_symbol(rx_symbol),
        .interrupt(interrupt)
    );
    
//    reg [7:0] dac_data = 0;
//    always @ ( posedge clk ) dac_data = ((sym_gen_I + sym_gen_Q) >>> (symb_width-8)) + 8'h80;
//    assign dac = dac_data;
    
    pulse_generator #(
        .pulse_width(1000)
    ) interrupt_pulse_generator (
        .clk(clk), .rst(rst_debounce), .start(interrupt),
        .sig(led[1])
    );
    
    wire signed [symb_width-1:0] I_ps, Q_ps;
    
    PolyphaseFilterUp #(
        .DWIDTH(symb_width),
        .DFRAC(symb_frac)
    ) I_ps_filt_tx (
        .clk(clk),
        .rst(rst_debounce),
        .en(en),
        .new_sample(new_sample),
        .in_sample(sym_gen_I),
        .out_sample(I_ps)
    );
    
    PolyphaseFilterUp #(
        .DWIDTH(symb_width),
        .DFRAC(symb_frac)
    ) Q_ps_filt_tx (
        .clk(clk),
        .rst(rst_debounce),
        .en(en),
        .new_sample(new_sample),
        .in_sample(sym_gen_Q),
        .out_sample(Q_ps)
    );
    
    CORDIC_MOD #(
        .DWIDTH(symb_width),
        .DFRAC(symb_frac),
        .SAMPLE_RATE(spl_rate),
        .CARRIER_FRQ(carrier_frq)
    ) cordic_modulator (
        .clk(clk),
        .rst(rst_debounce),
        .en(en),
        .new_sample(new_sample),
        .I(I_ps),
        .Q(Q_ps),
        .passband(mod_out)
    );

    wire signed [symb_width+16:0] amp_out;
    localparam reg signed [15:0] gain = $rtoi(1.5 * 2**8);
    PipeMult #(
        .WIDTH_A(symb_width+1),
        .WIDTH_B(16)
    ) amplifier (
        .clk(clk), .en(en), .rst(rst_debounce),
        .a(mod_out), .b(gain),
        .r(amp_out)
    );

    reg [7:0] dac_data = 0;
    always @ ( posedge clk ) dac_data = (amp_out >>> (symb_width)) + 8'h80;
    assign dac = dac_data;
    
    
    wire signed [symb_width-1:0] rx_signal;
    
    PMOD9200 #(
        .I_CLK_FRQ(clk_freq),
        .S_CLK_FRQ(spl_rate),
        .DWIDTH(symb_width),
        .DFRAC(symb_frac)
    ) adc_controller (
        .clk(clk),
        .rst(rst_debounce),
        .en(1),
        .adc_din(adc),
        .dout(rx_signal),
        .adc_clk(adc_clk),
        .adc_n_en(adc_n_en),
        .adc_shdn(adc_shdn)
    );
    

    wire signed [symb_width-1:0] rx_filt_out;
    IIR #(
        .DWIDTH(symb_width),
        .DFRAC(symb_frac),
        .SOS(5),
        .COEFFICIENTS("rx_iir.mem")
    ) rx_filter (
        .clk(clk),
        .en(en),
        .rst(rst_debounce),
        .new_sample(new_sample),
        .filt_in(rx_signal),
        .filt_out(rx_filt_out)
    );


    signal_detector #(
        .SYMBOL_WIDTH(symb_width),
        .SYMBOL_FRAC(symb_frac),
        .N(64),
        .dB_THRESH(-40)
    ) signal_power_detector (
        .clk(clk), .en(en), .rst(rst_debounce),
        .new_sample(new_sample),
        .sample(rx_filt_out),
        .signal_detected(signal_detected)
    );
    
    pulse_generator #(
        .pulse_width(1000)
    ) signal_detected_pulse_generator (
        .clk(clk), .rst(rst_debounce), .start(signal_detected),
        .sig(led[0])
    );
    
    wire signed [symb_width-1:0] I_rx, Q_rx;
    
    CORDIC_DEMOD #(
        .DWIDTH(symb_width),
        .DFRAC(symb_frac),
        .SAMPLE_RATE(spl_rate),
        .CARRIER_FRQ(carrier_frq)
    ) cordic_demodulator (
        .clk(clk), .en(en), .rst(rst_debounce),
        .new_sample(new_sample),
        .passband(rx_filt_out),
        .I(I_rx), .Q(Q_rx)
    );
    
    wire signed [symb_width-1:0] I_ps_rx, Q_ps_rx;
    
    wire I_polyphase_ready, Q_polyphase_ready;
    wire new_rx_sample = I_polyphase_ready | Q_polyphase_ready;
    
    PolyphaseFilterDown #(
        .DWIDTH(symb_width),
        .DFRAC(symb_frac)
    ) I_ps_filt_rx (
        .clk(clk),
        .rst(rst_debounce),
        .en(en),
        .new_sample(new_sample),
        .in_sample(I_rx),
        .out_sample(I_ps_rx),
        .new_rx_sample(I_polyphase_ready)
    );
    
    PolyphaseFilterDown #(
        .DWIDTH(symb_width),
        .DFRAC(symb_frac)
    ) Q_ps_filt_rx (
        .clk(clk),
        .rst(rst_debounce),
        .en(en),
        .new_sample(new_sample),
        .in_sample(Q_rx),
        .out_sample(Q_ps_rx),
        .new_rx_sample(Q_polyphase_ready)
    );
    
    
    
    wire signed [symb_width-1:0] I_eq, Q_eq;
    
    Sampler #(
        .DWIDTH(symb_width),
        .DFRAC(symb_frac),
        .MOD_ORDER(order)
    ) symbol_aware_sampler (
        .clk(clk), .en(en), .rst(rst_debounce),
        .new_sample(new_rx_sample),
        .I_i(I_ps_rx),
        .Q_i(Q_ps_rx),
        .signal_detected(signal_detected),
        .I_o(I_eq),
        .Q_o(Q_eq),
        .rx_symbol(rx_symbol),
        .new_symbol(new_symbol),
        .interrupt(interrupt)
    );
    
//    ila_0 logic_analyzer (
//        .clk(clk), // input wire clk
    
    
//        .probe0(main_controller.tx_state), // input wire [6:0]  probe0  
//        .probe1(dac), // input wire [7:0]  probe1 
//        .probe2(adc), // input wire [9:0]  probe2 
//        .probe3(signal_detected), // input wire [0:0]  probe3 
//        .probe4(symbol_aware_sampler.state) // input wire [4:0]  probe4
//    );
    
endmodule