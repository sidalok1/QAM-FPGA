`timescale 1ns / 1ps
`define HALF_PERIOD 5
module tb();

    parameter symb_width = 18;
    parameter symb_frac = 16;
    parameter clk_freq = 100_000_000;
    parameter spl_rate = 5_000_000;
    parameter carrier_frq = 1_000_000;
    parameter baud_rate = 50_000;
    parameter sync_len = 32;

    reg clk;
    always #`HALF_PERIOD clk = (clk === 1'b0);
    wire en = 1;
    wire rst = 0;
    reg start = 0;
    
    reg axis_state = 0;
    
    reg [31:0] m_axis_tdata = 0;
    reg [3:0] m_axis_tkeep = 0;
    reg m_axis_tlast = 0;
    reg m_axis_tvalid = 0;
    wire m_axis_tready;
    
    wire [31:0] s_axis_tdata;
    wire [3:0] s_axis_tkeep;
    wire s_axis_tlast;
    wire s_axis_tvalid;
    reg s_axis_tready = 1;
    
    always @ ( posedge clk ) 
        if ( m_axis_tvalid && m_axis_tready ) begin 
            m_axis_tvalid <= 0;
            m_axis_tlast <= 0;
            m_axis_tkeep <= 0; 
        end
    
    wire signed [symb_width-1:0] sym_gen_I, sym_gen_Q;
    wire signed [symb_width:0] mod_out;
//    wire sym_gen_ready;
    
    wire new_sample;
    clockdiv
    #(
        .I_CLK_FRQ(clk_freq),
        .FREQUENCY(spl_rate)
    ) sample_rate_generator (
        .rst(0),
        .en(en),
        .i_clk(clk),
        .o_clk(new_sample)
    );
    
    
    wire rx_bit, new_bit, msg_found, inv_msg_found;
    
    wire msg_edge, inv_msg_edge, msg_pulse, inv_msg_pulse;
    
//    edgedetect 
//        msg_edge_detector (
//            .clk(clk),
//            .rst(0),
//            .sig(msg_found),
//            .en(msg_edge)
//        ), 
//        inv_edge_detector (
//            .clk(clk),
//            .rst(0),
//            .sig(inv_msg_found),
//            .en(inv_msg_edge)
//        );
    
//    pulse_generator #( .pulse_width(50_000_000) )
//        msg_pulse_generator (
//            .clk(clk),
//            .rst(0),
//            .start(msg_edge),
//            .sig(msg_pulse)
//        ),
//        inv_pulse_generator (
//            .clk(clk),
//            .rst(0),
//            .start(inv_msg_edge),
//            .sig(inv_msg_pulse)
//        );
    
//    wire uart_rxd_out;
    
    Controller #(
        .DWIDTH(symb_width),
        .DFRAC(symb_frac),
        .SAMPLE_RATE(spl_rate),
        .SYMBOL_RATE(baud_rate)
        
    ) UUT1 (
        .clk(clk),
        .en(en),
        .rst(rst),
        .start(start),
        .new_sample(new_sample),
        .I(sym_gen_I),
        .Q(sym_gen_Q),
        
        .s_axis_tdata(m_axis_tdata),
//        .s_axis_tkeep(m_axis_tkeep),
        .s_axis_tlast(m_axis_tlast),
        .s_axis_tvalid(m_axis_tvalid),
        .s_axis_tready(m_axis_tready),
        
        .m_axis_tdata(s_axis_tdata),
//        .m_axis_tkeep(s_axis_tkeep),
        .m_axis_tlast(s_axis_tlast),
        .m_axis_tvalid(s_axis_tvalid),
        .m_axis_tready(s_axis_tready)
        
//        .rx_bit(rx_bit),
//        .new_bit(new_bit),
//        .msg_found(msg_found),
//        .inv_msg_found(inv_msg_found)
    );
    
    wire signed [symb_width:0] mag;
    wire signed [23:0] phase;
    wire vec_valid;
    
    CORDIC_VEC #(
        .DWIDTH(symb_width),
        .DFRAC(symb_frac),
        .PWIDTH(24),
        .DELAY(19)
    ) cordic_vectoring_mode (
        .clk(clk), .en(en), .rst(rst),
        .start(new_sample),
        .x_in(sym_gen_I),
        .y_in(sym_gen_Q),
        .phase(phase),
        .magnitude(mag),
        .valid(vec_valid)
    );
    
    wire signed [symb_width-1:0] I_ps, Q_ps;
    
    PolyphaseFilterUp #(
        .DWIDTH(symb_width),
        .DFRAC(symb_frac)
    ) I_ps_filt_tx (
        .clk(clk),
        .rst(rst),
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
        .rst(rst),
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
        .rst(rst),
        .en(en),
        .new_sample(new_sample),
        .I(I_ps),
        .Q(Q_ps),
        .passband(mod_out)
    );
    
    wire [7:0] dac_out = mod_out[symb_width -: 8] + 8'hA0;
    
    wire [11:0] signal;
    
    channel #(.DELAY(180)) wireless_channel (
        .clk(clk),
        .dac_data(dac_out),
        .impaired_signal(signal)
    );
    
    wire signed [symb_width-1:0] adc_in = {signal - 12'hA00, {(symb_width-12){1'b0}}};
    
    wire signed [symb_width-1:0] I_rx, Q_rx;
    
    CORDIC_DEMOD #(
        .DWIDTH(symb_width),
        .DFRAC(symb_frac),
        .SAMPLE_RATE(spl_rate),
        .CARRIER_FRQ(carrier_frq)
    ) cordic_demodulator (
        .clk(clk), .en(en), .rst(rst),
        .new_sample(new_sample),
        .passband(adc_in),
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
        .rst(rst),
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
        .rst(rst),
        .en(en),
        .new_sample(new_sample),
        .in_sample(Q_rx),
        .out_sample(Q_ps_rx),
        .new_rx_sample(Q_polyphase_ready)
    );
    
