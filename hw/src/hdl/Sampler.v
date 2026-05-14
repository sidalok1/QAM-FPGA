/*
Performs both sampling and equalization. 
*/

module Sampler #(
    parameter DWIDTH = 18,
    parameter DFRAC = 16,
    parameter MOD_ORDER = 16
)
(
    input wire clk, rst, en,
    input wire new_sample, // 500khz, not 5Mhz
    input wire [DWIDTH-1:0] I_i, Q_i,
    input wire signal_detected, interrupt,
    output reg [DWIDTH-1:0] I_o, Q_o,
    output wire [$clog2(MOD_ORDER)-1:0] rx_symbol,
    output wire new_symbol
);

    initial begin
        I_o = 0;
        Q_o = 0;
    end

    localparam STATES = 5;
    localparam IDLE     = 'b00001; // Wait for a signal to be detected
    localparam EQ_MAG   = 'b00010;
    localparam EQ_FRQ   = 'b00100;
    localparam FRAME    = 'b01000; // Await the frame header
    localparam SAMPLE   = 'b10000; // Sampling with phase adjustment
    reg [STATES-1:0] state = IDLE;

    localparam PIPELEN = 7;

    localparam GWIDTH = 24;
    localparam GFRAC = 12;
    reg signed [GWIDTH-1:0] magn_gain = 2**GFRAC; // magn_gain = 1

    reg signed [DWIDTH-1:0] I_mult_in = 0, Q_mult_in = 0;
    reg signed [DWIDTH-1:0] zero_offset_I = 0, zero_offset_Q = 0;
    wire signed [(DWIDTH+GWIDTH)-1:0] I_mult_out, Q_mult_out;
    wire signed [(DWIDTH+GWIDTH)-1:0] I_amplified = I_mult_out >>> GFRAC;
    wire signed [(DWIDTH+GWIDTH)-1:0] Q_amplified = Q_mult_out >>> GFRAC;

    PipeMult #(
        .WIDTH_A(DWIDTH),
        .WIDTH_B(GWIDTH),
        .PIPELEN(PIPELEN)
    ) I_amp (
        .clk(clk), .en(en), .rst(rst),
        .a(I_mult_in),
        .b(magn_gain),
        .r(I_mult_out)
    ),Q_amp (
        .clk(clk), .en(en), .rst(rst),
        .a(Q_mult_in),
        .b(magn_gain),
        .r(Q_mult_out)
    );

    reg mult_valid_i = 0;
    wire mult_valid_o;
    

    PipeSignal #(
        .DWIDTH(1),
        .PIPELEN(PIPELEN)
    ) multiplier_valid_pipe (
        .clk(clk), .en(en), .rst(rst),
        .i(mult_valid_i),
        .o(mult_valid_o)
    );

    localparam PWIDTH = 24;
    localparam PFRAC = PWIDTH - 4;
    reg signed [PWIDTH-1:0] phase_reg = 0;
    reg signed [PWIDTH-1:0] phase_tot = 0;
    reg signed [PWIDTH-1:0] freq_offset = 0;
    reg signed [PWIDTH-1:0] phase_offset = 0;
    localparam signed [PWIDTH-1:0] PI = $rtoi($itor(2**PFRAC) * (2*$atan2(1,0)));

    function signed [PWIDTH-1:0] add_phase (input signed [PWIDTH-1:0] a, b);
        begin
            add_phase = ((a + b) < -1*PI) ? 
                            (a + b) + 2*PI:
                        ((a + b) > PI)    ?
                            (a + b) - (2*PI):
                            (a + b);
        end
    endfunction
    
    
    wire signed [DWIDTH-1:0] I_eq, Q_eq;
    wire cordic_rot_valid;

    localparam CORDIC_DELAY = 40;

    CORDIC_ROT #(
        .DWIDTH(DWIDTH),
        .DFRAC(DFRAC),
        .PWIDTH(PWIDTH),
        .DELAY(CORDIC_DELAY)
    ) phase_adjust (
        .clk(clk), .en(en), .rst(rst), 
        .start(mult_valid_o),
        .x_in(I_amplified[DWIDTH-1:0]),
        .y_in(Q_amplified[DWIDTH-1:0]),
        .phase(phase_tot),
        .x_out(I_eq),
        .y_out(Q_eq),
        .valid(cordic_rot_valid)
    );

    
    wire signed [PWIDTH-1:0] phase_err;
    wire signed [PWIDTH-1:0] abs_phase_err = phase_err < 0 ?
                                phase_err * -1 :
                                phase_err;
    reg signed [PWIDTH-1:0] phase_err_n = 0, phase_err_n_neg = 0;
    
    wire signed [DWIDTH:0] magnitude_out;

    wire signed [DWIDTH:0] magnitude_err = magnitude_out - (2**DFRAC);
    reg signed [DWIDTH:0] magn_err_sum = 0;
    wire signed [DWIDTH:0] abs_mag_err = magnitude_err < 0 ?
                            magnitude_err * -1 :
                            magnitude_err;

    wire cordic_vec_valid;

    CORDIC_VEC #(
        .DWIDTH(DWIDTH),
        .DFRAC(DFRAC),
        .PWIDTH(PWIDTH),
        .DELAY(CORDIC_DELAY)
    ) error_detector (
        .clk(clk), .en(en), .rst(rst),
        .start(cordic_rot_valid),
        .x_in(I_eq),
        .y_in(Q_eq),
        .phase(phase_err),
        .magnitude(magnitude_out),
        .valid(cordic_vec_valid)
    );

    localparam SPS = 10;
    
    reg signed [PWIDTH-1:0] freq_err = 0;
    reg signed [PWIDTH-1:0] freq_err_sum = 0;

    integer idx = 0, jdx = 0;

    localparam FWIDTH = DWIDTH+4;

    wire signed [FWIDTH-1:0] e_I_eq = I_eq, e_Q_eq = Q_eq;

    wire signed [FWIDTH-1:0] frame_r, frame_i;
    wire signed [FWIDTH:0] frame_mag;
    integer frame_mag_n = 0;
    wire signed [PWIDTH-1:0] frame_phs;
    reg signed [PWIDTH-1:0] frame_phs_n = 0;
    wire frame_valid;
    
    localparam signed [FWIDTH-1:0] frame_detect_threshold = $rtoi(30.0 * $itor(2**DFRAC));

    FIR_Complex #(
        .DWIDTH(FWIDTH),
        .DFRAC(DFRAC)
    ) frame_synchronization (
        .clk(clk), .en(en), .rst(rst), .new_sample(cordic_rot_valid),
        .i_real(e_I_eq), .i_imag(e_Q_eq),
        .o_real(frame_r), .o_imag(frame_i)
    );

    CORDIC_VEC #(
        .DWIDTH(FWIDTH),
        .DFRAC(DFRAC),
        .PWIDTH(PWIDTH),
        .DELAY(CORDIC_DELAY)
    ) frame_sync_detector (
        .clk(clk), .en(en), .rst(rst),
        .start(cordic_rot_valid),
        .x_in(frame_r),
        .y_in(frame_i),
        .phase(frame_phs),
        .magnitude(frame_mag),
        .valid(frame_valid)
    );

    reg signed [DWIDTH-1:0] min_dist_detector_real = 0, min_dist_detector_imag = 0;
    reg start_min_dist_detector = 0;

    wire [$clog2(MOD_ORDER)-1:0] min_dist_symbol;
    assign rx_symbol = min_dist_symbol;
    wire signed [PWIDTH-1:0] min_dist_phase_err;
    reg signed [PWIDTH-1:0] min_dist_phase_err_sum = 0;
    wire min_dist_dvalid;
    assign new_symbol = min_dist_dvalid;

    MinDistDetector #(
        .DWIDTH(DWIDTH),
        .DFRAC(DFRAC),
        .PWIDTH(PWIDTH),
        .ORDER(MOD_ORDER)
    ) min_dist_detector (
        .clk(clk), .en(en), .rst(rst),
        .new_sample(start_min_dist_detector),
        .I(min_dist_detector_real), .Q(min_dist_detector_imag),
        .symbol(min_dist_symbol),
        .phase_error(min_dist_phase_err),
        .valid(min_dist_dvalid)
    );

    always @ ( posedge clk ) begin
        if ( rst | interrupt ) begin
            I_o <= 0;
            Q_o <= 0;
            state <= IDLE;
            magn_gain <= 2**GFRAC;
            freq_offset <= 0;
            phase_offset <= 0;
            I_mult_in <= 0;
            Q_mult_in <= 0;
            mult_valid_i <= 0;
            phase_reg <= 0;
            phase_tot <= 0;
            freq_err <= 0;
            freq_err_sum <= 0;
            phase_err_n <= 0;
            phase_err_n_neg <= 0;
            idx <= 0;
            jdx <= 0;
            frame_mag_n <= 0;
            frame_phs_n <= 0;
            start_min_dist_detector <= 0;
            min_dist_detector_real <= 0;
            min_dist_detector_imag <= 0;
            min_dist_phase_err_sum <= 0;
        end
        else if ( en ) begin
            phase_tot <= add_phase(phase_reg, phase_offset);
            if ( new_sample ) begin
                I_mult_in <= I_i;
                Q_mult_in <= Q_i;
                mult_valid_i <= 1;
                phase_reg <= add_phase(phase_reg, freq_offset);
                phase_err_n <= phase_err;
                phase_err_n_neg <= phase_err * -1;
                freq_err <= add_phase(phase_err, phase_err_n_neg);
                I_o <= I_eq;
                Q_o <= Q_eq;
            end
            else begin
                mult_valid_i <= 0;
            end

            start_min_dist_detector <= 0;
            case ( state )
            IDLE: begin
                if ( new_sample ) begin
                    if ( idx > 4*SPS ) begin
                        idx <= 0;
                        state <= EQ_MAG;
                    end
                    else begin
                        if ( signal_detected )
                            idx <= idx + 1;
                        else 
                            idx <= 0;
                    end
                end
            end
            EQ_MAG: begin
                if ( new_sample ) begin
                    magn_gain <= magn_gain - (magnitude_err >>> 2);
                    if ( idx == 32 ) begin
                        state <= EQ_FRQ;
                        idx <= 0;
                    end
                    else begin
                        idx <= idx + 1;
                    end
                end
            end
            EQ_FRQ: begin
                if ( new_sample ) begin
                    if ( idx == 128 ) begin
                        freq_offset <= (freq_err_sum / 128);
                        freq_err_sum <= 0;
                        idx <= 0;
                        state <= FRAME;
                        phase_offset <= phase_err;
                    end 
                    else begin
                        idx <= idx + 1;
                        freq_err_sum <= freq_err_sum + freq_err;    
                    end
                end
            end
            FRAME: begin
                if ( new_sample ) begin
                    frame_mag_n <= frame_mag;
                    frame_phs_n <= frame_phs;
                    if ( !signal_detected )
                        jdx <= jdx + 1;
                    else
                        jdx <= 0;
                    if ( jdx == 3*SPS ) begin
                        // If three symbols have passed without a signal being detected
                        state <= IDLE;
                        magn_gain <= 2**GFRAC;
                        freq_offset <= 0;
                        phase_offset <= 0;
                    end
                end else begin
                    if ( frame_mag > frame_detect_threshold && frame_mag < frame_mag_n ) begin
                        state <= SAMPLE;
                        phase_offset <= add_phase(phase_offset, frame_phs_n);
                        idx <= 0;
                        jdx <= 0;
                    end
                end
            end
            SAMPLE: begin
                if ( new_sample ) begin
                    if ( idx == SPS - 1 ) begin
                        min_dist_detector_real <= I_eq;
                        min_dist_detector_imag <= Q_eq;
                        start_min_dist_detector <= 1;
                        idx <= 0;
                    end
                    else begin
                        idx <= idx + 1;
                    end

                    if ( !signal_detected )
                        jdx <= jdx + 1;
                    else
                        jdx <= 0;
                end
                else if ( min_dist_dvalid ) begin
                    // phase_offset <= add_phase(phase_offset, min_dist_phase_err);
                    min_dist_phase_err_sum <= add_phase(min_dist_phase_err_sum, min_dist_phase_err);
                end

                if ( jdx == 4*SPS ) begin
                    state <= IDLE;
                    magn_gain <= 2**GFRAC;
                    freq_offset <= 0;
                    phase_offset <= 0;
                    min_dist_phase_err_sum <= 0;
                end
            end
            endcase
        end
    end

endmodule