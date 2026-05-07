module MinDistDetector #(
    parameter DWIDTH = 20,
    parameter DFRAC = 16,
    parameter PWIDTH = 24,
    parameter ORDER = 4,
    parameter CONSTELLATION = "const.mem"
)
(
    input wire clk, en, rst,
    input wire new_sample,
    input wire [DWIDTH-1:0] I, Q,
    output reg [$clog2(ORDER)-1:0] symbol,
    output reg [PWIDTH-1:0] phase_error,
    output reg valid
);


    localparam RE = 0;
    localparam IM = 1;
    reg [DWIDTH-1:0] const [0:(ORDER*2)-1];
    // genvar g;
    // generate
    //     for ( g = 0; g < ORDER; g = g + 1 ) begin:const
    //         reg signed [DWIDTH-1:0] val [0:1];
    //         initial $readmemb(CONSTELLATION, val, g*2, (g*2) + 1);  
    //     end
    // endgenerate

    reg signed [DWIDTH-1:0] in_real = 0, in_imag = 0, 
        cordic_real = 0, cordic_imag = 0;
    
    reg signed [DWIDTH:0] current_min_mag = 0;
    reg signed [PWIDTH-1:0] current_min_phase = 0;
    wire signed [DWIDTH:0] cordic_mag;
    wire signed [PWIDTH-1:0] cordic_phase;
    
    reg [$clog2(ORDER)-1:0] current_min_symbol = 0;

    integer idx = 0;
    reg [$clog2(ORDER)-1:0] cordic_symbol_in = 0;
    wire [$clog2(ORDER)-1:0] cordic_symbol_out;

    localparam STATES = 3;
    localparam IDLE = 'b001;
    localparam DIST = 'b010;
    localparam ANGL = 'b100;
    reg [STATES-1:0] state = IDLE;

    localparam CORDIC1DELAY = 20;
    localparam MULT_DELAY = 15;
    localparam CORIDC2DELAY = 40;

    reg signed [DWIDTH-1:0] m_re, m_im;
    wire signed [DWIDTH-1:0] mzre, mzim;
    reg start_cordic2 = 0;



    CORDIC_VEC_PIPE #(
        .DWIDTH(DWIDTH),
        .DFRAC(DFRAC),
        .PWIDTH(PWIDTH),
        .DELAY(CORDIC1DELAY)
    ) distance_calculator (
        .clk(clk), .en(en), .rst(rst),
        .x_in(cordic_real), .y_in(cordic_imag),
        .magnitude(cordic_mag)
    );

    PipeSignal #(
        .DWIDTH($clog2(ORDER)),
        .PIPELEN(CORDIC1DELAY)
    ) cordic_symbol_pipe (
        .clk(clk), .en(en), .rst(rst),
        .i(cordic_symbol_in),
        .o(cordic_symbol_out)
    );


    PipeMultC #(
        .DWIDTH(DWIDTH),
        .DFRAC(DFRAC),
        .PIPELEN(MULT_DELAY)
    ) complex_multiplier (
        .clk(clk), .en(en), .rst(rst),
        .x_r(in_real), .x_i(in_imag),
        .y_r(m_re), .y_i(m_im),
        .z_r(mzre), .z_i(mzim)
    );

    wire cordic_2_valid;

    CORDIC_VEC #(
        .DWIDTH(DWIDTH),
        .DFRAC(DFRAC),
        .PWIDTH(PWIDTH),
        .DELAY(CORIDC2DELAY)
    ) angle_calculator (
        .clk(clk), .en(en), .rst(rst),
        .start(start_cordic2),
        .x_in(mzre), .y_in(mzim),
        .phase(cordic_phase),
        .valid(cordic_2_valid)
    );

    initial begin
        {symbol, phase_error, valid} = 0;
        $readmemb(CONSTELLATION, const);
    end

    always @ ( posedge clk ) begin
        if ( rst ) begin
            in_real <= 0;
            in_imag <= 0;
            cordic_real <= 0;
            cordic_imag <= 0;
            current_min_mag <= 0;
            current_min_phase <= 0;
            current_min_symbol <= 0;
            cordic_symbol_in <= 0;
            symbol <= 0;
            phase_error <= 0;
            valid <= 0;
            idx <= 0;
            state <= IDLE;
            m_re <= 0;
            m_im <= 0;
            start_cordic2 <= 0;
        end
        else if ( en ) begin
            start_cordic2 <= 0;
            valid <= 0;
            case ( state ) 
            IDLE: begin
                if ( new_sample ) begin
                    current_min_symbol <= 0;
                    in_real <= I;
                    in_imag <= Q;

                    cordic_symbol_in <= 0;
                    idx <= 0;
                    state <= DIST;
                end
            end
            DIST: begin
                if ( idx < ORDER + CORDIC1DELAY + MULT_DELAY ) begin
                    idx <= idx + 1;
                end
                else begin
                    state <= ANGL;
                    start_cordic2 <= 1;
                end

                if ( idx < ORDER ) begin
                    cordic_symbol_in <= idx;
                    cordic_real <= in_real - const[(idx*2)];
                    cordic_imag <= in_imag - const[(idx*2)+1];
                end

                if ( cordic_symbol_out == current_min_symbol ) begin
                    current_min_mag <= cordic_mag;
                    m_re <= const[(cordic_symbol_out*2)];
                    m_im <= const[(cordic_symbol_out*2)+1] * -1;
                    // Multiplication by complex conjugate yields value
                    // whose phase is the difference of input values
                end
                else if ( cordic_mag < current_min_mag ) begin
                    current_min_mag <= cordic_mag;
                    current_min_symbol <= cordic_symbol_out;
                    m_re <= const[(cordic_symbol_out*2)];
                    m_im <= const[(cordic_symbol_out*2)+1] * -1;
                end
            end
            ANGL: begin
                if ( cordic_2_valid ) begin
                    symbol <= current_min_symbol;
                    state <= IDLE;
                    phase_error <= cordic_phase;
                    valid <= 1;
                end
            end
            endcase
            // if ( new_sample ) begin
            //     current_min_symbol <= 0;
            //     in_real <= I;
            //     in_imag <= Q;

            //     cordic_symbol_in <= 0;
            //     idx <= 0;
            // end
            // else begin

            //     if ( idx < ORDER + DELAY ) begin
            //         idx <= idx + 1;
            //     end
            //     else if ( idx == ORDER + DELAY ) begin
            //         symbol <= current_min_symbol;
            //         phase_error <= current_min_phase;
            //         valid <= 1;
            //         idx <= idx + 1;
            //     end
            //     else begin
            //         valid <= 0;
            //     end

            //     if ( idx < ORDER ) begin
            //         cordic_symbol_in <= idx;
            //         cordic_real <= in_real - const[idx][0];
            //         cordic_imag <= in_imag - const[idx][1];
            //     end

            //     if ( cordic_symbol_out == current_min_symbol ) begin
            //         current_min_mag <= cordic_mag;
            //         current_min_phase <= cordic_phase;
            //     end
            //     else if ( cordic_mag < current_min_mag ) begin
            //         current_min_mag <= cordic_mag;
            //         current_min_phase <= cordic_phase;
            //         current_min_symbol <= cordic_symbol_out;
            //     end
            // end
        end
    end

endmodule