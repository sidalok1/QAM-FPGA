module CORDIC_MOD #(
    parameter DWIDTH = 14,
    parameter DFRAC = 12,
    parameter SAMPLE_RATE = 5_000_000,
    parameter CARRIER_FRQ = 1_000_000
)
(
    input wire clk, en, rst,
    input wire new_sample,
    input wire signed [DWIDTH-1:0] I, Q,
    output reg signed [DWIDTH:0] R
);

    initial R = 0;

    reg signed [DWIDTH-1:0] cordic_cos = 0, cordic_sin = 0;

    wire signed [DWIDTH-1:0] cos_out, sin_out;
    wire cordic_valid;

    reg signed [23:0] phase = 0;
    wire signed [23:0] phase_next;
    localparam signed [23:0] PI = $rtoi((2*$atan2(1,0)) * 2**20);
    localparam signed [23:0] tuning_word = $rtoi((4*$atan2(1,0) * ($itor(CARRIER_FRQ)/$itor(SAMPLE_RATE))) * 2**20);

    assign phase_next = phase + tuning_word;

    CORDIC_ROT #(
        .DWIDTH(DWIDTH),
        .DFRAC(DFRAC),
        .PWIDTH(24),
        .DELAY(19)
    ) cordic_modulator (
        .clk(clk), .en(en), .rst(rst), .start(new_sample),
        .x_in(cordic_cos), .y_in(cordic_sin),
        .phase(phase), 
        .x_out(cos_out),
        .y_out(sin_out),
        .valid(cordic_valid)
    );

    always @ ( posedge clk ) begin
        if ( rst ) begin
            cordic_cos <= 0;
            cordic_sin <= 0;
            R <= 0;
            phase <= 0;
        end
        else if ( en ) begin
            if ( new_sample ) begin
                R <= cos_out - sin_out;
                cordic_cos <= I;
                cordic_sin <= Q;
                phase <= (phase_next > PI) ? phase_next - (2*PI) : phase_next;
            end
        end
    end

endmodule