//    parameter adc_spl_rate = 3_000_000;
      
    
//    wire [symb_width-1:0] adc_increased_bits = {{symb_width-adc_bitdepth{1'b0}}, signal};
//    wire signed [symb_width-1:0] adc_offset = adc_increased_bits - 14'h0800;
    
    
//    wire signed [symb_width-1:0] upsample_out;
    
//    Upsample #(
//        .OUT_RATE(spl_rate),
//        .IN_RATE(adc_spl_rate),
//        .SYMBOL_WIDTH(symb_width)
//    ) adc_samplerate_converter (
//        .clk(clk),
//        .en(1),
//        .new_sample(new_sample),
//        .rst(0),
//        .i_sample(adc_offset),
//        .o_sample(upsample_out)
//    );
    
//    wire signed [symb_width-1:0] filtered_adc;
    
//    FIR #(
//        .SYMBOL_WIDTH(symb_width),
//        .SYMBOL_FRAC(symb_frac),
//        .FILT_TAPS(12),
//        .memfile("upsample_lp.mem")
//    ) ADC_filter (
//        .clk(clk),
//        .en(en),
//        .rst(rst),
//        .new_sample(new_sample),
//        .i_sample(upsample_out),
//        .o_sample(filtered_adc)
//    );
    
//    wire signed [symb_width-1:0] ac_signal;
    
//    DC_Decouple #(
//        .SYMBOL_WIDTH(symb_width),
//        .SYMBOL_FRAC(symb_frac),
//        .window(64),
//        .kp(1),
//        .ki(0),
//        .kd(0)
//    ) dc_signal_decoupler (
//        .clk(clk),
//        .rst(0),
//        .en(1),
//        .new_sample(new_sample),
//        .sample(filtered_adc),
//        .ac_signal(ac_signal)
//    );
    
//    wire signed[symb_width-1:0] agc_out;
//    wire signal_detected;
    
//    wire reset_rx;
//    edgedetect #(
//        .DETECT_NEGEDGE(0)
//    ) new_signal_detector (
//        .clk(clk),
//        .rst(0),
//        .sig(signal_detected),
//        .en(reset_rx)
//    );
    
//    signal_detector #(
//        .SYMBOL_WIDTH(symb_width),
//        .SYMBOL_FRAC(symb_frac),
//        .N(256),
//        .dB_THRESH(-30)
//    ) channel_detector (
//        .clk(clk),
//        .en(1),
//        .rst(0),
//        .new_sample(new_sample),
//        .sample(ac_signal),
//        .signal_detected(signal_detected)
//    );
    
