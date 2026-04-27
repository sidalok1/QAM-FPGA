module IIR #(
    parameter DWIDTH = 18,
    parameter DFRAC = 16,
    parameter ORDER = 2,
    parameter NUM_COE = "iir_num.mem",
    parameter DEN_COE = "iir_den.mem",
    parameter PIPELEN = 7
)
(
    input wire clk, en, rst,
    input wire new_sample,
    input wire [DWIDTH-1:0] filt_in,
    output wire [DWIDTH-1:0] filt_out
);


    reg signed [DWIDTH-1:0] num [0:ORDER];
    reg signed [DWIDTH-1:0] den [0:ORDER];

    reg signed [DWIDTH-1:0] x [0:ORDER];
    reg signed [DWIDTH-1:0] y [0:ORDER];
    reg signed [(2*DWIDTH)-1:0] y0 = 0;

    assign filt_out = y[1];

    reg [$clog2(ORDER):0] idx = 0;
    reg [$clog2(ORDER):0] jdx = 1;

    integer i, j;

    reg signed [DWIDTH-1:0] mult_in_a = 0, mult_in_b = 0;
    wire signed [(2*DWIDTH)-1:0] mult_out;
    wire signed [(2*DWIDTH)-1:0] mult_res = y0 >>> DFRAC;

    reg mult_valid_i = 0;
    wire mult_valid_o;

    PipeMult #(
        .WIDTH_A(DWIDTH),
        .WIDTH_B(DWIDTH),
        .PIPELEN(PIPELEN)
    ) multiplier (
        .clk(clk), .en(en), .rst(rst),
        .a(mult_in_a),
        .b(mult_in_b),
        .r(mult_out)
    );

    PipeSignal #(
        .DWIDTH(1),
        .PIPELEN(PIPELEN)
    ) signal_pipe (
        .clk(clk), .en(en), .rst(rst | new_sample),
        .i(mult_valid_i),
        .o(mult_valid_o)
    );

    initial begin
        $readmemb(NUM_COE, num);
        $readmemb(DEN_COE, den);
        // it is (for now) assumed, but not checked, that den[0] = 1
        for ( i = 0; i <= ORDER; i = i + 1 ) begin
            x[i] = 0;
        end
        for ( j = 0; j <= ORDER; j = j + 1 ) begin
            y[j] = 0;
        end
    end

    always @ ( posedge clk ) begin
        if ( rst ) begin
            for ( i = 0; i <= ORDER; i = i + 1 ) begin
                x[i] <= 0;
            end
            for ( j = 0; j <= ORDER; j = j + 1 ) begin
                y[j] <= 0;
            end
            idx <= 0;
            jdx <= 1;
            mult_in_a <= 0;
            mult_in_b <= 0;
            mult_valid_i <= 0;
            y0 <= 0;
        end
        else if ( en ) begin
            mult_valid_i <= 0;
            if ( new_sample ) begin
                mult_in_a <= 0;
                mult_in_b <= 0;
                idx <= 0;
                jdx <= 1;
                x[0] <= filt_in;
                y0 <= 0;
                for ( i = 1; i <= ORDER; i = i + 1 ) begin
                    x[i] <= x[i-1];
                end
                y[1] <= y0[DWIDTH-1:0];
                for ( j = 2; j <= ORDER; j = j + 1 ) begin
                    y[j] <= y[j-1];
                end
            end
            else if ( idx <= ORDER ) begin
                idx <= idx + 1;
                mult_valid_i <= 1;
                mult_in_a <= x[idx];
                mult_in_b <= num[idx];
            end
            else if ( idx > ORDER && jdx <= ORDER ) begin
                jdx <= jdx + 1;
                mult_valid_i <= 1;
                mult_in_a <= y[jdx];
                mult_in_b <= den[jdx] * -1;
            end

            if ( mult_valid_o ) begin
                y0 <= y0 + (mult_out >>> DFRAC);
            end
        end
    end

endmodule