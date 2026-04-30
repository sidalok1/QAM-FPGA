module FIR
#(
    //  Total word length of the output symbols
    parameter DWIDTH  = 16,
    //  Length of the fractional portion of a signal
    parameter DFRAC   = 14,
    
    //  Following two parameters MUST be defined at instantiation
    
    //  Number of taps in the filter (technically order + 1)
    parameter ORDER    = 0,
    //  Name of the memory file for readmemh directive
    parameter TAPS_FILE       = ""
)
(
    input wire                              clk,
    input wire                              rst,
    input wire                              en,
    input wire                              new_sample,
    
    input wire signed [DWIDTH-1:0]    filt_in,
    
    output reg signed [DWIDTH-1:0]    filt_out
);

    reg signed [DWIDTH-1:0] taps [0:ORDER-1];
    reg signed [DWIDTH-1:0] input_buffer [0:ORDER-1];
    integer idx = 0;
    
    //  Non-synthesized indexing variables
    integer i;

    reg signed [DWIDTH-1:0] mul_a = 0, mul_b = 0;
    wire signed [(2*DWIDTH)-1:0] mul_o;
    reg valid_i = 0;
    wire valid_o;

    localparam PIPELEN = 7;

    PipeMult #(
        .WIDTH_A(DWIDTH),
        .WIDTH_B(DWIDTH),
        .PIPELEN(PIPELEN)
    ) multiplier (
        .clk(clk), .en(en), .rst(rst),
        .a(mul_a), .b(mul_b),
        .r(mul_o)
    );

    PipeSignal #(
        .DWIDTH(1),
        .PIPELEN(PIPELEN)
    ) valid_signal_pipe (
        .clk(clk), .en(en), .rst(rst),
        .i(valid_i),
        .o(valid_o)
    );
    
    reg signed [(DWIDTH*2)-1:0] acc = 0;
    
    localparam [1:0] IDLE   = 'b01;
    localparam [1:0] CALC   = 'b10;
    reg [1:0] state = IDLE;
    
    
    initial begin
        filt_out = 0;
        $readmemb(TAPS_FILE, taps);
        for ( i = 0; i < ORDER; i = i + 1 ) begin
            input_buffer[i] = 0;
        end
    end
    
    always @ ( posedge clk )
    if ( rst ) begin
        filt_out <= 0;
        mul_a <= 0;
        mul_b <= 0;
        acc <= 0;
        valid_i <= 0;
        idx <= 0;
        for ( i = 0; i < ORDER; i = i + 1 ) begin
            input_buffer[i] <= 0;
        end
    end else
    if ( en ) begin
        if ( new_sample ) begin
            input_buffer[0] <= filt_in;
            for ( i = 1; i < ORDER; i = i + 1 ) begin
                input_buffer[i] <= input_buffer[i-1];
            end
            filt_out <= acc;
            acc <= 0;
            idx <= 0;
            mul_a <= 0;
            mul_b <= 0;
            valid_i <= 0;
        end
        else begin
            if ( idx < ORDER ) begin
                mul_a <= input_buffer[idx];
                mul_b <= taps[idx];
                valid_i <= 1;
            end
            else begin
                valid_i <= 0;
            end

            if ( valid_o ) begin
                acc <= acc + (mul_o >>> DFRAC);
            end
        end
    end
    
    
    
endmodule

module FIR_Complex #(
    parameter DWIDTH = 20,
    parameter DFRAC = 16,
    parameter ORDER = 160,
    parameter TAPS_FILE = "zadoff_chu_rc.mem",
    parameter PIPELEN = 15
)
(
    input wire clk, en, rst, new_sample,
    input wire signed [DWIDTH-1:0] i_real, i_imag,
    output reg signed [DWIDTH-1:0] o_real, o_imag
);

    reg signed [DWIDTH-1:0] taps [0:ORDER-1][0:1];
    initial $readmemb(TAPS_FILE, taps);

    reg signed [DWIDTH-1:0] inputs [0:ORDER-1][0:1];
    integer i;
    initial begin
        for ( i = 0; i < ORDER; i = i + 1 ) begin
            inputs[i][0] = 0;
            inputs[i][1] = 0;
        end
    end

    integer idx = 0;

    reg signed [DWIDTH-1:0] xmul_r = 0, xmul_i = 0, ymul_r = 0, ymul_i = 0;
    wire signed [DWIDTH-1:0] zmul_r, zmul_i;

    PipeMultC #(
        .DWIDTH(DWIDTH),
        .DFRAC(DFRAC),
        .PIPELEN(PIPELEN)
    ) complex_multiplier (
        .clk(clk), .en(en), .rst(rst),
        .x_r(xmul_r), .x_i(xmul_i),
        .y_r(ymul_r), .y_i(ymul_i),
        .z_r(zmul_r), .z_i(zmul_i)
    );

    reg valid_i = 0;
    wire valid_o;

    PipeSignal #(
        .DWIDTH(1),
        .PIPELEN(PIPELEN)
    ) valid_signal_pipe (
        .clk(clk), .en(en), .rst(rst),
        .i(valid_i),
        .o(valid_o)
    );

    reg signed [DWIDTH-1:0] sum_r = 0, sum_i = 0;

    always @ ( posedge clk ) begin
        if ( rst ) begin
            o_real <= 0;
            o_imag <= 0;
            sum_r <= 0;
            sum_i <= 0;
            idx <= 0;
            valid_i <= 0;
            for ( i = 0; i < ORDER; i = i + 1 ) begin
                inputs[i][0] <= 0;
                inputs[i][1] <= 0;
            end
        end
        else if ( en ) begin
            if ( new_sample ) begin
                o_real <= sum_r;
                o_imag <= sum_i;
                sum_r <= 0;
                sum_i <= 0;
                idx <= 0;
                valid_i <= 0;
                inputs[0][0] <= i_real;
                inputs[0][1] <= i_imag;
                for ( i = 1; i < ORDER; i = i + 1 ) begin
                    inputs[i][0] <= inputs[i-1][0];
                    inputs[i][1] <= inputs[i-1][1];
                end
            end
            else begin
                if ( idx < ORDER ) begin
                    idx <= idx + 1;
                    xmul_r <= inputs[idx][0];
                    xmul_i <= inputs[idx][1];
                    ymul_r <= taps[idx][0];
                    ymul_i <= taps[idx][1];
                    valid_i <= 1;
                end
                else valid_i <= 0;

                if ( valid_o ) begin
                    sum_r <= sum_r + zmul_r;
                    sum_i <= sum_i + zmul_i;
                end
            end
        end
    end

endmodule