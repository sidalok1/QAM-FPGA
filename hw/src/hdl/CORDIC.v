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

    wire signed [DWIDTH:0] e_x_in = {x_in[DWIDTH-1], x_in};
    wire signed [DWIDTH:0] e_y_in = {y_in[DWIDTH-1], y_in};

    localparam ITERATIONS = DELAY-1;

    initial begin
        x_out = 0;
        y_out = 0;
        valid = 0;
    end

    localparam PFRAC = PWIDTH - 4;

    reg [$clog2(DELAY)-1:0] idx = 0;

    reg signed [PWIDTH-1:0] cordic_angles [0:ITERATIONS-1];

    localparam signed [PWIDTH-1:0] PI_1_4 = $rtoi($atan2(1, 1) * 2**(PFRAC));
    localparam signed [PWIDTH-1:0] PI_3_4 = $rtoi($atan2(1, -1) * 2**(PFRAC));
    localparam signed [PWIDTH-1:0] PI_1_2 = $rtoi($atan2(1, 0) * 2**(PFRAC));
    localparam signed [PWIDTH-1:0] PI     = $rtoi($atan2(0, -1) * 2**(PFRAC));

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

    // Precision is doubled to avoid truncation effects
    reg signed [DWIDTH:0] x = 0, y = 0;

    wire signed [(DWIDTH*2)-1:0] scale_x, scale_y;
    assign scale_x = (x * K) >>> DFRAC;
    assign scale_y = (y * K) >>> DFRAC;


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
                    requested_phase <= phase - PI;
                    x <= e_x_in * -1;
                    y <= e_y_in * -1;
                end
                else if ( phase < PI_3_4 && phase >= PI_1_4 ) begin
                    requested_phase <= phase - PI_1_2;
                    x <= e_y_in * -1;
                    y <= e_x_in;
                end
                else if ( phase < PI_1_4 && phase >= (-1*PI_1_4) ) begin
                    requested_phase <= phase;
                    x <= e_x_in;
                    y <= e_y_in;
                end
                else if ( phase < (-1*PI_1_4) && phase >= (-1*PI_3_4) ) begin
                    requested_phase <= phase + PI_1_2;
                    x <= e_y_in;
                    y <= e_x_in * -1;
                end
                else begin // phase < -PI_3_4
                    requested_phase <= phase + PI;
                    x <= e_x_in * -1;
                    y <= e_y_in * -1;
                end
            end
            else if ( idx < DELAY - 1 ) begin
                idx <= idx + 1;
                valid <= 0;
                if ( current_phase < requested_phase ) begin
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


module CORDIC_VEC #(
    parameter DWIDTH = 16,
    parameter DFRAC = 12,
    parameter PWIDTH = 16,
    parameter DELAY = 16
) (
    input wire clk, en, rst, start,
    input wire signed [DWIDTH-1:0] x_in, y_in,
    output reg signed [PWIDTH-1:0] phase,
    output reg signed [DWIDTH:0] magnitude,
    output reg valid
);

    localparam ITERATIONS = DELAY-1;

    wire signed [DWIDTH:0] e_x_in = {x_in[DWIDTH-1], x_in};
    wire signed [DWIDTH:0] e_y_in = {y_in[DWIDTH-1], y_in};

    initial begin
        phase = 0;
        magnitude = 0;
        valid = 0;
    end

    localparam PFRAC = PWIDTH - 4;

    reg [$clog2(DELAY)-1:0] idx = 0;

    reg signed [PWIDTH-1:0] cordic_angles [0:ITERATIONS-1];

    localparam signed [PWIDTH-1:0] PI_1_4 = $rtoi($atan2(1, 1) * 2**(PFRAC));
    localparam signed [PWIDTH-1:0] PI_3_4 = $rtoi($atan2(1, -1) * 2**(PFRAC));
    localparam signed [PWIDTH-1:0] PI_1_2 = $rtoi($atan2(1, 0) * 2**(PFRAC));
    localparam signed [PWIDTH-1:0] PI     = $rtoi($atan2(0, -1) * 2**(PFRAC));

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


    reg signed [PWIDTH-1:0] current_phase = 0;

    // Precision is doubled to avoid truncation effects
    reg signed [DWIDTH:0] x = 0, y = 0;

    wire signed [((DWIDTH+1)*2)-1:0] scale_mag;
    assign scale_mag = (x * K) >>> (DFRAC);

    always @( posedge clk ) begin
        if ( rst ) begin
            phase <= 0;
            magnitude <= 0;
            valid <= 0;
            idx <= 0;
            current_phase <= 0;
            x <= 0;
            y <= 0;
        end
        else if ( en ) begin
            if ( start ) begin
                idx <= 0;
                valid <= 0;
                if ( x_in < 0 ) begin
                    current_phase <= PI;
                    x <= -1 * e_x_in;
                    y <= -1 * e_y_in;
                end
                else begin
                    current_phase <= 0;
                    x <= e_x_in;
                    y <= e_y_in;
                end
            end
            else if ( idx < DELAY - 1 ) begin
                idx <= idx + 1;
                valid <= 0;
                if ( y < 0 ) begin
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
                phase <= current_phase;
                magnitude <= scale_mag[DWIDTH:0];
                valid <= 1;
            end
        end
    end


endmodule