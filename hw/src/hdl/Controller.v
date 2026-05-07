module Controller
#(
  //  Total word length of the output symbols
  parameter DWIDTH                          = 10,
  parameter DFRAC                           = 8,
  //  Number of symbols in constellation
  parameter MODULATION_ORDER                = 4,
  //  File containing constellation symbols in order,
  parameter CONSTELLATION                   = "const.mem", 
  parameter FRAME_SEQ                       = "zadoff_chu.mem",
  //  Output sample rate in hertz
  parameter SAMPLE_RATE                     = 5_000_000,
  parameter CLK_FREQ                        = 100_000_000,
  //  Symbol rate in hertz, together with last value determin sps
  parameter SYMBOL_RATE                     = 50_000,
  parameter FRAME_LEN                       = 16,
  parameter EQ_LEN                          = 18,
  parameter UART_BAUD                       = 1_000_000
)
(
  //  Input clock, should be at the frequency specified by parameter
  input wire                                clk,
  //  General clocked logic enable signal
  input wire                                en,
  //  Synchronous reset
  input wire                                rst,
  //  Signal to begin a transmission
  input wire                                start,
  input wire                                new_sample,
  input wire                                signal_detected,
  //  Output symbols in two's complement form at the requested sample rate
  output wire signed [DWIDTH-1:0]           I, Q,
  
  input wire                                uart_rx,
  output wire                               uart_tx,

  output wire                               interrupt,
  output wire                               tx_started,
  
  //  Controller also receives information from receiver hardware
  input wire [$clog2(MODULATION_ORDER)-1:0] rx_symbol,
  input wire                                new_symbol
);
  
  TX_Controller #(
    .DWIDTH(DWIDTH),
    .DFRAC(DFRAC),
    .MODULATION_ORDER(MODULATION_ORDER),
    .CONSTELLATION(CONSTELLATION),
    .FRAME_SEQ(FRAME_SEQ),
    .SAMPLE_RATE(SAMPLE_RATE),
    .CLK_FREQ(CLK_FREQ),
    .SYMBOL_RATE(SYMBOL_RATE),
    .FRAME_LEN(FRAME_LEN),
    .EQ_LEN(EQ_LEN),
    .UART_BAUD(UART_BAUD)
  ) transmit_controller (
    .clk(clk), .en(en), .rst(rst),
    .start(start),
    .new_sample(new_sample),
    .signal_detected(signal_detected),
    .I(I), .Q(Q),
    .uart_rx(uart_rx),
    .interrupt(tx_started)
  );

  RX_Controller #(
    .MODULATION_ORDER(MODULATION_ORDER),
    .CLK_FREQ(CLK_FREQ),
    .UART_BAUD(UART_BAUD)
  ) receive_controller (
    .clk(clk), .en(en), .rst(rst),
    .uart_tx(uart_tx),
    .interrupt(interrupt),
    .rx_symbol(rx_symbol),
    .new_symbol(new_symbol)
  );

endmodule

