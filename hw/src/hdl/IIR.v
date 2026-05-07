// Coefficients must be specified as second order sections

module IIR #(
    parameter DWIDTH = 20,
    parameter DFRAC = 16,
    parameter SOS = 1,
    parameter COEFFICIENTS = "rx_iir.mem"
)(
    input wire clk, en, rst,
    input wire new_sample,
    input wire signed [DWIDTH-1:0] filt_in,
    output wire signed [DWIDTH-1:0] filt_out
);

    wire signed [DWIDTH-1:0] b [0:SOS-1][0:2], a [0:SOS-1][0:2]; 
    reg signed [DWIDTH-1:0] x [0:SOS-1][0:2], y [0:SOS-1][0:2];

    reg signed [DWIDTH-1:0] mul_a [0:SOS-1], mul_b [0:SOS-1];
    wire signed [(DWIDTH*2)-1:0] mul_o [0:SOS-1];

    wire signed [DWIDTH-1:0] stage_in [0:SOS-1];
    
    localparam PIPELEN = 7;
    genvar g, h;

    

    reg [2:0] idx = 0;
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

    reg [DWIDTH-1:0] coe [0:(SOS*6)-1];
    
    generate
        assign stage_in[0] = filt_in;
        for ( g = 0; g < SOS; g = g + 1 ) begin
            // reg signed [DWIDTH-1:0] coe_a [0:2], coe_b[0:2];
            // initial begin
            //     $readmemb(COEFFICIENTS, coe_b, g*6, (g*6)+2);
            //     $readmemb(COEFFICIENTS, coe_a, (g*6)+3, (g*6)+5);
            // end
            assign b[g][0] = coe[(g*6)];
            assign b[g][1] = coe[(g*6)+1];
            assign b[g][2] = coe[(g*6)+2];
            assign a[g][0] = coe[(g*6)+3];
            assign a[g][1] = coe[(g*6)+4];
            assign a[g][2] = coe[(g*6)+5];

            PipeMult #(
                .WIDTH_A(DWIDTH),
                .WIDTH_B(DWIDTH),
                .PIPELEN(PIPELEN)
            ) multiplier (
                .clk(clk), .en(en), .rst(rst),
                .a(mul_a[g]), .b(mul_b[g]),
                .r(mul_o[g])
            );
            if ( g != 0 )
                assign stage_in[g] = y[g-1][1];
        end
        assign filt_out = y[SOS-1][1];
    endgenerate

    integer i;

    initial begin
        $readmemb(COEFFICIENTS, coe);
        for ( i = 0; i < SOS; i = i + 1 ) begin
            
            // $readmemb(COEFFICIENTS, b[i], i*6, (i*6) + 2);
            // $readmemb(COEFFICIENTS, a[i], (i*6) + 3, (i*6) + 5);

            // b[i][0] = coe[i][0];
            // b[i][1] = coe[i][1];
            // b[i][2] = coe[i][2];

            // a[i][0] = coe[i][3];
            // a[i][1] = coe[i][4];
            // a[i][2] = coe[i][5];

            x[i][0] = 0;
            x[i][1] = 0;
            x[i][2] = 0;

            y[i][0] = 0;
            y[i][1] = 0;
            y[i][2] = 0;

            mul_a[i] = 0;
            mul_b[i] = 0;
        end
    end

    always @ ( posedge clk ) begin
        if ( rst ) begin
            for ( i = 0; i < SOS; i = i + 1 ) begin
                x[i][0] <= 0;
                x[i][1] <= 0;
                x[i][2] <= 0;

                y[i][0] <= 0;
                y[i][1] <= 0;
                y[i][2] <= 0;

                mul_a[i] <= 0;
                mul_b[i] <= 0;
            end
            valid_i <= 0;
            idx <= 0;
        end
        else if ( en ) begin
            if ( new_sample ) begin
                idx <= 0;
                valid_i <= 0;
                for ( i = 0; i < SOS; i = i + 1 ) begin
                    x[i][2] <= x[i][1];
                    x[i][1] <= x[i][0];
                    x[i][0] <= stage_in[i];

                    y[i][2] <= y[i][1];
                    y[i][1] <= y[i][0];
                    y[i][0] <= 0;

                    mul_a[i] <= 0;
                    mul_b[i] <= 0;
                end
            end
            else begin
                case ( idx )
                0, 1, 2: begin
                    for ( i = 0; i < SOS; i = i + 1 ) begin
                        mul_a[i] <= x[i][idx];
                        mul_b[i] <= b[i][idx];
                    end
                    valid_i <= 1;
                    idx <= idx + 1;
                end
                3, 4: begin
                    for ( i = 0; i < SOS; i = i + 1 ) begin
                        mul_a[i] <= y[i][idx-2];
                        mul_b[i] <= a[i][idx-2] * -1;
                    end
                    valid_i <= 1;
                    idx <= idx + 1;
                end
                default: begin
                    valid_i <= 0;
                    idx <= idx;
                end
                endcase

                if ( valid_o ) begin
                    for ( i = 0; i < SOS; i = i + 1 ) begin
                        y[i][0] <= y[i][0] + (mul_o[i] >>> DFRAC);
                    end
                end
            end
        end
    end

endmodule
