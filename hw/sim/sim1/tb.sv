`timescale 1ns / 1ps
`define HALF_PERIOD 5
module tb();

    parameter symb_width = 20;
    parameter symb_frac = 16;
    parameter clk_freq = 100_000_000;
    parameter spl_rate = 5_000_000;
    parameter carrier_frq = 1_000_000;
    parameter baud_rate = 50_000;
    parameter sync_len = 16;
    parameter order = 4;

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
    
    
    wire new_symbol;
    wire [$clog2(order)-1:0] rx_symbol;
    wire interrupt;
    
    Controller #(
        .DWIDTH(symb_width),
        .DFRAC(symb_frac),
        .SAMPLE_RATE(spl_rate),
        .SYMBOL_RATE(baud_rate),
        .MODULATION_ORDER(order),
        .EQ_LEN(sync_len)
        
    ) UUT1 (
        .clk(clk),
        .en(en),
        .rst(rst),
        .start(start),
        .new_sample(new_sample),
        .I(sym_gen_I),
        .Q(sym_gen_Q),
        
        .s_axis_tdata(m_axis_tdata),
        .s_axis_tlast(m_axis_tlast),
        .s_axis_tvalid(m_axis_tvalid),
        .s_axis_tready(m_axis_tready),
        
        .m_axis_tdata(s_axis_tdata),
        .m_axis_tlast(s_axis_tlast),
        .m_axis_tvalid(s_axis_tvalid),
        .m_axis_tready(s_axis_tready),
        
        .new_symbol(new_symbol),
        .rx_symbol(rx_symbol),
        .interrupt(interrupt)
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
    
    
    
    wire signed [symb_width-1:0] rx_signal = (signal - 12'hA00) <<< (symb_width - 12);

    wire signed [symb_width-1:0] rx_filt_out;
    IIR #(
        .DWIDTH(symb_width),
        .DFRAC(symb_frac),
        .SOS(7),
        .COEFFICIENTS("rx_iir.mem")
    ) rx_filter (
        .clk(clk),
        .en(en),
        .rst(rst),
        .new_sample(new_sample),
        .filt_in(rx_signal),
        .filt_out(rx_filt_out)
    );


    wire signal_detected;
    signal_detector #(
        .SYMBOL_WIDTH(symb_width),
        .SYMBOL_FRAC(symb_frac),
        .N(64),
        .dB_THRESH(-30)
    ) signal_power_detector (
        .clk(clk), .en(en), .rst(rst),
        .new_sample(new_sample),
        .sample(rx_filt_out),
        .signal_detected(signal_detected)
    );
    
    wire signed [symb_width-1:0] I_rx, Q_rx;
    
    CORDIC_DEMOD #(
        .DWIDTH(symb_width),
        .DFRAC(symb_frac),
        .SAMPLE_RATE(spl_rate),
        .CARRIER_FRQ($rtoi($itor(carrier_frq) * 1.0005))
    ) cordic_demodulator (
        .clk(clk), .en(en), .rst(rst),
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
    
    
    
    wire signed [symb_width-1:0] I_eq, Q_eq;
    
    Sampler #(
        .DWIDTH(symb_width),
        .DFRAC(symb_frac),
        .MOD_ORDER(order)
    ) symbol_aware_sampler (
        .clk(clk), .en(en), .rst(rst),
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
    
    wire signed [symb_width:0] mag;
    wire signed [19:0] phase;
    wire vec_valid;
    
    CORDIC_VEC #(
        .DWIDTH(symb_width),
        .DFRAC(symb_frac),
        .PWIDTH(20),
        .DELAY(19)
    ) cordic_vectoring_mode (
        .clk(clk), .en(en), .rst(rst),
        .start(new_rx_sample),
        .x_in(I_eq),
        .y_in(Q_eq),
        .phase(phase),
        .magnitude(mag),
        .valid(vec_valid)
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
        
        write_m_axis("A message that is nontrivial in size!!!");
        
        #3_000_000 start = 1; 
        #10 start = 0;
    end
    
endmodule
