/*
Module for a basic clock divider with synchronous reset

This module takes in one parameter, the desired output frequency in hertz

The system (input) clock frequency is expected as the parameter I_CLK_FRQ

*/

module clockdiv #(
    parameter           I_CLK_FRQ = 100_000_000,
    parameter           FREQUENCY = 5_000_000 // Output frq in hz
) (
    input wire          rst,
    input wire          i_clk,
    input wire          en,
    output reg          o_clk
);

    localparam integer  divider = I_CLK_FRQ / FREQUENCY;
    localparam integer  width   = $clog2(divider);
    
    reg [width-1:0]     counter;

    initial begin
        o_clk = 0;
        counter = 0;
    end

    always @( posedge i_clk ) begin
        if ( rst ) begin
            counter <= 0;
            o_clk <= 0;
        end else 
        if ( en ) begin
            if ( counter == divider - 1 ) begin
                counter <= 0;
                o_clk <= 1;
            end else begin
                counter <= counter + 1;
                o_clk <= 0;
            end
        end
    end

endmodule

/*
Usage notes:
The output of this module is not a 50% duty cycle clock, which would generally
require global clock related buffers, but instead closer to a one cycle clock
enable signal. Therefore instead of using the output signal as follows:

    always @ ( posedge o_clk ) ...

Use it in this way instead

    always @ ( posedge i_clk ) if ( o_clk ) ...

Note that since this routes the output clock to the clock enable pin of any
registers, it can be gated with any other enable signals. Fore example, the
following code:

    always @ ( posedge o_clk ) begin
        if ( i_en ) ...
    
Should be written as:

    and( enable, i_en, o_clk );

    always @ ( posedge i_clk ) begin
        if ( enable ) ...

or:

    and( enable, i_en, o_clk );

    always @ ( posedge i_clk ) if ( enable ) ...
*/