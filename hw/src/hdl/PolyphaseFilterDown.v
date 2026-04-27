module PolyphaseFilterDown #(
    parameter DWIDTH = 10,
    parameter DFRAC = 8,
    parameter ORDER = 1001,
    parameter COEFILE = "rrc.mem",
    parameter DN = 10
) (
    input clk, en, rst,
    input new_sample,
    input [DWIDTH-1:0] in_sample,
    output reg [DWIDTH-1:0] out_sample,
    output reg new_rx_sample
);

    localparam SPAN = (ORDER/DN) + 1;
    
    reg [$clog2(DN)-1:0] idx = 0;
    reg [$clog2(SPAN)-1:0] jdx = 0;


    reg signed [DWIDTH-1:0] inputs [0:SPAN-1];

    reg signed [DWIDTH-1:0] bank_inputs [0:SPAN-1];

    reg signed [DWIDTH-1:0] mult_in_a [0:DN-1], mult_in_b [0:DN-1];
    wire signed [(DWIDTH*2)-1:0] mult_out [0:DN-1];
    reg signed  [(DWIDTH*2)-1:0] sum [0:DN-1];

    reg signed [(DWIDTH*2)-1:0] sum_in [0:DN-1];
    reg signed [(DWIDTH*2)-1:0] total = 0;

    wire signed [(DWIDTH*2)-1:0] res = total >>> (DFRAC - ($clog2(SPAN)-1));

    reg pipe_in = 0;
    reg reset_pipe = 0;

    localparam PIPELEN = 7;

    genvar g;
    generate
        for ( g = 0; g < DN; g = g + 1 ) begin
            PipeMult #(
                .WIDTH_A(DWIDTH),
                .WIDTH_B(DWIDTH),
                .PIPELEN(PIPELEN)
            ) multiplier (
                .clk(clk),
                .rst(rst),
                .en(en),
                .a(mult_in_a[g]),
                .b(mult_in_b[g]),
                .r(mult_out[g])
            );
        end
    endgenerate

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

    reg signed [DWIDTH-1:0] taps [0:SPAN-1][0:DN-1];
    integer i, j;
    initial begin
        for ( i = 0; i < DN; i = i + 1 ) begin
            mult_in_a[i] = 0;
            mult_in_b[i] = 0;
            sum[i] = 0;
            sum_in[i] = 0;
        end
        for ( i = 0; i < SPAN; i = i + 1 ) begin
            inputs[i] = 0;
            bank_inputs[i] = 0;
            for ( j = 0; j < DN; j = j + 1 ) begin
                taps[i][j] = 0;
            end
        end
        $readmemb(COEFILE, taps);
        out_sample = 0;
        new_rx_sample = 0;
    end

    always @ ( posedge clk ) begin
        if ( rst ) begin
            idx <= 0;
            jdx <= 0;
            for ( i = 0; i < DN; i = i + 1 ) begin
                mult_in_a[i] = 0;
                mult_in_b[i] = 0;
                sum[i] = 0;
                sum_in[i] = 0;
            end
            pipe_in <= 0;
            reset_pipe <= 0;
            total <= 0;
            for ( i = 0; i < SPAN; i = i + 1 ) begin
                inputs[i] <= 0;
                bank_inputs[i] <= 0;
            end
            out_sample <= 0;
            new_rx_sample <= 0;
        end
        else if ( en ) begin
            reset_pipe <= 0;
            new_rx_sample <= 0;
            if ( new_sample ) begin
                inputs[0] <= in_sample;
                for ( i = 1; i < SPAN; i = i + 1 ) begin
                    inputs[i] <= inputs[i-1];
                end
                
                if ( idx == DN - 1 ) begin
                    idx <= 0;
                    out_sample <= res[DWIDTH-1:0];
                    new_rx_sample <= 1;
                    total <= 0;
                    for ( i = 0; i < DN; i = i + 1 ) begin
                        bank_inputs[i] <= inputs[i];
                        sum_in[i] <= sum[i];
                        sum[i] <= 0;
                    end
                    jdx <= 0;
                    pipe_in <= 0;
                    reset_pipe <= 1;
                end
                else begin
                    idx <= idx + 1;
                end

            end
            else begin
                for ( i = 0; i < DN; i = i + 1 ) begin
                    mult_in_a[i] <= bank_inputs[jdx];
                    mult_in_b[i] <= taps[jdx][i];
                end
                if ( jdx < SPAN ) begin
                    pipe_in <= 1;
                    jdx <= jdx + 1;
                end
                else begin
                    pipe_in <= 0;
                end
                
                if ( pipe_out ) begin
                    // if multiplier output is valid, accumulate
                    for ( i = 0; i < DN; i = i + 1 ) begin
                        sum[i] <= sum[i] + mult_out[i];
                    end
                end

                // Second additional stage for summing the intermediate sums
                if ( jdx < DN ) begin
                    total <= total + sum_in[jdx];
                    jdx <= jdx + 1;
                end

                // Due to nonblocking assignment, jdx is incremented if either 
                // of the jdx conditions are met, which is the desired 
                // behaviour. Importantly, the conditions are mainly there to 
                // ensure that the multiplication and addition operations are
                // only performed over a valid range
            end
        end
    end



endmodule