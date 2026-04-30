module PipeMult
#(
    parameter WIDTH_A = 16,
    parameter WIDTH_B = 16,
    parameter PIPELEN = 2
)
(
    input wire clk, rst, en,
    input wire signed [WIDTH_A-1:0] a,
    input wire signed [WIDTH_B-1:0] b,
    output wire signed [(WIDTH_A+WIDTH_B)-1:0] r
);

    reg signed [(WIDTH_A+WIDTH_B)-1:0] p [0:PIPELEN-1];
    assign r = p[PIPELEN-1];
    integer i;
    initial begin
        for ( i = 0; i < PIPELEN; i = i + 1 ) begin
            p[i] = 0;
        end
    end
    always @ ( posedge clk ) begin
        if ( rst ) begin
            for ( i = 0; i < PIPELEN; i = i + 1) begin
                p[i] <= 0;
            end
        end else
        if ( en ) begin
            p[0] <= a * b;
            for ( i = 0; i < PIPELEN - 1; i = i + 1) begin
                p[i+1] <= p[i];
            end
        end
    end

endmodule

module PipeMultC #(
    parameter DWIDTH = 20,
    parameter DFRAC = 16,
    parameter PIPELEN = 10
)
(
    input wire clk, rst, en,
    input wire signed [DWIDTH-1:0] x_r, x_i, y_r, y_i,
    output wire signed [DWIDTH-1:0] z_r, z_i
);

    reg signed [DWIDTH-1:0] x_dif = 0, y_dif = 0, y_sum = 0;
    reg signed [(DWIDTH*2)-1:0] xr_prod = 0, xi_prod = 0, yi_prod = 0;
    reg signed [DWIDTH-1:0] z_real = 0, z_imag = 0;

    reg signed [DWIDTH-1:0] zr_pipe [0:PIPELEN-1], zi_pipe [0:PIPELEN-1];
    integer i;
    initial begin
        for ( i = 0; i < PIPELEN; i = i + 1 ) begin
            zr_pipe[i] = 0;
            zi_pipe[i] = 0;
        end
    end

    assign z_r = zr_pipe[PIPELEN-1];
    assign z_i = zi_pipe[PIPELEN-1];

    always @* begin
        // Make sure to enable global retiming in synthesis
        x_dif = x_r - x_i;
        y_dif = y_r - y_i;
        y_sum = y_r + y_i;

        xr_prod <= (x_r * y_dif);
        xi_prod <= (x_i * y_sum);
        yi_prod <= (y_i * x_dif);

        z_real <= (xr_prod >>> DFRAC) + (yi_prod >>> DFRAC);
        z_imag <= (xi_prod >>> DFRAC) + (yi_prod >>> DFRAC);
    end

    always @ ( posedge clk ) begin
        if ( rst ) begin
            for ( i = 0; i < PIPELEN; i = i + 1 ) begin
                zr_pipe[i] <= 0;
                zi_pipe[i] <= 0;
            end
        end
        else if ( en ) begin
            zr_pipe[0] <= z_real;
            zi_pipe[0] <= z_imag;
            for ( i = 1; i < PIPELEN; i = i + 1 ) begin
                zr_pipe[i] <= zr_pipe[i-1];
                zi_pipe[i] <= zi_pipe[i-1];
            end
        end
    end

endmodule