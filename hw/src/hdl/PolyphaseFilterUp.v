/*
Multicycle implementation of an upsampling polyphase fir filter. In order for 
this module to function properly it should be ensured that there are more
than ORDER/UP clock cycles in between each output sample, and that ORDER is
evenly divisible by UP
*/

module PolyphaseFilterUp #(
    parameter DWIDTH = 10,
    parameter DFRAC = 8,
    parameter ORDER = 900,
    parameter COEFILE = "rrc.mem",
    parameter UP = 100,
    parameter PIPELEN = 2
) (
    input clk, en, rst,
    input new_sample,
    input [DWIDTH-1:0] in_sample,
    output reg [DWIDTH-1:0] out_sample
);

    localparam SPAN = (ORDER/UP);
    
    reg [$clog2(UP)-1:0] idx = 0;
    reg [$clog2(SPAN):0] jdx = 0;
    reg [$clog2(SPAN):0] kdx = 0;


    reg signed [DWIDTH-1:0] inputs [0:SPAN-1];

    reg signed [DWIDTH-1:0] mult_in_a = 0, mult_in_b = 0;
    wire signed [(DWIDTH*2)-1:0] mult_out;
    reg signed  [(DWIDTH*2)-1:0] sum = 0;

    reg pipe_in = 0;


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
        .rst(rst),
        .en(en),
        .i(pipe_in),
        .o(pipe_out)
    );

    wire signed [(DWIDTH*2)-1:0] sum_next = sum + mult_out;
    wire signed [(DWIDTH*2)-1:0] res = sum_next >>> (DFRAC - ($clog2(SPAN)));

    // reg signed [DWIDTH-1:0] taps [0:SPAN-1][0:UP-1];
    reg signed [DWIDTH-1:0] taps [0:(SPAN*UP)-1];
    integer i, j;
    initial begin
        for ( i = 0; i < SPAN; i = i + 1 ) begin
            inputs[i] = 0;
            // for ( j = 0; j < UP; j = j + 1 ) begin
            //     taps[(i*UP)+j] = 0;
            // end
            // $readmemb(COEFILE, taps[i], (i*UP), (i*UP)+UP-1);
        end
        
        $readmemb(COEFILE, taps);
        out_sample = 0;
    end

    always @ ( posedge clk ) begin
        if ( rst ) begin
            idx <= 0;
            jdx <= 0;
            kdx <= 0;
            mult_in_a <= 0;
            mult_in_b <= 0;
            pipe_in <= 0;
            sum <= 0;
            for ( i = 0; i < SPAN; i = i + 1 ) begin
                inputs[i] <= 0;
            end
            out_sample <= 0;
        end
        else if ( en ) begin
            if ( new_sample ) begin
                mult_in_a <= in_sample;
                mult_in_b <= taps[idx];
                pipe_in <= 1;
                jdx <= 1;
                if ( idx == UP - 1 ) begin
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
                pipe_in <= 0;
                if ( jdx < SPAN ) begin
                    mult_in_a <= inputs[jdx];
                    mult_in_b <= taps[(jdx*UP)+idx];
                    jdx <= jdx + 1;
                end
                else begin
                    mult_in_a <= 0;
                    mult_in_b <= 0;
                end
            end
        end

        if ( pipe_out ) begin
            kdx <= 0;
            sum <= mult_out;
            out_sample <= res[DWIDTH-1:0];
        end 
        else begin
            if ( kdx < SPAN-1 ) begin
                sum <= sum_next;
            end
        end
    end



endmodule