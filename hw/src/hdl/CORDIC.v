module CORDIC_ROT #(
    parameter DWIDTH = 16,
    parameter DFRAC = 12,
    parameter PWIDTH = 16,
    parameter DELAY = 16
) (
    input wire clk, en, rst, start,
    input wire signed [DWIDTH-1:0] x_in, y_in,
    // controller of this module must ensure range of
    // values given in phase are between -pi and pi
    input wire signed [PWIDTH-1:0] phase,
    output reg signed [DWIDTH-1:0] x_out, y_out,
    output reg valid
);

    localparam ITERATIONS = DELAY-1;

    initial begin
        x_out = 0;
        y_out = 0;
        valid = 0;
    end

    localparam PFRAC = PWIDTH - 4;

    reg [$clog2(DELAY)-1:0] idx = 0;

    reg signed [PWIDTH-1:0] cordic_angles [0:ITERATIONS-1];

    localparam signed [PWIDTH-1:0]   PI_1_4 = $rtoi($atan2(1, 1) * 2**(PFRAC));
    localparam signed [PWIDTH-1:0]  PI_3_4 = $rtoi($atan2(1, -1) * 2**(PFRAC));
    localparam signed [PWIDTH-1:0]   PI_1_2 = $rtoi($atan2(1, 0) * 2**(PFRAC));
    localparam signed [PWIDTH-1:0]   PI   = $rtoi($atan2(0, -1) * 2**(PFRAC));

    reg signed [DWIDTH-1:0] K;
    
    integer i;
    real cos_scale;
    real angle;
    initial begin
        cos_scale = 1.0;
        for ( i = 0; i < ITERATIONS; i = i + 1 ) begin
            angle = $atan($pow(2, -1*i));
            cos_scale = cos_scale * $cos(angle);
            cordic_angles[i] = $rtoi(angle * 2**(PFRAC));
        end
        K = $rtoi(cos_scale * 2**(DFRAC));
    end


    reg signed [PWIDTH-1:0] requested_phase = 0, current_phase = 0;
    // angle increment is positive (sigma == 1) if current phase is less than
    // the requested phase
    wire sigma = current_phase < requested_phase;

    // Precision is doubled to avoid truncation effects
    reg signed [DWIDTH:0] x = 0, y = 0;

    wire signed [(DWIDTH*2)-1:0] scale_x, scale_y;
    assign scale_x = (x * K) >>> DFRAC;
    assign scale_y = (y * K) >>> DFRAC;

    reg [2:0] cond = 0;

    always @( posedge clk ) begin
        if ( rst ) begin
            x_out <= 0;
            y_out <= 0;
            valid <= 0;
            idx <= 0;
            requested_phase <= 0;
            current_phase <= 0;
            x <= 0;
            y <= 0;
        end
        else if ( en ) begin
            if ( start ) begin
                idx <= 0;
                current_phase <= 0;
                valid <= 0;
                if ( phase >= PI_3_4 ) begin
                    cond <= 1;
                    requested_phase <= phase - PI;
                    x <= x_in * -1;
                    y <= y_in * -1;
                end
                else if ( phase < PI_3_4 && phase >= PI_1_4 ) begin
                    cond <= 2;
                    requested_phase <= phase - PI_1_2;
                    x <= y_in * -1;
                    y <= x_in;
                end
                else if ( phase < PI_1_4 && phase >= (-1*PI_1_4) ) begin
                    cond <= 3;
                    requested_phase <= phase;
                    x <= x_in;
                    y <= y_in;
                end
                else if ( phase < (-1*PI_1_4) && phase >= (-1*PI_3_4) ) begin
                    cond <= 4;
                    requested_phase <= phase + PI_1_2;
                    x <= y_in;
                    y <= x_in * -1;
                end
                else begin // phase < -PI_3_4
                    cond <= 5;
                    requested_phase <= phase + PI;
                    x <= x_in * -1;
                    y <= y_in * -1;
                end
            end
            else if ( idx < DELAY - 1 ) begin
                idx <= idx + 1;
                valid <= 0;
                if ( sigma ) begin
                    x <= x - (y>>>idx);
                    y <= y + (x>>>idx);
                    current_phase <= current_phase + cordic_angles[idx];
                end
                else begin
                    x <= x + (y>>>idx);
                    y <= y - (x>>>idx);
                    current_phase <= current_phase - cordic_angles[idx];
                end
            end
            else if ( idx == DELAY - 1 ) begin
                x_out <= scale_x[DWIDTH-1:0];
                y_out <= scale_y[DWIDTH-1:0];
                valid <= 1;
            end
        end
    end


endmodule