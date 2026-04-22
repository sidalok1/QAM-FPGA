`timescale 1ns / 1ps
`define HALF_PERIOD 5
module tb();

    parameter symb_width = 14;
    parameter symb_frac = 12;
    parameter clk_freq = 96_000_000;
    parameter spl_rate = 6_000_000;
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
    
    wire signed [symb_width-1:0] sym_gen_out;
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
    
    edgedetect 
        msg_edge_detector (
            .clk(clk),
            .rst(0),
            .sig(msg_found),
            .en(msg_edge)
        ), 
        inv_edge_detector (
            .clk(clk),
            .rst(0),
            .sig(inv_msg_found),
            .en(inv_msg_edge)
        );
    
    pulse_generator #( .pulse_width(50_000_000) )
        msg_pulse_generator (
            .clk(clk),
            .rst(0),
            .start(msg_edge),
            .sig(msg_pulse)
        ),
        inv_pulse_generator (
            .clk(clk),
            .rst(0),
            .start(inv_msg_edge),
            .sig(inv_msg_pulse)
        );
    
    wire uart_rxd_out;
    
    Controller #(
        .SYMBOL_WIDTH(symb_width),
        .SYMBOL_FRAC(symb_frac),
        .SAMPLE_RATE(spl_rate),
        .SYMBOL_RATE(baud_rate),
        .SYNC_LEN(sync_len)
    ) UUT1 (
        .clk(clk),
        .en(en),
        .rst(rst),
        .start(start),
        .new_sample(new_sample),
        .sample(sym_gen_out),
        
        .s_axis_tdata(m_axis_tdata),
//        .s_axis_tkeep(m_axis_tkeep),
        .s_axis_tlast(m_axis_tlast),
        .s_axis_tvalid(m_axis_tvalid),
        .s_axis_tready(m_axis_tready),
        
        .m_axis_tdata(s_axis_tdata),
//        .m_axis_tkeep(s_axis_tkeep),
        .m_axis_tlast(s_axis_tlast),
        .m_axis_tvalid(s_axis_tvalid),
        .m_axis_tready(s_axis_tready),
        
        .rx_bit(rx_bit),
        .new_bit(new_bit),
        .msg_found(msg_found),
        .inv_msg_found(inv_msg_found)
    );
    
    wire signed [symb_width-1:0] ps_out;

    RRC_Filter #(
        .DWIDTH(symb_width),
        .DFRAC(symb_frac),
        .PIPELEN(3),
        .fixed_gain(3)
    ) UUT2C (
        .clk(clk),
        .rst(rst),
        .in_sample(sym_gen_out),
        .out_sample(ps_out)
    );
    
    wire signed [symb_width-1:0] I, Q;
    
    IQGenerator #(
        .SYMBOL_WIDTH(symb_width),
        .SYMBOL_FRAC(symb_frac),
        .SAMPLE_RATE(spl_rate),
        .FREQUENCY(carrier_frq),
        .RES(8)
    ) carrier (
        .clk(clk),
        .rst(rst),
        .en(en),
        .new_sample(new_sample),
        .offset(0),
        .I(I),
        .Q(Q)
    );
    
    localparam symb_whole       = symb_width - symb_frac;
    //  Two's complement symbols parameterized to given bitwidths
    localparam symb_zero        = {symb_width{1'b0}};
    localparam symb_one         = {{symb_whole-1{1'b0}}, 1'b1, {symb_frac{1'b0}}};
    localparam symb_neg_one     = {{symb_whole{1'b1}}, {symb_frac{1'b0}}};
    localparam symb_half        = symb_one / 2;
    localparam symb_quart       = symb_one / 4;
    localparam symb_eigth       = symb_one / 8;
    
    wire signed [(2*symb_width)-1:0] modulation_product;
    PipeMult #(
        .WIDTH_A(symb_width),
        .WIDTH_B(symb_width),
        .PIPELEN(3)
    ) modulation_mult_pipeline (
        .clk(clk),
        .en(en),
        .rst(rst),
        .a(I),
        .b(ps_out),
        .r(modulation_product)
    );
    
    
    wire signed [symb_width-1:0] mod_out = modulation_product >>> symb_frac;
    wire [symb_width-1:0] offset = {~mod_out[symb_width-1], mod_out[symb_width-2:0]};
    wire [7:0] dac_out = offset[symb_width-1:symb_width-8];
    
    localparam adc_bitdepth = 12;
    
    wire [adc_bitdepth-1:0] signal;
    
    channel #(.DELAY(180)) wireless_channel (
        .clk(clk),
        .dac_data(dac_out),
        .impaired_signal(signal)
    );
    
    
    parameter adc_spl_rate = 3_000_000;
      
    
    wire [symb_width-1:0] adc_increased_bits = {{symb_width-adc_bitdepth{1'b0}}, signal};
    wire signed [symb_width-1:0] adc_offset = adc_increased_bits - 14'h0800;
    
    
    wire signed [symb_width-1:0] upsample_out;
    
    Upsample #(
        .OUT_RATE(spl_rate),
        .IN_RATE(adc_spl_rate),
        .SYMBOL_WIDTH(symb_width)
    ) adc_samplerate_converter (
        .clk(clk),
        .en(1),
        .new_sample(new_sample),
        .rst(0),
        .i_sample(adc_offset),
        .o_sample(upsample_out)
    );
    
    wire signed [symb_width-1:0] filtered_adc;
    
    FIR #(
        .SYMBOL_WIDTH(symb_width),
        .SYMBOL_FRAC(symb_frac),
        .FILT_TAPS(12),
        .memfile("upsample_lp.mem")
    ) ADC_filter (
        .clk(clk),
        .en(en),
        .rst(rst),
        .new_sample(new_sample),
        .i_sample(upsample_out),
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
    
    wire signed[symb_width-1:0] agc_out;
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
        .dB_THRESH(-30)
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
    
    
    
    reg dly_new_sample = 0;
    
    always @ ( posedge clk ) dly_new_sample <= new_sample;
    
    wire signed [symb_width-1:0] unfiltered_in_phase;
    Costas_Loop #(
        .SYMBOL_WIDTH(symb_width),
        .SYMBOL_FRAC(symb_frac),
//        .SAMPLE_RATE(spl_rate),
        .CARRIER_FRQ($itor(carrier_frq - (carrier_frq * 0.03))),
//        .CARRIER_FRQ(carrier_frq),
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
        .rst(rst),
        .in_sample(unfiltered_in_phase),
        .out_sample(filtered_in_phase)
    );
    
    
    wire signed [13:0] symbol;
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
    
    task write_m_axis (input string s);
        for ( int i = 0; i < s.len(); i++ ) begin
            m_axis_tdata = {24'b0, s[i]};
            m_axis_tvalid = 1;
            m_axis_tlast = i == (s.len() - 1);
            while ( m_axis_tvalid ) #1;
        end
    endtask
    
    initial begin
        
        write_m_axis("hello world!");
        
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
