// AXI4 Master - Burst-capable master interface
// Issues transactions from a command FIFO to the AXI4 bus
`ifndef AXI4_MASTER_SV
`define AXI4_MASTER_SV

module axi4_master #(
  parameter ADDR_WIDTH = 32,
  parameter DATA_WIDTH = 64,
  parameter ID_WIDTH   = 4
)(
  input  logic aclk,
  input  logic aresetn,

  // Write Address Channel
  output logic [ID_WIDTH-1:0]   awid,
  output logic [ADDR_WIDTH-1:0] awaddr,
  output logic [7:0]            awlen,
  output logic [2:0]            awsize,
  output logic [1:0]            awburst,
  output logic                  awvalid,
  input  logic                  awready,

  // Write Data Channel
  output logic [DATA_WIDTH-1:0]   wdata,
  output logic [DATA_WIDTH/8-1:0] wstrb,
  output logic                    wlast,
  output logic                    wvalid,
  input  logic                    wready,

  // Write Response Channel
  input  logic [ID_WIDTH-1:0] bid,
  input  logic [1:0]          bresp,
  input  logic                bvalid,
  output logic                bready,

  // Read Address Channel
  output logic [ID_WIDTH-1:0]   arid,
  output logic [ADDR_WIDTH-1:0] araddr,
  output logic [7:0]            arlen,
  output logic [2:0]            arsize,
  output logic [1:0]            arburst,
  output logic                  arvalid,
  input  logic                  arready,

  // Read Data Channel
  input  logic [ID_WIDTH-1:0]   rid,
  input  logic [DATA_WIDTH-1:0] rdata,
  input  logic [1:0]            rresp,
  input  logic                  rlast,
  input  logic                  rvalid,
  output logic                  rready,

  // Command interface (from testbench)
  input  logic                    cmd_valid,
  output logic                    cmd_ready,
  input  logic                    cmd_write,     // 1=write, 0=read
  input  logic [ADDR_WIDTH-1:0]   cmd_addr,
  input  logic [7:0]              cmd_len,
  input  logic [2:0]              cmd_size,
  input  logic [1:0]              cmd_burst,
  input  logic [DATA_WIDTH-1:0]   cmd_wdata,
  input  logic [DATA_WIDTH/8-1:0] cmd_wstrb,
  output logic [DATA_WIDTH-1:0]   rsp_rdata,
  output logic [1:0]              rsp_resp,
  output logic                    rsp_valid
);

  localparam STRB_WIDTH = DATA_WIDTH / 8;

  typedef enum logic [1:0] {M_IDLE, M_WR_ADDR, M_WR_DATA, M_WR_RESP,
                             M_RD_ADDR, M_RD_DATA} master_state_t;
  master_state_t state;

  logic [7:0]            beat_cnt;
  logic [7:0]            cmd_len_r;
  logic [ID_WIDTH-1:0]   txn_id;

  always_ff @(posedge aclk or negedge aresetn) begin
    if (!aresetn) begin
      state    <= M_IDLE;
      awvalid  <= 1'b0;
      wvalid   <= 1'b0;
      wlast    <= 1'b0;
      arvalid  <= 1'b0;
      bready   <= 1'b0;
      rready   <= 1'b0;
      cmd_ready <= 1'b0;
      rsp_valid <= 1'b0;
      txn_id   <= '0;
      beat_cnt <= '0;
    end else begin
      rsp_valid <= 1'b0;

      case (state)
        M_IDLE: begin
          cmd_ready <= 1'b1;
          awvalid   <= 1'b0;
          arvalid   <= 1'b0;
          wvalid    <= 1'b0;
          bready    <= 1'b0;
          rready    <= 1'b0;
          if (cmd_valid && cmd_ready) begin
            cmd_ready  <= 1'b0;
            cmd_len_r  <= cmd_len;
            beat_cnt   <= '0;
            if (cmd_write) begin
              awid    <= txn_id;
              awaddr  <= cmd_addr;
              awlen   <= cmd_len;
              awsize  <= cmd_size;
              awburst <= cmd_burst;
              awvalid <= 1'b1;
              state   <= M_WR_ADDR;
            end else begin
              arid    <= txn_id;
              araddr  <= cmd_addr;
              arlen   <= cmd_len;
              arsize  <= cmd_size;
              arburst <= cmd_burst;
              arvalid <= 1'b1;
              state   <= M_RD_ADDR;
            end
            txn_id <= txn_id + 1;
          end
        end

        M_WR_ADDR: begin
          if (awvalid && awready) begin
            awvalid <= 1'b0;
            wdata   <= cmd_wdata;
            wstrb   <= cmd_wstrb;
            wlast   <= (cmd_len_r == 0);
            wvalid  <= 1'b1;
            state   <= M_WR_DATA;
          end
        end

        M_WR_DATA: begin
          if (wvalid && wready) begin
            if (wlast) begin
              wvalid <= 1'b0;
              bready <= 1'b1;
              state  <= M_WR_RESP;
            end else begin
              beat_cnt <= beat_cnt + 1;
              wlast    <= (beat_cnt + 1 == cmd_len_r);
            end
          end
        end

        M_WR_RESP: begin
          if (bvalid && bready) begin
            bready    <= 1'b0;
            rsp_resp  <= bresp;
            rsp_valid <= 1'b1;
            state     <= M_IDLE;
          end
        end

        M_RD_ADDR: begin
          if (arvalid && arready) begin
            arvalid <= 1'b0;
            rready  <= 1'b1;
            state   <= M_RD_DATA;
          end
        end

        M_RD_DATA: begin
          if (rvalid && rready) begin
            rsp_rdata <= rdata;
            rsp_resp  <= rresp;
            if (rlast) begin
              rready    <= 1'b0;
              rsp_valid <= 1'b1;
              state     <= M_IDLE;
            end
          end
        end

        default: state <= M_IDLE;
      endcase
    end
  end

endmodule : axi4_master
`endif // AXI4_MASTER_SV
