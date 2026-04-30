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
    
    integer idx = 0;
    integer jdx = 0;


    reg signed [DWIDTH-1:0] inputs [0:DN-1];

    reg signed [DWIDTH-1:0] bank_inputs [0:DN-1][0:SPAN-1];

    reg signed [DWIDTH-1:0] mult_in_a [0:DN-1], mult_in_b [0:DN-1];
    wire signed [(DWIDTH*2)-1:0] mult_out [0:DN-1];
    reg signed  [(DWIDTH*2)-1:0] acc [0:DN-1];

    reg signed [(DWIDTH*2)-1:0] sum_in [0:DN-1];
    reg signed [(DWIDTH*2)-1:0] total = 0;

    wire signed [(DWIDTH*2)-1:0] res = total >>> (DFRAC - ($clog2(SPAN)-1));

    reg pipe_in = 0;

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
        .rst(rst),
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
            acc[i] = 0;
            sum_in[i] = 0;
            inputs[i] = 0;
            for ( j = 0; j < SPAN; j = j + 1 ) begin
                bank_inputs[i][j] = 0;
                taps[j][i] = 0;
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
                acc[i] = 0;
                sum_in[i] = 0;
                inputs[i] <= 0;
                for ( j = 0; j < SPAN; j = j + 1 ) begin
                    bank_inputs[i][j] = 0;
                end
            end
            pipe_in <= 0;
            total <= 0;
            out_sample <= 0;
            new_rx_sample <= 0;
        end
        else if ( en ) begin
            // FAST DOMAIN
            if ( new_sample ) begin
                inputs[0] <= in_sample;
                for ( i = 1; i < DN; i = i + 1 ) begin
                    inputs[i] <= inputs[i-1];
                end
            end
            
            // SLOW DOMAIN
            if ( new_sample ) begin
                if ( idx == DN - 1 ) begin
                    idx <= 0;
                    // Samples in slow domain happen every DN samples of fast
                    // domain.
                    jdx <= 0;
                    total <= 0;
                    out_sample <= total;
                    for ( i = 0; i < DN; i = i + 1 ) begin
                        bank_inputs[i][0] <= inputs[i];
                        for ( j = 1; j < SPAN; j = j + 1 ) begin
                            bank_inputs[i][j] <= bank_inputs[i][j-1];
                        end
                        sum_in[i] <= acc[i];
                        acc[i] <= 0;
                    end
                    new_rx_sample <= 1;
                end
                else begin
                    idx <= idx + 1;
                end
            end 
            else begin
                new_rx_sample <= 0;
                if ( jdx < SPAN || jdx < DN ) begin
                    jdx <= jdx + 1;
                end

                if ( jdx < SPAN ) begin
                    pipe_in <= 1;
                    for ( i = 0; i < DN; i = i + 1 ) begin
                        mult_in_a[i] <= bank_inputs[i][jdx];
                        mult_in_b[i] <= taps[jdx][i];
                    end
                end 
                else begin
                    pipe_in <= 0;
                end
                if ( pipe_out ) begin
                    for ( i = 0; i < DN; i = i + 1 ) begin
                        acc[i] <= acc[i] + (mult_out[i] >>> DFRAC);
                    end
                end

                if ( jdx < DN ) begin
                    total <= total + sum_in[jdx];
                end
                
            end

        end
    end



endmodule