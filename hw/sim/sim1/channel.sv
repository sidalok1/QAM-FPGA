`timescale 1ns / 1ps

module channel
#(
    parameter ifreq = 100_000_000,
    parameter splr = 5_000_000,
    parameter DELAY = 1
)
(
    input wire clk,
    input wire [7:0] dac_data,
    input wire adc_clk,
    output reg [11:0] adc_data,
    output reg adc_ovf
    );
    
    wire new_sample;
    clockdiv
    #(
        .I_CLK_FRQ(ifreq),
        .FREQUENCY(splr)
    ) sample_rate_generator (
        .rst(0),
        .en(1),
        .i_clk(clk),
        .o_clk(new_sample)
    );
    
    localparam real dac_scale_factor = 3.3 / $itor(8'hFF);
    
    integer seed = 0;
    localparam real maxint = $itor(32'hEF_FF_FF_FF);
    integer stdev = $rtoi(maxint * 0.003);    
    function real awgn();
        return $dist_normal(seed, 0, stdev)/maxint;
    endfunction
    real clipping;
    function [11:0] adc(input real spl);
        clipping = spl < 0 ? 0 : spl;
        clipping = clipping > 3.3 ? 3.3 : clipping;
        return $rtoi((clipping / 3.3) * 12'hFFF);
    endfunction

    function [0:0] ovf(input real spl);
        return spl < 0 || spl > 3.3;
    endfunction
    
    
    real dly [0:DELAY];
    integer i;
    initial begin
        adc_data = 0;
        adc_ovf = 0;
        for ( i = 0; i <= DELAY; i++ )
            dly[i] = 0;
    end
    
    real dac_output = 0;
    
    //  Discrete transfer function numerator coefficients
    real a1 = 0.03349282;
    real a2 = 0;
    real a3 = -0.03349282;
    //  Discrete transfer function denominator coefficients
//    real b1 = 1;
    real b2 = -1.89473684;
    real b3 = 0.93301435;
    
    real w1 = 0;
    real w2 = 0;
    
    real x = 0;
    real y = 0;
    always @ ( posedge clk ) if ( new_sample ) begin
        x = ($itor(dac_data) * dac_scale_factor) - 1.65;
        y = (a1 * x) + w1;
        w1 = (a2 * x) + w2 - (b2 * y);
        w2 = (a3 * x) - (b3 * y);
        dly[0] = y;
        for ( int i = DELAY; i > 0; i-- ) begin
            dly[i] = dly[i-1];
        end
        
    end

    real out_spl = 0;

    always @ ( posedge adc_clk ) begin
        out_spl = (dly[DELAY] * 15) + 1.4 + awgn();
        adc_data = adc(out_spl);
        adc_ovf = ovf(out_spl);
    end
    
endmodule