module TX_Controller #(
  parameter DWIDTH                          = 10,
  parameter DFRAC                           = 8,
  parameter MODULATION_ORDER                = 4,
  parameter CONSTELLATION                   = "const.mem", 
  parameter FRAME_SEQ                       = "zadoff_chu.mem",
  parameter SAMPLE_RATE                     = 5_000_000,
  parameter CLK_FREQ                        = 100_000_000,
  parameter SYMBOL_RATE                     = 50_000,
  parameter FRAME_LEN                       = 16,
  parameter EQ_LEN                          = 18,
  parameter UART_BAUD                       = 1115200
)
(
  input wire                                clk,
  input wire                                en,
  input wire                                rst,
  input wire                                start,
  input wire                                new_sample,
  input wire                                signal_detected,
  output reg signed [DWIDTH-1:0]            I, Q,
  
  input wire                                uart_rx,

  output reg                                interrupt
);
  localparam BITS_PER_SYMBOL = $clog2(MODULATION_ORDER);
  localparam MAX_BYTES = 256;
  localparam MAX_BITS = MAX_BYTES * 8;
  localparam MAX_SYMBOLS = MAX_BITS / BITS_PER_SYMBOL;
  localparam MSG_LEN_LEN = ($clog2(MAX_SYMBOLS)/BITS_PER_SYMBOL) + 1;

  integer i;

  reg [7:0] buff [0:MAX_BYTES-1];
  reg [(BITS_PER_SYMBOL*MSG_LEN_LEN)-1:0] msg_len;
  reg [$clog2(MAX_BYTES)-1:0] bytes;
  
  
  localparam RE = 0;
  localparam IM = 1;
  reg [DWIDTH-1:0] const [0:(MODULATION_ORDER*2)-1];
  reg [DWIDTH-1:0] frame_header [0:(FRAME_LEN*2)-1];

  
  //  Symbols per sample
  localparam SPS                  = SAMPLE_RATE / SYMBOL_RATE;
  
  //  General registers used for counting indices
  integer idx;
  integer jdx;
  integer kdx;
  
  // FSM state register and state definitions
  localparam STATES                     = 6;
  localparam [STATES-1:0] UART_RX       = 'b000001;
  localparam [STATES-1:0] WAIT          = 'b000010;
  localparam [STATES-1:0] PRESYNC       = 'b000100;
  localparam [STATES-1:0] STARTCODE     = 'b001000;
  localparam [STATES-1:0] MSGLEN        = 'b010000;
  localparam [STATES-1:0] MSGBODY       = 'b100000;
  reg [STATES-1:0] state;

  wire [7:0] uart_rx_data;
  wire uart_valid;

  uartrx #(
    .I_CLK_FRQ(CLK_FREQ),
    .BAUD(UART_BAUD),
    .PARITY(0),
    .FRAME(8),
    .STOP(1)
  ) uart_receiver (
    .clk(clk), .en(en), .rst(rst),
    .rx(uart_rx), 
    .rx_data(uart_rx_data),
    .valid(uart_valid)
  );

  reg [BITS_PER_SYMBOL-1:0] symb;
  
  initial begin
    I               = 0;
    Q               = 0;
    interrupt       = 0;
    state           = UART_RX;
    idx             = 0;
    jdx             = 0;
    kdx             = 0;
    symb            = 0;
    $readmemb(CONSTELLATION, const);
    $readmemb(FRAME_SEQ, frame_header);
    bytes = 0;
    msg_len = (2*8)/BITS_PER_SYMBOL; 
    for ( i = 0; i < MAX_BYTES; i = i + 1 ) begin
      case ( i ) 
      0:        buff[i] = "h";
      1:        buff[i] = "i";
      default:  buff[i] = 8'b0;
      endcase
    end
  end

  localparam [DWIDTH-1:0] ONE = 2**DFRAC;
  
  always @ ( posedge clk ) begin
    if ( rst ) begin
        state <= UART_RX;
        // buffer <= {"hello world!\n", {(STR_BITS-(13*8)){1'b0}}};
        // msg_len <= (13*8)/BITS_PER_SYMBOL;
        idx <= 0;
        jdx <= 0;
        kdx <= 0;
        bytes <= 0;
        I <= 0;
        Q <= 0;
        symb <= 0;
        interrupt <= 0;
    end 
    else if ( en ) begin
      interrupt <= 0;

      case ( state )
      UART_RX: begin
        if ( new_sample ) begin
          I <= 0;
          Q <= 0;
        end
        if ( uart_valid ) begin
          case ( uart_rx_data )
          8'o012,
          8'o015: begin // enter keys
            if ( bytes > 0 ) begin
              state <= WAIT;
              jdx <= idx;
              bytes <= 0;
              msg_len <= (bytes*8) / BITS_PER_SYMBOL;
            end
          end
          // backspace
          8'o010: begin
            bytes <= ( bytes == 0 ) ? 0 : bytes - 1;
          end
          default: begin
            // buffer[(bytes*8)+:8] <= uart_rx_data;
            buff[bytes] <= uart_rx_data;
            bytes <= ( bytes == MAX_BYTES - 1 ) ? MAX_BYTES - 1 : bytes + 1;
          end
          endcase
        end
        else if ( start ) begin
          jdx <= idx;
          state <= WAIT;
        end
      end
      WAIT: begin
        if ( new_sample ) begin
          I <= 0;
          Q <= 0;
          if ( idx == 0 ) begin
            jdx <= 0;
            interrupt <= 1;
            state <= PRESYNC;
          end 
          else if ( signal_detected == 1'b0 ) begin
            idx <= idx - 1;  
          end
          else begin
            idx <= jdx;
          end
        end
      end
      PRESYNC: begin
        if ( new_sample ) begin
          I <= ONE;
          Q <= 0;
          if ( jdx == SPS - 1 ) begin
            jdx <= 0;
            if ( idx == EQ_LEN - 1 ) begin
              idx <= 0;
              state <= STARTCODE;
            end
            else begin
              idx <= idx + 1;
            end
          end
          else begin
            jdx <= jdx + 1;
          end
        end
      end
      STARTCODE: begin
        if ( new_sample ) begin
          if ( idx < FRAME_LEN ) begin
            I <= frame_header[(idx*2)];
            Q <= frame_header[(idx*2)+1];
          end
          else begin
              I <= 0;
              Q <= 0;
          end
          if ( jdx == SPS - 1 ) begin
            jdx <= 0;
            if ( idx == FRAME_LEN ) begin
              idx <= 0;
              kdx <= 0;
              state <= MSGLEN;
            end
            else begin
              idx <= idx + 1;
            end
          end
          else begin
            jdx <= jdx + 1;
          end
        end
      end
      MSGLEN: begin
        if ( kdx < ((idx+1)*BITS_PER_SYMBOL) ) begin
          symb[kdx % BITS_PER_SYMBOL] <= msg_len[kdx];
          kdx <= kdx + 1;
        end
        if ( new_sample ) begin
          I <= const[(symb*2)];
          Q <= const[(symb*2)+1];
          if ( jdx == SPS - 1 ) begin
            jdx <= 0;
            if ( idx == MSG_LEN_LEN - 1 ) begin
              idx <= 0;
              kdx <= 0;
              state <= MSGBODY;
            end
            else begin
              idx <= idx + 1;
            end
          end
          else begin
            jdx <= jdx + 1;
          end
        end
      end
      MSGBODY: begin
        if ( kdx < ((idx+1)*BITS_PER_SYMBOL) ) begin
          symb[kdx%BITS_PER_SYMBOL] <= buff[kdx/8][kdx%8];
          kdx <= kdx + 1;
        end
        if ( new_sample ) begin
          // I <= const[(buffer[(idx*BITS_PER_SYMBOL)+:BITS_PER_SYMBOL]*2)];
          // Q <= const[(buffer[(idx*BITS_PER_SYMBOL)+:BITS_PER_SYMBOL]*2)+1];
          I <= const[(symb*2)];
          Q <= const[(symb*2)+1];
          if ( jdx == SPS - 1 ) begin
            jdx <= 0;
            if ( idx == msg_len - 1 ) begin
              kdx <= 0;
              state <= UART_RX;
              idx <= 2048; // number of samples to wait before transmitting again
            end
            else begin
              idx <= idx + 1;
            end
          end
          else begin
            jdx <= jdx + 1;
          end
        end
      end
      default: begin
        // illegal state
        state <= UART_RX;
      end
      endcase
    end
  end
endmodule

module RX_Controller #(
  parameter MODULATION_ORDER                = 4,
  parameter CLK_FREQ                        = 100_000_000,
  parameter UART_BAUD                       = 1115200
)
(
  input wire                                clk,
  input wire                                en,
  input wire                                rst,
  
  output wire                               uart_tx,

  output reg                                interrupt,
  
  //  Controller also receives information from receiver hardware
  input wire [$clog2(MODULATION_ORDER)-1:0] rx_symbol,
  input wire                                new_symbol
);

  initial interrupt = 0;

  localparam BITS_PER_SYMBOL = $clog2(MODULATION_ORDER);

  reg [BITS_PER_SYMBOL-1:0] symbol_in = 0;

  localparam MAX_BYTES = 256;
  localparam MAX_BITS = MAX_BYTES * 8;
  localparam MAX_SYMBOLS = MAX_BITS / BITS_PER_SYMBOL;
  localparam MSG_LEN_LEN = ($clog2(MAX_SYMBOLS)/BITS_PER_SYMBOL) + 1;


  reg [7:0] uart_tx_data = 0;
  reg uart_tx_en = 0;
  wire uart_busy;

  
  uarttx #(
    .I_CLK_FRQ(CLK_FREQ),
    .BAUD(UART_BAUD),
    .PARITY(0),
    .FRAME(8),
    .STOP(1)
  ) uart_transmitter (
    .clk(clk), .rst(rst), .en(uart_tx_en),
    .i_data(uart_tx_data),
    .tx(uart_tx),
    .busy(uart_busy)
  );

  localparam STATES                     = 3;
  localparam [STATES-1:0] READLEN       = 3'b001;
  localparam [STATES-1:0] READBODY      = 3'b010;
  localparam [STATES-1:0] UART_TX       = 3'b100;
  reg [STATES-1:0] state                = READLEN;

  
  reg [(BITS_PER_SYMBOL*MSG_LEN_LEN)-1:0] msg_len  = 0;
  wire [$clog2(MAX_BYTES)-1:0] bytes;
  assign bytes = (msg_len*BITS_PER_SYMBOL) / 8;
  // reg [0:STR_BITS-1] buffer = 0;
  reg [7:0] buff [0:MAX_BYTES-1];
  integer i;
  initial for ( i = 0; i < MAX_BYTES; i = i + 1 ) begin
    buff[i] = 0;
  end
  
  integer kdx = 0;

  always @ ( posedge clk ) begin
    if ( rst ) begin
        interrupt <= 0;
        kdx <= 0;
        uart_tx_en <= 0;
        uart_tx_data <= 0;
        // buffer <= 0;
        msg_len <= 0;
        state <= READLEN;
        symbol_in <= 0;
    end 
    else if ( en ) begin
      uart_tx_en <= 0;
      interrupt <= 0;
      symbol_in <= rx_symbol;
      case ( state )
      READLEN: begin
          if ( new_symbol ) begin
            msg_len[(kdx*BITS_PER_SYMBOL)+:BITS_PER_SYMBOL] <= rx_symbol;
            if ( kdx == MSG_LEN_LEN - 1 ) begin
              state <= READBODY;
              kdx <= 0;
            end
            else begin
              kdx <= kdx + 1;
            end
          end
      end
      READBODY: begin
        if ( new_symbol ) begin
          // buffer[(kdx*BITS_PER_SYMBOL)+:BITS_PER_SYMBOL] <= rx_symbol;
          buff[(kdx*BITS_PER_SYMBOL)/8][(kdx*BITS_PER_SYMBOL)%8+:BITS_PER_SYMBOL] <= rx_symbol;
          if ( kdx == msg_len - 1 ) begin
            interrupt <= 1;
            state <= UART_TX;
            kdx <= 0;
          end
          else begin
            kdx <= kdx + 1;
          end
        end
      end
      UART_TX: begin
        if ( !uart_busy && !uart_tx_en ) begin
          uart_tx_en <= 1;
          // uart_tx_data <= ( kdx == bytes ) ? "\n" : buffer[kdx*8 +: 8];
          uart_tx_data <= ( kdx == bytes ) ? "\n" : buff[kdx];
          state <=     ( kdx == bytes ) ? READLEN : UART_TX;
          kdx <=          ( kdx == bytes ) ? 0 : kdx + 1;
        end
        // m_axis_tvalid <= 1;
        // if ( m_axis_tready && m_axis_tvalid ) begin
        //   m_axis_tvalid <= ( kdx == bytes ) ? 0 : 1;
        //   m_axis_tdata <=  ( kdx == bytes ) ? 32'b0 : {24'b0, buffer[kdx*8 +: 8]};
        //   m_axis_tlast <=  ( kdx == bytes - 1 ) ? 1 : 0;   
        //   kdx <=           ( kdx == bytes ) ? 0 : kdx + 1;
        //   state <=      ( kdx == bytes ) ? READLEN : AXI_TX;
        // end
      end
      default: begin
        // illegal state
        state <= READLEN;
      end
      endcase
    end
  end
endmodule