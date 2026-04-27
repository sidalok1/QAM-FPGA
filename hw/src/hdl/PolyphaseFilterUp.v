/*
Multicycle implementation of an upsampling polyphase fir filter. In order for 
this module to function properly it should be ensured that there are more
than SPAN + PIPELEN clock cycles in between each output sample
*/

module PolyphaseFilterUp #(
    parameter DWIDTH = 10,
    parameter DFRAC = 8,
    parameter ORDER = 1001,
    parameter COEFILE = "rrc.mem",
    parameter SPS = 100
) (
    input clk, en, rst,
    input new_sample,
    input [DWIDTH-1:0] in_sample,
    output reg [DWIDTH-1:0] out_sample
);

    localparam SPAN = (ORDER/SPS) + 1;
    
    reg [$clog2(SPS)-1:0] idx = 0;
    reg [$clog2(SPAN)-1:0] jdx = 0;


    reg signed [DWIDTH-1:0] inputs [0:SPAN-1];

    reg signed [DWIDTH-1:0] mult_in_a = 0, mult_in_b = 0;
    wire signed [(DWIDTH*2)-1:0] mult_out;
    reg signed  [(DWIDTH*2)-1:0] sum = 0;
    wire signed [(DWIDTH*2)-1:0] res = sum >>> DFRAC;

    reg pipe_in = 0;
    reg reset_pipe = 0;

    localparam PIPELEN = 7;

    PipeMult #(
        .WIDTH_A(DWIDTH),
        .WIDTH_B(DWIDTH),
        .PIPELEN(PIPELEN)
    ) multiplier (
        .clk(clk),
        .rst(rst),
        .en(en),
        .a(mult_in_a),
        .b(mult_in_b),
        .r(mult_out)
    );

    wire pipe_out;

    PipeSignal #(
        .DWIDTH(1),
        .PIPELEN(PIPELEN)
    ) signal_pipe (
        .clk(clk),
        .rst(rst | reset_pipe),
        .en(en),
        .i(pipe_in),
        .o(pipe_out)
    );

    reg signed [DWIDTH-1:0] taps [0:SPAN-1][0:SPS-1];
    integer i, j;
    initial begin
        for ( i = 0; i < SPAN; i = i + 1 ) begin
            inputs[i] = 0;
            for ( j = 0; j < SPS; j = j + 1 ) begin
                taps[i][j] = 0;
            end
        end
        $readmemb(COEFILE, taps);
        out_sample = 0;
    end

    always @ ( posedge clk ) begin
        if ( rst ) begin
            idx <= 0;
            jdx <= 0;
            mult_in_a <= 0;
            mult_in_b <= 0;
            pipe_in <= 0;
            reset_pipe <= 0;
            sum <= 0;
            for ( i = 0; i < SPAN; i = i + 1 ) begin
                inputs[i] <= 0;
            end
            out_sample <= 0;
        end
        else if ( en ) begin
            reset_pipe <= 0;
            if ( new_sample ) begin
                jdx <= 0;
                pipe_in <= 0;
                reset_pipe <= 1;
                out_sample <= res[DWIDTH-1:0] * (SPAN-1);
                sum <= 0;
                if ( idx == SPS - 1 ) begin
                    idx <= 0;
                    inputs[0] <= in_sample;
                    for ( i = 1; i < SPAN; i = i + 1 ) begin
                        inputs[i] <= inputs[i-1];
                    end
                end
                else begin
                    idx <= idx + 1;
                end
            end
            else begin
                // by default, accumulator assume multiplier has invalid output
                pipe_in <= 0;
                if ( jdx < SPAN ) begin
                    mult_in_a <= inputs[jdx];
                    mult_in_b <= taps[jdx][idx];
                    // signal to accumulator multiplier has valid output
                    pipe_in <= 1; 
                    jdx <= jdx + 1;
                end
                if ( pipe_out ) begin
                    // if multiplier output is valid, accumulate
                    sum <= sum + mult_out;
                end
            end
        end
    end



endmodule