//    PGA #(
//        .SYMBOL_WIDTH(symb_width),
//        .SYMBOL_FRAC(symb_frac),
//        .N(360),
//        .kp(0.03125),
//        .ki(0.0),
//        .kd(0.0),
//        .TARGET(0.8)
//    ) auto_amp (
//        .clk(clk),
//        .en(signal_detected),
//        .rst(reset_rx),
//        .new_sample(new_sample),
//        .in_sample(ac_signal),
//        .out_sample(agc_out)
//    );
    
    
    
//    reg dly_new_sample = 0;
    
//    always @ ( posedge clk ) dly_new_sample <= new_sample;
    
//    wire signed [symb_width-1:0] unfiltered_in_phase;
//    Costas_Loop #(
//        .SYMBOL_WIDTH(symb_width),
//        .SYMBOL_FRAC(symb_frac),
////        .SAMPLE_RATE(spl_rate),
//        .CARRIER_FRQ($itor(carrier_frq - (carrier_frq * 0.03))),
////        .CARRIER_FRQ(carrier_frq),
//        .kp(0.01),
//        .ki(0.00002),
//        .kd(0)
//    ) demodulator (
//        .clk(clk),
//        .rst(reset_rx),
//        .en(1),
//        .new_sample(new_sample),
//        .modulated_input(agc_out),
//        .I_component(unfiltered_in_phase)
//    );
    
//    wire signed [symb_width-1:0] filtered_in_phase;
    
//    RRC_Filter #(
//        .DWIDTH(symb_width),
//        .DFRAC(symb_frac),
//        .PIPELEN(3),
//        .fixed_gain(-3)
//    ) matched_filter (
//        .clk(clk),
//        .rst(rst),
//        .in_sample(unfiltered_in_phase),
//        .out_sample(filtered_in_phase)
//    );
    
    
//    wire signed [13:0] symbol;
//    wire new_symbol;
    
    
//    Early_Late_TED #(
//        .SYMBOL_WIDTH(symb_width),
//        .SYMBOL_FRAC(symb_frac),
//        .SPS(spl_rate / baud_rate),
//        .kp(1.5),
//        .ki(0.1),
//        .kd(5)
//    ) sampler (
//        .clk(clk),
//        .rst(reset_rx),
//        .en(1),
//        .sample(filtered_in_phase),
//        .new_sample(new_sample),
//        .symbol_ready(new_symbol),
//        .symbol(symbol)
//    );
    
    
//    Symbol_Bit_Mapper #(
//        .SYMBOL_WIDTH(symb_width),
//        .SYMBOL_FRAC(symb_frac)
//    ) symb_to_bits (
//        .clk(clk),
//        .rst(0),
//        .en(signal_detected),
//        .symbol(symbol),
//        .new_symbol(new_symbol),
//        .rx_bit(rx_bit),
//        .new_bit(new_bit)
//    );
    
    task write_m_axis (input string s);
        for ( int i = 0; i < s.len(); i++ ) begin
            m_axis_tdata = {24'b0, s[i]};
            m_axis_tvalid = 1;
            m_axis_tlast = i == (s.len() - 1);
            while ( m_axis_tvalid ) #1;
        end
    endtask
    
    initial begin
        
        write_m_axis("A perfectly acceptable example of an extremely verbose message of large words and many characters!!!");
        
//        #10 m_axis_tdata = "hell";
//        m_axis_tvalid = 1;
//        while ( m_axis_tvalid ) #1;
        
//        m_axis_tdata = "o ov";
//        m_axis_tvalid = 1;
//        while ( m_axis_tvalid ) #1;
        
//        m_axis_tdata = "er t";
//        m_axis_tvalid = 1;
//        while ( m_axis_tvalid ) #1;
        
//        m_axis_tdata = "here";
//        m_axis_tvalid = 1;
//        while ( m_axis_tvalid ) #1;
        
//        m_axis_tdata = "!\0\0\0";
//        m_axis_tvalid = 1;
//        m_axis_tlast = 1;
//        m_axis_tkeep = 'b1000;
//        while ( m_axis_tvalid ) #1;
        
        
//        #3_000_000 m_axis_tdata = "hi!\0";
//        m_axis_tvalid = 1;
//        m_axis_tlast = 1;
//        m_axis_tkeep = 'b1110;
//        while ( m_axis_tvalid ) #1;
        
        #3_000_000 start = 1; 
        #10 start = 0;
    end
    
endmodule
