// AXI4 Slave - Simple memory-mapped slave DUT
// Supports INCR, FIXED, WRAP bursts; 4KB-addressed SRAM model
`ifndef AXI4_SLAVE_SV
`define AXI4_SLAVE_SV

module axi4_slave #(
  parameter ADDR_WIDTH = 32,
  parameter DATA_WIDTH = 64,
  parameter ID_WIDTH   = 4,
  parameter MEM_DEPTH  = 4096        // bytes
)(
  input  logic aclk,
  input  logic aresetn,

  // Write Address Channel
  input  logic [ID_WIDTH-1:0]   awid,
  input  logic [ADDR_WIDTH-1:0] awaddr,
  input  logic [7:0]            awlen,
  input  logic [2:0]            awsize,
  input  logic [1:0]            awburst,
  input  logic                  awvalid,
  output logic                  awready,

  // Write Data Channel
  input  logic [DATA_WIDTH-1:0]   wdata,
  input  logic [DATA_WIDTH/8-1:0] wstrb,
  input  logic                    wlast,
  input  logic                    wvalid,
  output logic                    wready,

  // Write Response Channel
  output logic [ID_WIDTH-1:0] bid,
  output logic [1:0]          bresp,
  output logic                bvalid,
  input  logic                bready,

  // Read Address Channel
  input  logic [ID_WIDTH-1:0]   arid,
  input  logic [ADDR_WIDTH-1:0] araddr,
  input  logic [7:0]            arlen,
  input  logic [2:0]            arsize,
  input  logic [1:0]            arburst,
  input  logic                  arvalid,
  output logic                  arready,

  // Read Data Channel
  output logic [ID_WIDTH-1:0]   rid,
  output logic [DATA_WIDTH-1:0] rdata,
  output logic [1:0]            rresp,
  output logic                  rlast,
  output logic                  rvalid,
  input  logic                  rready
);

  localparam STRB_WIDTH = DATA_WIDTH / 8;

  // Byte-addressable memory
  logic [7:0] mem [0:MEM_DEPTH-1];

  // Write state machine
  typedef enum logic [1:0] {W_IDLE, W_DATA, W_RESP} wr_state_t;
  wr_state_t wr_state;

  logic [ID_WIDTH-1:0]   aw_id_r;
  logic [ADDR_WIDTH-1:0] aw_addr_r;
  logic [7:0]            aw_len_r;
  logic [2:0]            aw_size_r;
  logic [1:0]            aw_burst_r;
  logic [7:0]            wr_beat_cnt;
  logic [ADDR_WIDTH-1:0] wr_cur_addr;

  // Read state machine
  typedef enum logic [1:0] {R_IDLE, R_DATA} rd_state_t;
  rd_state_t rd_state;

  logic [ID_WIDTH-1:0]   ar_id_r;
  logic [ADDR_WIDTH-1:0] ar_addr_r;
  logic [7:0]            ar_len_r;
  logic [2:0]            ar_size_r;
  logic [1:0]            ar_burst_r;
  logic [7:0]            rd_beat_cnt;
  logic [ADDR_WIDTH-1:0] rd_cur_addr;

  // ---------------------------------------------------------------
  // Write FSM
  // ---------------------------------------------------------------
  always_ff @(posedge aclk or negedge aresetn) begin
    if (!aresetn) begin
      wr_state  <= W_IDLE;
      awready   <= 1'b0;
      wready    <= 1'b0;
      bvalid    <= 1'b0;
      bid       <= '0;
      bresp     <= 2'b00;
      wr_beat_cnt <= '0;
    end else begin
      case (wr_state)
        W_IDLE: begin
          awready <= 1'b1;
          wready  <= 1'b0;
          bvalid  <= 1'b0;
          if (awvalid && awready) begin
            aw_id_r    <= awid;
            aw_addr_r  <= awaddr;
            aw_len_r   <= awlen;
            aw_size_r  <= awsize;
            aw_burst_r <= awburst;
            wr_cur_addr <= awaddr;
            wr_beat_cnt <= '0;
            awready     <= 1'b0;
            wready      <= 1'b1;
            wr_state    <= W_DATA;
          end
        end

        W_DATA: begin
          if (wvalid && wready) begin
            // Write byte lanes with strobe masking
            for (int i = 0; i < STRB_WIDTH; i++) begin
              if (wstrb[i] && (wr_cur_addr + i) < MEM_DEPTH)
                mem[wr_cur_addr + i] <= wdata[i*8 +: 8];
            end

            if (wlast) begin
              wready   <= 1'b0;
              bvalid   <= 1'b1;
              bid      <= aw_id_r;
              bresp    <= 2'b00; // OKAY
              wr_state <= W_RESP;
            end else begin
              // Advance address
              wr_cur_addr <= next_addr(wr_cur_addr, aw_size_r, aw_burst_r,
                                       wr_beat_cnt, aw_len_r);
              wr_beat_cnt <= wr_beat_cnt + 1;
            end
          end
        end

        W_RESP: begin
          if (bvalid && bready) begin
            bvalid   <= 1'b0;
            awready  <= 1'b1;
            wr_state <= W_IDLE;
          end
        end
      endcase
    end
  end

  // ---------------------------------------------------------------
  // Read FSM
  // ---------------------------------------------------------------
  always_ff @(posedge aclk or negedge aresetn) begin
    if (!aresetn) begin
      rd_state    <= R_IDLE;
      arready     <= 1'b0;
      rvalid      <= 1'b0;
      rlast       <= 1'b0;
      rid         <= '0;
      rresp       <= 2'b00;
      rdata       <= '0;
      rd_beat_cnt <= '0;
    end else begin
      case (rd_state)
        R_IDLE: begin
          arready <= 1'b1;
          rvalid  <= 1'b0;
          rlast   <= 1'b0;
          if (arvalid && arready) begin
            ar_id_r    <= arid;
            ar_addr_r  <= araddr;
            ar_len_r   <= arlen;
            ar_size_r  <= arsize;
            ar_burst_r <= arburst;
            rd_cur_addr <= araddr;
            rd_beat_cnt <= '0;
            arready     <= 1'b0;
            rd_state    <= R_DATA;
          end
        end

        R_DATA: begin
          rvalid <= 1'b1;
          rid    <= ar_id_r;
          rresp  <= 2'b00;

          // Pack bytes into read data word
          for (int i = 0; i < STRB_WIDTH; i++) begin
            rdata[i*8 +: 8] <= (rd_cur_addr + i < MEM_DEPTH) ?
                                 mem[rd_cur_addr + i] : 8'hXX;
          end

          rlast <= (rd_beat_cnt == ar_len_r);

          if (rvalid && rready) begin
            if (rd_beat_cnt == ar_len_r) begin
              rvalid      <= 1'b0;
              rlast       <= 1'b0;
              arready     <= 1'b1;
              rd_state    <= R_IDLE;
            end else begin
              rd_cur_addr <= next_addr(rd_cur_addr, ar_size_r, ar_burst_r,
                                       rd_beat_cnt, ar_len_r);
              rd_beat_cnt <= rd_beat_cnt + 1;
            end
          end
        end
      endcase
    end
  end

  // ---------------------------------------------------------------
  // AXI4 burst address calculator
  // ---------------------------------------------------------------
  function automatic logic [ADDR_WIDTH-1:0] next_addr(
    input logic [ADDR_WIDTH-1:0] cur,
    input logic [2:0]            sz,
    input logic [1:0]            burst,
    input logic [7:0]            beat,
    input logic [7:0]            total_len
  );
    logic [ADDR_WIDTH-1:0] inc;
    logic [ADDR_WIDTH-1:0] wrap_mask;
    inc = 1 << sz;
    case (burst)
      2'b00: next_addr = cur;                         // FIXED
      2'b01: next_addr = cur + inc;                   // INCR
      2'b10: begin                                     // WRAP
        wrap_mask = (total_len + 1) * inc - 1;
        next_addr = (cur & ~wrap_mask) |
                    ((cur + inc) & wrap_mask);
      end
      default: next_addr = cur + inc;
    endcase
  endfunction

endmodule : axi4_slave
`endif // AXI4_SLAVE_SV
