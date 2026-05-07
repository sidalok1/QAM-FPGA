module uarttx #(
  parameter I_CLK_FRQ     = 100_000_000,
  parameter BAUD          = 115200,
  parameter [0:0] PARITY  = 0,
  parameter [3:0] FRAME   = 8,
  parameter [1:0] STOP    = 1

) (
  input wire  clk,
  input wire  en,
  input wire  rst,
  input wire  [FRAME-1:0] i_data,
  output reg  tx,
  output wire busy
);
  localparam integer FRAMESIZE  = FRAME - 1;
  localparam integer PACKETSIZE = FRAMESIZE + 1 + PARITY + STOP;
  
  wire baud_enable;

  clockdiv #(
    .I_CLK_FRQ(I_CLK_FRQ),
    .FREQUENCY(BAUD)
  ) baud_clock (
    .rst(rst),
    .en(1),
    .i_clk(clk),
    .o_clk(baud_enable)
  );

  reg [$clog2(PACKETSIZE)-1:0] bit_idx;
  reg [FRAMESIZE:0] frame;
  wire [PACKETSIZE:0] packet;
  wire parity = ^frame;
  wire [STOP-1:0] stop = {STOP{1'b1}};
  assign packet = PARITY ? {stop, parity, frame, 1'b0} : {stop, frame, 1'b0};

  
  localparam [1:0] IDLE = 'b01;
  localparam [1:0] SEND = 'b10;
  
  reg [1:0] state;
  
  assign busy = state != IDLE;
  
  initial begin
    bit_idx <= 0;
    frame <= 0;
    state = IDLE;
    tx = 1;
  end
  
  always @ ( posedge clk ) begin
    if ( rst ) begin
      state <= IDLE;
      frame <= 0;
      bit_idx <= 0;
      tx <= 1;
    end else begin
      case ( state )
      IDLE: begin
        tx <= 1;
        if ( en ) begin
          state <= SEND;
          frame <= i_data;
          bit_idx <= 0;
        end
      end
      SEND: begin
        if ( baud_enable ) begin
          if ( bit_idx == PACKETSIZE ) begin
            state <= IDLE;
          end
          tx <= packet[bit_idx];
          bit_idx <= bit_idx + 1;
        end else begin
          tx <= tx;
        end
      end
      default: begin
        // illegal state
        state <= IDLE;
      end
      endcase
    end
  end
endmodule

module uartrx #(
  parameter I_CLK_FRQ = 100_000_000,
  parameter BAUD = 115200,
  parameter [0:0] PARITY = 0,
  parameter [3:0] FRAME = 8,
  parameter [1:0] STOP = 1
) (
  input wire clk,
  input wire en,
  input wire rst,
  input wire rx,
  output reg [FRAME-1:0] rx_data,
  output reg valid
);

  initial begin 
    valid = 0;
    rx_data = 0;
  end

  localparam integer PACKETSIZE = FRAME + PARITY;

  integer clk_counter = 0, bit_counter = 0;
  localparam integer DIVIDER = I_CLK_FRQ / BAUD;

  reg [PACKETSIZE-1:0] packet = 0;


  localparam STATES = 4;
  localparam IDLE = 'b0001;
  localparam START = 'b0010;
  localparam DATA = 'b0100;
  localparam DONE = 'b1000;
  reg [STATES-1:0] state = IDLE;

  always @ ( posedge clk ) begin
    if ( rst ) begin
      clk_counter <= 0;
      bit_counter <= 0;
      valid <= 0;
      packet <= 0;
      state <= IDLE;
      rx_data <= 0;
    end
    else if ( en ) begin
      valid <= 0;
      case ( state )
      IDLE: begin
        if ( !rx ) begin
          state <= START;
          clk_counter <= (DIVIDER / 2) - 1;
        end
      end
      START: begin
        if ( rx ) begin
          state <= START;
        end
        else if ( clk_counter == 0 ) begin
          state <= DATA;
          bit_counter <= 0;
          clk_counter <= DIVIDER - 1;
        end
        else begin
          clk_counter <= clk_counter - 1;
        end
      end
      DATA: begin
        if ( clk_counter == 0 ) begin
          packet[bit_counter] <= rx;
          if ( bit_counter == PACKETSIZE - 1 ) begin
            state <= DONE;
            clk_counter <= DIVIDER - 1;
            bit_counter <= 0;
          end
          else begin
            bit_counter <= bit_counter + 1;
            clk_counter <= DIVIDER - 1;
          end
        end
        else begin
          clk_counter <= clk_counter - 1;
        end
      end
      DONE: begin
        if ( clk_counter == 0 ) begin
          if ( ~rx ) begin
            // Data not correctly framed
            state <= IDLE;
          end
          else if ( bit_counter == STOP - 1 ) begin
            state <= IDLE;
            if ( PARITY ) begin
              valid <= ( ^~packet ) ? 1 : 0;
              rx_data <= ( ^~packet ) ? packet[FRAME-1:0] : rx_data; 
            end
            else begin
              valid <= 1;
              rx_data <= packet[FRAME-1:0];
            end
          end
          else begin
            bit_counter <= bit_counter + 1;
            clk_counter <= DIVIDER - 1;
          end
        end
        else begin
          clk_counter <= clk_counter - 1;
        end
      end
      default: begin
        // illegal state
        state <= IDLE;
      end
      endcase
    end
  end

endmodule