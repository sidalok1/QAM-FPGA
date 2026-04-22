module Controller
#(
  //  Total word length of the output symbols
  parameter SYMBOL_WIDTH                      = 16,
  //  Length of the fractional portion of a signal
  parameter SYMBOL_FRAC                       = 14,
  //  Output sample rate in hertz
  parameter SAMPLE_RATE                       = 6_000_000,
  //  Symbol rate in hertz, together with last value determin sps
  parameter SYMBOL_RATE                       = 50_000,
  parameter SYNC_LEN                          = 32
)
(
  //  Input clock, should be at the frequency specified by parameter
  input wire                              clk,
  //  General clocked logic enable signal
  input wire                              en,
  //  Synchronous reset
  input wire                              rst,
  //  Signal to begin a transmission
  input wire                              start,
  input wire                              new_sample,
  //  Output symbols in two's complement form at the requested sample rate
  output reg signed [SYMBOL_WIDTH-1:0]    sample,
  
  //  Axi stream ports
  input wire [31:0]                       s_axis_tdata,
//    input wire [3:0]                        s_axis_tkeep,
  input wire                              s_axis_tlast,
  input wire                              s_axis_tvalid,
  output reg                              s_axis_tready,
  
  output reg [31:0]                       m_axis_tdata,
//    output reg [3:0]                        m_axis_tkeep,
  output reg                              m_axis_tlast,
  output reg                              m_axis_tvalid,
  input wire                              m_axis_tready,
  
  output reg                              interrupt,
  
  //  Controller also receives information from receiver hardware
  input wire                              new_bit,
  input wire                              rx_bit,
  output reg                              msg_found,
  output reg                              inv_msg_found
);
  //  Calculated bitlength of the symbol representing the nonfractional number
  localparam SYMBOL_WHOLE     = SYMBOL_WIDTH - SYMBOL_FRAC;
  //  Two's complement symbols parameterized to given bitwidths
  localparam SYMBOL_ZERO      = {SYMBOL_WIDTH{1'b0}};
  localparam SYMBOL_ONE       = {{SYMBOL_WHOLE-1{1'b0}}, 1'b1, {SYMBOL_FRAC{1'b0}}};
  localparam SYMBOL_NEG_ONE   = {{SYMBOL_WHOLE{1'b1}}, {SYMBOL_FRAC{1'b0}}};
  
  initial begin
    sample          = SYMBOL_ZERO;
    msg_found       = 0;
    inv_msg_found   = 0;
    s_axis_tready = 0;
    m_axis_tdata = 0;
//        m_axis_tkeep = 0;
    m_axis_tlast = 0;
    m_axis_tvalid = 0;
    interrupt = 0;
  end
  /*
      Memory containing the output message in ascii. This is hard coded but obviously
      this will ideally not be the case in the future. Should be (relatively) trivial
      to change this to arbitrary messages. Doing so is out of the scope of this demo
  */
  localparam MAX_STR_LEN                  = 256;
  localparam STR_BITS                     = MAX_STR_LEN * 8;
  reg [0:STR_BITS-1] message_buffer       = 0;
  reg [7:0] tx_len                        = 0;
  // Maximum value of idx before state should change
  reg [10:0] idx_max_val;
  /*
      Presently the matlab simulation uses a message length field to indicate how
      long the message is. I am leaning toward changing this to a simple barker
      code at the start and end of the message. The current approach requires the
      receiver to lock on to the message by the first barker code in order to know
      when it has received the full message (and can stop listening). Barker codes at
      either end make it so that the receiver only needs to locked on by the end of
      the message to know when to stop listening (if the start and stop codes are
      different). This does add the complexity that we must worry about the stop code
      appearing in the message.
  */
  localparam reg [0:10] start_code  = 11'b11100010010;
  
  //  Symbols per sample
  localparam integer SPS                  = SAMPLE_RATE / SYMBOL_RATE;
  
  //  General registers used for counting indices
  reg [10:0] idx                          = 0;
  reg [$clog2(SPS)-1:0] jdx               = 0;
  
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
  
  // Below are combinational block variables used on rhs in clocked block
  // What sample should register on the sample clock
  reg [SYMBOL_WIDTH-1:0] sample_select;
  // Combinational assignment of next state value
  reg [tx_STATES-1:0] tx_next, axi_next = IDLE;
  
  localparam rx_STATES                    = 4;
  localparam [rx_STATES-1:0] DETECT       = 4'b0001;
  localparam [rx_STATES-1:0] READLEN      = 4'b0010;
  localparam [rx_STATES-1:0] READBODY     = 4'b0100;
  localparam [rx_STATES-1:0] AXI_TX       = 4'b1000;
  reg [rx_STATES-1:0] rx_state            = DETECT;

  reg invert = 0;
  wire in_bit = invert == 1 ? ~rx_bit : rx_bit;
  
  localparam reg [12:0] WRAP_HEADER = 13'b1111100110101;
  reg [12:0] code           = 0;
  
  reg [7:0] rx_len              = 0;
  reg [7:0] rx_buffer [0:255];
  
  integer i = 0;
  initial begin
      for ( i = 0; i < 256; i = i + 1 ) begin
          rx_buffer[i] = 0;
      end
  end
  
  reg write_to_buffer                     = 0;
  reg [7:0] rx_byte                       = 0;
  reg [7:0] kdx = 0, hdx = 0;
  
  always @ ( posedge clk )
  if ( rst ) begin
      tx_state <= IDLE;
      idx <= 0;
      jdx <= 0;
      sample <= SYMBOL_ZERO;
      interrupt <= 0;
//        rx_state <= DETECT;
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
          tx_len <= 0;
        end
      end
      PRESYNC,
      STARTCODE,
      MSGLEN,
      MSGBODY,
      POSTSYNC: begin
        if ( new_sample ) begin
          sample <= sample_select;
          if ( idx == idx_max_val && jdx == SPS - 1 ) begin
            idx <= 0;
            jdx <= 0;
            tx_state <= tx_next;
            if ( tx_next == AXI_RX ) begin
              axi_next <= STARTCODE;
              s_axis_tready <= 1;
              tx_len <= 0;
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
          message_buffer[(tx_len*8)+:8] <= s_axis_tdata[7:0];
          tx_len <= tx_len + 1;
          if ( s_axis_tlast ) begin
            tx_state <= axi_next;
            s_axis_tready <= 0;
          end
        end
      end
    endcase
    
    msg_found <= 0;
    inv_msg_found <= 0;
    
    write_to_buffer <= 0;
    
    m_axis_tvalid <= 0;
    interrupt <= 0;
    
    case ( rx_state )
      DETECT: begin
          if ( new_bit ) begin
            code[0] <= rx_bit;
            code[12:1] <= code[11:0];
          end
          if ( code[10:0] == start_code ) begin
            code <= 0;
            msg_found <= 1;
            invert <= 0;
            rx_state <= READLEN;
          end else
          if ( code[10:0] == ~start_code ) begin
            code <= 0;
            inv_msg_found <= 1;
            invert <= 1;
            rx_state <= READLEN;
          end else
          if ( code == WRAP_HEADER ) begin
            code <= 0;
            msg_found <= 1;
            invert <= 0;
            rx_state <= READBODY;
            rx_len <= 8'd6;
          end else
          if ( code == ~WRAP_HEADER ) begin
            code <= 0;
            inv_msg_found <= 1;
            invert <= 1;
            rx_state <= READBODY;
            rx_len <= 8'd6;
          end
          kdx <= 0;
      end
      READLEN: begin
          if ( new_bit ) begin
            rx_len[0] <= in_bit;
            rx_len[7:1] <= rx_len[6:0];
            
            if ( kdx == 7 ) begin
              kdx <= 0;
              hdx <= 0;
              rx_state <= READBODY;
            end else begin
              kdx <= kdx + 1;
            end
          end
      end
      READBODY: begin
        if ( new_bit ) begin
          rx_byte[0] <= in_bit;
          rx_byte[7:1] <= rx_byte[6:0];
          
          if ( kdx == 7 ) begin
            kdx <= 0;
            write_to_buffer <= 1; // goes low ever other possible cycle
          end else begin
            kdx <= kdx + 1;
          end
        end
          
        if ( write_to_buffer ) begin
          rx_buffer[hdx] <= rx_byte;
          if ( hdx == rx_len - 1 ) begin
            hdx <= 0;
            kdx <= 0;
            rx_state <= AXI_TX;
            interrupt <= 1;
          end else begin
            hdx <= hdx + 1;
          end
        end
      end
      AXI_TX: begin
        m_axis_tvalid <= 1;
        if ( m_axis_tready && m_axis_tvalid ) begin
          m_axis_tvalid <= ( hdx == rx_len ) ? 0 : 1;
          m_axis_tdata <=  ( hdx == rx_len ) ? 32'b0 : {24'b0, rx_buffer[hdx]};
          m_axis_tlast <=  ( hdx == rx_len - 1 ) ? 1 : 0;   
          hdx <=           ( hdx == rx_len ) ? 0 : hdx + 1;
          rx_state <=      ( hdx == rx_len ) ? DETECT : AXI_TX;
        end
      end
    endcase
    
    // msg_found <= ( code == start_code ) ? 1 : 0;
    // inv_msg_found <= ( code == ~start_code ) ? 1 : 0;
  end
  
  reg [SYMBOL_WIDTH-1:0] current_symbol;
  reg current_bit;
  
  always @* begin
    case ( tx_state )
    // The synchronization is a stream of ones and zeros, which aid both the
    // costas loop and timing error detector.
      PRESYNC: begin 
        current_bit     = idx % 2;
        idx_max_val     = SYNC_LEN - 1;
        tx_next         = STARTCODE;
      end            
      STARTCODE: begin  
        current_bit     = start_code[idx];
        idx_max_val     = 10;
        tx_next         = MSGLEN;
      end
      MSGLEN: begin
        current_bit     = tx_len[7-idx];
        idx_max_val     = 7;
        tx_next         = MSGBODY;
      end
      MSGBODY: begin
        current_bit     = message_buffer[idx];
        idx_max_val     = (tx_len * 8) - 1;
        tx_next         = POSTSYNC;
      end
      POSTSYNC: begin
        current_bit     = idx % 2;
        idx_max_val     = (SYNC_LEN/2) - 1;
        if ( s_axis_tvalid ) begin
          tx_next     = AXI_RX;
        end else
        if ( start ) begin
          tx_next     = STARTCODE;
        end else begin
          tx_next         = IDLE;
        end
      end
      default: begin   
        current_bit     = 0;
        idx_max_val     = 0;
        tx_next         = IDLE;
      end
    endcase
    current_symbol = ( current_bit == 0 ) ? SYMBOL_NEG_ONE : SYMBOL_ONE;
    // Recall, for upsampling, a new symbol is added only every SPS, and
    // otherwise is zero
    sample_select = ( jdx == 0 ) ? current_symbol : SYMBOL_ZERO;
      
  end

endmodule
