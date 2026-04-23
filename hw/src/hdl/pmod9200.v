module PMOD9200 #(
    parameter I_CLK_FRQ = 96_000_000,
    parameter S_CLK_FRQ = 6_000_000,
    parameter DWIDTH    = 16,
    parameter DFRAC     = 14
) (
    input wire clk, en, rst,
    input wire [9:0] adc_din,
    output reg [DWIDTH-1:0] dout,
    output reg adc_clk,
    output reg adc_n_en,
    output reg adc_shdn
);

    localparam ADC_CLK_GEN_FRQ = S_CLK_FRQ * 2;

    localparam SHIFT_AMT = DWIDTH - 10;

    wire clk_gen_en;

    reg [9:0] din;
    reg [9:0] s_din;

    clockdiv #(
        .I_CLK_FRQ(I_CLK_FRQ),
        .FREQUENCY(ADC_CLK_GEN_FRQ)
    ) adc_clk_gen (
        .rst(rst),
        .i_clk(clk),
        .en(en),
        .o_clk(clk_gen_en)
    );

    initial begin
        adc_clk <= 0;
        adc_n_en <= 0;
        adc_shdn <= 0;
        dout <= 0;
        din <= 0;
        s_din <= 0;
    end

    always @ ( posedge clk ) 
        if ( rst ) begin
            dout <= 0;
            din <= 0;
            s_din <= 0;
        end
        else if ( en ) begin
            if ( clk_gen_en ) begin
                if ( ~adc_clk )
                    din <= adc_din; // posedge sampling
                adc_clk <= ~adc_clk;
            end
            s_din <= din + {1'b1, 9'b0}; // signed to unsigned
            dout <= s_din << SHIFT_AMT;
        end

endmodule