module Radio(
    output wire [7:0] DAC_O,
    
    input wire [9:0] ADC_I,
    input wire ADC_OVF_I,
    output wire ADC_N_EN_O,
    output wire ADC_SHDN_O,
    output wire ADC_CLK_O,
    
    output wire [1:0] LED_O,
    
    input wire [31:0]                       s_axis_tdata,
//    input wire [3:0]                        s_axis_tkeep,
    input wire                              s_axis_tlast,
    input wire                              s_axis_tvalid,
    output wire                             s_axis_tready,
    
    output wire [31:0]                      m_axis_tdata,
//    output wire [3:0]                       m_axis_tkeep,
    output wire                             m_axis_tlast,
    output wire                             m_axis_tvalid,
    input wire                              m_axis_tready,
    
    output wire interrupt,
    
    input wire aclk
    );
    
    parameter symb_width = 14;
    parameter symb_frac = 12;
    parameter clk_freq = 96_000_000;
    parameter spl_rate = 6_000_000;
    parameter carrier_frq = 1_000_000;
    parameter baud_rate = 50_000;
    parameter sync_len = 32;
    
    wire en = 1; 
    
    wire clk;
    
    assign clk = aclk;
    
    wire new_sample;
    clockdiv #(
        .I_CLK_FRQ(clk_freq),
        .FREQUENCY(spl_rate)
    ) sample_rate_generator (
        .rst(0),
        .en(en),
        .i_clk(clk),
        .o_clk(new_sample)
    );
    
    wire signed [symb_width-1:0] symbol_generator_out;
    
    wire rx_bit, new_bit, msg_found, inv_msg_found;
    
    wire msg_edge;
    
    edgedetect 
        msg_edge_detector (
            .clk(clk),
            .rst(0),
            .sig(msg_found | inv_msg_found),
            .en(msg_edge)
        );
    
    pulse_generator #( .pulse_width(50_000_000) )
        msg_pulse_generator (
            .clk(clk),
            .rst(0),
            .start(msg_edge),
            .sig(LED_O[0])
        );
        
    wire start_tx;
    clockdiv #(
        .I_CLK_FRQ(clk_freq),
        .FREQUENCY(5000)
    ) tx_start_clk (
        .rst(0),
        .en(en),
        .i_clk(clk),
        .o_clk(start_tx)
    );
    
    Controller #(
        .SYMBOL_WIDTH(symb_width),
        .SYMBOL_FRAC(symb_frac),
        .SAMPLE_RATE(spl_rate),
        .SYMBOL_RATE(baud_rate),
        .SYNC_LEN(sync_len)
    ) SYMBGEN (
        .clk(clk),
        .en(en),
        .rst(0),
        .start(start_tx),
        .new_sample(new_sample),
        .sample(symbol_generator_out),
        
        //  Pass-through of axi stream signals
        .s_axis_tdata(s_axis_tdata),
//        .s_axis_tkeep(s_axis_tkeep),
        .s_axis_tlast(s_axis_tlast),
        .s_axis_tvalid(s_axis_tvalid),
        .s_axis_tready(s_axis_tready),
        
        .m_axis_tdata(m_axis_tdata),
//        .m_axis_tkeep(m_axis_tkeep),
        .m_axis_tlast(m_axis_tlast),
        .m_axis_tvalid(m_axis_tvalid),
        .m_axis_tready(m_axis_tready),
        
        .interrupt(interrupt),
        
        .rx_bit(rx_bit),
        .new_bit(new_bit),
        .msg_found(msg_found),
        .inv_msg_found(inv_msg_found)
    );
    
    wire signed [symb_width-1:0] pulse_shape_out;


    RRC_Filter #(
        .DWIDTH(symb_width),
        .DFRAC(symb_frac),
        .PIPELEN(3),
        .fixed_gain(3)
    ) psfilter (
        .clk(clk),
        .rst(0),
        .in_sample(symbol_generator_out),
        .out_sample(pulse_shape_out)
    );
    
    wire signed [symb_width-1:0] I, Q;
    
    IQGenerator #(
        .SYMBOL_WIDTH(symb_width),
        .SYMBOL_FRAC(symb_frac),
        .SAMPLE_RATE(spl_rate),
        .FREQUENCY(carrier_frq),
        .RES(8)
    ) carrier_wave_generator (
        .clk(clk),
        .rst(0),
        .en(en),
        .new_sample(new_sample),
        .offset(0),
        .I(I),
        .Q(Q)
    );
    
    wire signed [(2*symb_width)-1:0] modulation_product;
    
    PipeMult #(
        .WIDTH_A(symb_width),
        .WIDTH_B(symb_width),
        .PIPELEN(3)
    ) modulation_mult_pipeline (
        .clk(clk),
        .en(en),
        .rst(0),
        .a(I),
        .b(pulse_shape_out),
        .r(modulation_product)
    );
    
    reg signed [symb_width-1:0] mod_out = 0;
    reg [symb_width-1:0] offset = 0;
    assign DAC_O = offset[symb_width-1:symb_width-8];
    
    localparam symb_whole       = symb_width - symb_frac;
    //  Two's complement symbols parameterized to given bitwidths
    localparam symb_zero        = {symb_width{1'b0}};
    localparam symb_one         = {{symb_whole-1{1'b0}}, 1'b1, {symb_frac{1'b0}}};
    localparam symb_neg_one     = {{symb_whole{1'b1}}, {symb_frac{1'b0}}};
    localparam symb_half        = symb_one / 2;
    localparam symb_quart       = symb_one / 4;
    localparam symb_eigth       = symb_one / 8;
    
    
    
    //  Receiver code
    
//    assign {ADC_N_EN_O, ADC_SHDN_O} = 0;
    
//    wire [11:0] adc_out;
    
//    parameter adc_spl_rate = 3_000_000;
    
//    max11108_controller adc_controller (
//        .clk(clk),
//        .rst(0),
//        .en(1),
//        .din(SDO_I),
//        .dout(adc_out),
//        .sclk(SCK_O),
//        .cs(CS_O)
//    );
    
    wire signed [symb_width-1:0] adc_data;
    PMOD9200 #(
        .I_CLK_FRQ(clk_freq),
        .S_CLK_FRQ(spl_rate),
        .DWIDTH(symb_width),
        .DFRAC(symb_frac)
    ) adc_controller (
        .clk(clk),
        .rst(0),
        .en(1),
        .adc_din(ADC_I),
        .dout(adc_data),
        .adc_clk(ADC_CLK_O),
        .adc_n_en(ADC_N_EN_O),
        .adc_shdn(ADC_SHDN_O)
    );
    
    
//    Upsample #(
//        .OUT_RATE(spl_rate),
//        .IN_RATE(adc_spl_rate),
//        .SYMBOL_WIDTH(symb_width)
//    ) adc_samplerate_converter (
//        .clk(clk),
//        .en(1),
//        .rst(0),
//        .new_sample(new_sample),
//        .i_sample(adc_offset),
//        .o_sample(upsampled_out)
//    );
    
    wire signed [13:0] filtered_adc;
    FIR #(
        .SYMBOL_WIDTH(symb_width),
        .SYMBOL_FRAC(symb_frac),
        .FILT_TAPS(12),
        .memfile("upsample_lp.mem")
    ) ADC_filter (
        .clk(clk),
        .en(1),
        .rst(0),
        .new_sample(new_sample),
        .i_sample(adc_data),
        .o_sample(filtered_adc)
    );
    
    wire signed [symb_width-1:0] ac_signal;
    
    DC_Decouple #(
        .SYMBOL_WIDTH(symb_width),
        .SYMBOL_FRAC(symb_frac),
        .window(64),
        .kp(1),
        .ki(0),
        .kd(0)
    ) dc_signal_decoupler (
        .clk(clk),
        .rst(0),
        .en(1),
        .new_sample(new_sample),
        .sample(filtered_adc),
        .ac_signal(ac_signal)
    );
    
    wire signed[13:0] agc_out;
    wire signal_detected;
    
    wire reset_rx;
    edgedetect #(
        .DETECT_NEGEDGE(0)
    ) new_signal_detector (
        .clk(clk),
        .rst(0),
        .sig(signal_detected),
        .en(reset_rx)
    );
    
    signal_detector #(
        .SYMBOL_WIDTH(symb_width),
        .SYMBOL_FRAC(symb_frac),
        .N(256),
        .dB_THRESH(-20)
    ) channel_detector (
        .clk(clk),
        .en(1),
        .rst(0),
        .new_sample(new_sample),
        .sample(ac_signal),
        .signal_detected(signal_detected)
    );
    
    PGA #(
        .SYMBOL_WIDTH(symb_width),
        .SYMBOL_FRAC(symb_frac),
        .N(360),
        .kp(0.03125),
        .ki(0.0),
        .kd(0.0),
        .TARGET(0.8)
    ) auto_amp (
        .clk(clk),
        .en(signal_detected),
        .rst(reset_rx),
        .new_sample(new_sample),
        .in_sample(ac_signal),
        .out_sample(agc_out)
    );
    
    pulse_generator #( .pulse_width(1000) )
        rx_pulse_generator (
            .clk(clk),
            .rst(0),
            .start(signal_detected),
            .sig(LED_O[1])
        );
    
    wire signed [symb_width-1:0] unfiltered_in_phase;
    Costas_Loop #(
        .SYMBOL_WIDTH(symb_width),
        .SYMBOL_FRAC(symb_frac),
        .CARRIER_FRQ(carrier_frq),
        .kp(0.01),
        .ki(0.00002),
        .kd(0)
    ) demodulator (
        .clk(clk),
        .rst(reset_rx),
        .en(1),
        .new_sample(new_sample),
        .modulated_input(agc_out),
        .I_component(unfiltered_in_phase)
    );
    
    wire signed [symb_width-1:0] filtered_in_phase;
    
    RRC_Filter #(
        .DWIDTH(symb_width),
        .DFRAC(symb_frac),
        .PIPELEN(3),
        .fixed_gain(-3)
    ) matched_filter (
        .clk(clk),
        .rst(0),
        .in_sample(unfiltered_in_phase),
        .out_sample(filtered_in_phase)
    );
    
    wire signed [symb_width-1:0] symbol;
    wire new_symbol;
    
    Early_Late_TED #(
        .SYMBOL_WIDTH(symb_width),
        .SYMBOL_FRAC(symb_frac),
        .SPS(spl_rate / baud_rate),
        .kp(1.5),
        .ki(0.1),
        .kd(5)
    ) sampler (
        .clk(clk),
        .rst(reset_rx),
        .en(1),
        .sample(filtered_in_phase),
        .new_sample(new_sample),
        .symbol_ready(new_symbol),
        .symbol(symbol)
    );
    
    Symbol_Bit_Mapper #(
        .SYMBOL_WIDTH(symb_width),
        .SYMBOL_FRAC(symb_frac)
    ) symb_to_bits (
        .clk(clk),
        .rst(0),
        .en(signal_detected),
        .symbol(symbol),
        .new_symbol(new_symbol),
        .rx_bit(rx_bit),
        .new_bit(new_bit)
    );
    
    ila_0 signal_analyzer (
        .clk(clk), // input wire clk
    
    
        .probe0(ac_signal), // input wire [13:0]  probe0  
        .probe1(agc_out), // input wire [13:0]  probe1 
        .probe2(filtered_in_phase), // input wire [13:0]  probe2 
        .probe3(signal_detected), // input wire [0:0]  probe3 
        .probe4(new_sample), // input wire [0:0]  probe4
        .probe5(SYMBGEN.in_bit),
        .probe6(new_bit),
        .probe7({msg_found, inv_msg_found}),
        .probe8(SYMBGEN.rx_state),
        .probe9(SYMBGEN.code),
        .probe10(SYMBGEN.rx_len)
    );
    
    always @ ( posedge clk ) if ( en ) begin
        mod_out <= modulation_product >>> symb_frac;
        offset <= {~mod_out[symb_width-1], mod_out[symb_width-2:0]};

    end
    
    
endmodule