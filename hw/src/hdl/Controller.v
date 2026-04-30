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
  //  Symbol rate in hertz, together with last value determin sps
  parameter SYMBOL_RATE                     = 50_000,
  parameter FRAME_LEN                       = 16,
  parameter EQ_LEN                          = 32
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
  //  Output symbols in two's complement form at the requested sample rate
  output reg signed [DWIDTH-1:0]            I, Q,
  
  //  Axi stream ports
  input wire [31:0]                         s_axis_tdata,
  input wire                                s_axis_tlast,
  input wire                                s_axis_tvalid,
  output reg                                s_axis_tready,
  
  output reg [31:0]                         m_axis_tdata,
  output reg                                m_axis_tlast,
  output reg                                m_axis_tvalid,
  input wire                                m_axis_tready,
  
  output reg                                interrupt,
  
  //  Controller also receives information from receiver hardware
  input wire [$clog2(MODULATION_ORDER)-1:0] rx_symbol,
  input wire                                new_symbol
);
  
  initial begin
    I               = 0;
    Q               = 0;
    s_axis_tready   = 0;
    m_axis_tdata    = 0;
    m_axis_tlast    = 0;
    m_axis_tvalid   = 0;
    interrupt       = 0;
  end
  
  localparam BITS_PER_SYMBOL = $clog2(MODULATION_ORDER);

  localparam MAX_SYMBOLS = 2**(BITS_PER_SYMBOL*4);


  localparam MAX_STR_LEN                  = (MAX_SYMBOLS*BITS_PER_SYMBOL)/8;
  localparam STR_BITS                     = MAX_STR_LEN * 8;
  reg [0:STR_BITS-1] message_buffer       = 0;
  reg [$clog2(MAX_STR_LEN)-1:0] tx_bytes  = 0;
  wire [(BITS_PER_SYMBOL*4)-1:0] tx_len;
  assign tx_len = (tx_bytes*8) / BITS_PER_SYMBOL;
  // Maximum value of idx before state should change
  integer idx_max_val;
  
  reg [DWIDTH-1:0] constellation [0:MODULATION_ORDER-1][0:1];
  initial $readmemb(CONSTELLATION, constellation);
  reg [DWIDTH-1:0] frame_header_seq [0:FRAME_LEN-1][0:1];
  initial $readmemb(FRAME_SEQ, frame_header_seq);
  
  //  Symbols per sample
  localparam integer SPS                  = SAMPLE_RATE / SYMBOL_RATE;
  
  //  General registers used for counting indices
  integer idx                             = 0;
  integer jdx                             = 0;
  
  // FSM state register and state definitions
  localparam tx_STATES                    = 7;
  localparam [tx_STATES-1:0] IDLE         = 'b0000001;
  localparam [tx_STATES-1:0] AXI_RX       = 'b1000000;
  localparam [tx_STATES-1:0] PRESYNC      = 'b0000010;
  localparam [tx_STATES-1:0] STARTCODE    = 'b0000100;
  localparam [tx_STATES-1:0] MSGLEN       = 'b0001000;
  localparam [tx_STATES-1:0] MSGBODY      = 'b0010000;
  localparam [tx_STATES-1:0] POSTSYNC     = 'b0100000;
  reg [tx_STATES-1:0] tx_state            = IDLE;
  

  reg [tx_STATES-1:0] tx_next, axi_next   = IDLE;
  
  localparam rx_STATES                    = 3;
  localparam [rx_STATES-1:0] READLEN      = 3'b001;
  localparam [rx_STATES-1:0] READBODY     = 3'b010;
  localparam [rx_STATES-1:0] AXI_TX       = 3'b100;
  reg [rx_STATES-1:0] rx_state            = READLEN;

  
  reg [(BITS_PER_SYMBOL*4)-1:0] rx_len  = 0;
  wire [$clog2(MAX_STR_LEN)-1:0] rx_bytes;
  assign rx_bytes = (rx_len*BITS_PER_SYMBOL) / 8;
  reg [0:STR_BITS-1] rx_buffer = 0;
  
  integer kdx = 0;
  
  always @ ( posedge clk )
  if ( rst ) begin
      tx_state <= IDLE;
      idx <= 0;
      jdx <= 0;
      I <= 0;
      Q <= 0;
      interrupt <= 0;
  end else
  if ( en ) begin
    s_axis_tready <= 0;
    case ( tx_state )
      IDLE: begin
        if ( s_axis_tvalid ) begin
          tx_state <= AXI_RX;
          axi_next <= PRESYNC;
          idx <= 0;
          jdx <= 0;
          s_axis_tready <= 1;
          tx_bytes <= 0;
        end
      end
      PRESYNC,
      STARTCODE,
      MSGLEN,
      MSGBODY,
      POSTSYNC: begin
        if ( new_sample ) begin
          if ( idx == idx_max_val && jdx == SPS - 1 ) begin
            idx <= 0;
            jdx <= 0;
            tx_state <= tx_next;
            if ( tx_next == AXI_RX ) begin
              axi_next <= STARTCODE;
              s_axis_tready <= 1;
              tx_bytes <= 0;
            end
          end else
          if ( jdx == SPS - 1 ) begin
            idx <= idx + 1;
            jdx <= 0;
          end else begin
            jdx <= jdx + 1;
          end
        end            
      end
      AXI_RX: begin
        s_axis_tready <= 1;
        if ( s_axis_tvalid ) begin
          message_buffer[(tx_bytes*8)+:8] <= s_axis_tdata[7:0];
          tx_bytes <= tx_bytes + 1;
          if ( s_axis_tlast ) begin
            tx_state <= axi_next;
            s_axis_tready <= 0;
          end
        end
      end
    endcase
    
    
    m_axis_tvalid <= 0;
    interrupt <= 0;
    
    case ( rx_state )
      READLEN: begin
          if ( new_symbol ) begin
            rx_len[(kdx*BITS_PER_SYMBOL)+:BITS_PER_SYMBOL] <= rx_symbol;
            if ( kdx == 3 ) begin
              rx_state <= READBODY;
              kdx <= 0;
            end
            else begin
              kdx <= kdx + 1;
            end
          end
      end
      READBODY: begin
        if ( new_symbol ) begin
          rx_buffer[(kdx*BITS_PER_SYMBOL)+:BITS_PER_SYMBOL] <= rx_symbol;
          if ( kdx == rx_len - 1 ) begin
            rx_state <= AXI_TX;
            kdx <= 0;
            interrupt <= 1;
          end
          else begin
            kdx <= kdx + 1;
          end
        end
      end
      AXI_TX: begin
        m_axis_tvalid <= 1;
        if ( m_axis_tready && m_axis_tvalid ) begin
          m_axis_tvalid <= ( kdx == rx_bytes ) ? 0 : 1;
          m_axis_tdata <=  ( kdx == rx_bytes ) ? 32'b0 : {24'b0, rx_buffer[kdx*8 +: 8]};
          m_axis_tlast <=  ( kdx == rx_bytes - 1 ) ? 1 : 0;   
          kdx <=           ( kdx == rx_bytes ) ? 0 : kdx + 1;
          rx_state <=      ( kdx == rx_bytes ) ? READLEN : AXI_TX;
        end
      end
    endcase
    
  end

  localparam [DWIDTH-1:0] ONE = 2**DFRAC;
  localparam [DWIDTH-1:0] ZERO = 0;
  
  always @* begin
    case ( tx_state )
    // The synchronization is a stream of ones and zeros, which aid both the
    // costas loop and timing error detector.
      PRESYNC: begin 
        I               = ONE;
        Q               = ZERO;
        idx_max_val     = EQ_LEN - 1;
        tx_next         = STARTCODE;
      end            
      STARTCODE: begin  
        if ( idx < FRAME_LEN ) begin
          I             = frame_header_seq[idx][0];
          Q             = frame_header_seq[idx][1];
        end
        else begin
          I             = ZERO;
          Q             = ZERO;
        end
        idx_max_val     = FRAME_LEN;
        tx_next         = MSGLEN;
      end
      MSGLEN: begin
        I               = constellation[tx_len[(idx*BITS_PER_SYMBOL)+:BITS_PER_SYMBOL]][0];
        Q               = constellation[tx_len[(idx*BITS_PER_SYMBOL)+:BITS_PER_SYMBOL]][1];
        idx_max_val     = 3;
        tx_next         = MSGBODY;
      end
      MSGBODY: begin
        I               = constellation[message_buffer[(idx*BITS_PER_SYMBOL)+:BITS_PER_SYMBOL]][0];
        Q               = constellation[message_buffer[(idx*BITS_PER_SYMBOL)+:BITS_PER_SYMBOL]][1];
        idx_max_val     = tx_len - 1;
        tx_next         = POSTSYNC;
      end
      POSTSYNC: begin
        I               = ONE;
        Q               = ZERO;
        idx_max_val     = (EQ_LEN/2) - 1;
        if ( s_axis_tvalid ) begin
          tx_next       = AXI_RX;
        end else
        if ( start ) begin
          tx_next       = STARTCODE;
        end else begin
          tx_next       = IDLE;
        end
      end
      default: begin
        {I, Q}          = ZERO;
        idx_max_val     = ZERO;
        tx_next         = IDLE;
      end
    endcase
      
  end

endmodule
