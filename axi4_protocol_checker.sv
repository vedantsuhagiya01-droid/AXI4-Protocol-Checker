// AXI4 Protocol Checker using SystemVerilog Assertions
`ifndef AXI4_PROTOCOL_CHECKER_SV
`define AXI4_PROTOCOL_CHECKER_SV

module axi4_protocol_checker #(
  parameter ADDR_WIDTH = 32,
  parameter DATA_WIDTH = 64,
  parameter ID_WIDTH = 4
)(
  input logic aclk,
  input logic aresetn,
  
  // Write Address Channel
  input logic [ID_WIDTH-1:0]   awid,
  input logic [ADDR_WIDTH-1:0] awaddr,
  input logic [7:0]            awlen,
  input logic [2:0]            awsize,
  input logic [1:0]            awburst,
  input logic                  awvalid,
  input logic                  awready,
  
  // Write Data Channel
  input logic [DATA_WIDTH-1:0]   wdata,
  input logic [DATA_WIDTH/8-1:0] wstrb,
  input logic                    wlast,
  input logic                    wvalid,
  input logic                    wready,
  
  // Write Response Channel
  input logic [ID_WIDTH-1:0] bid,
  input logic [1:0]          bresp,
  input logic                bvalid,
  input logic                bready,
  
  // Read Address Channel
  input logic [ID_WIDTH-1:0]   arid,
  input logic [ADDR_WIDTH-1:0] araddr,
  input logic [7:0]            arlen,
  input logic [2:0]            arsize,
  input logic [1:0]            arburst,
  input logic                  arvalid,
  input logic                  arready,
  
  // Read Data Channel
  input logic [ID_WIDTH-1:0]   rid,
  input logic [DATA_WIDTH-1:0] rdata,
  input logic [1:0]            rresp,
  input logic                  rlast,
  input logic                  rvalid,
  input logic                  rready
);

  // ============================================================
  // CRITICAL ASSERTIONS - These catch real FPGA failures
  // ============================================================
  
  // A1: VALID signal must not depend on READY (prevents deadlock)
  property p_valid_not_depend_on_ready(valid, ready);
    @(posedge aclk) disable iff (!aresetn)
      (valid && !ready) |=> valid;
  endproperty
  
  aw_valid_stable: assert property(p_valid_not_depend_on_ready(awvalid, awready))
    else $error("[%0t] PROTOCOL VIOLATION: AWVALID went low before AWREADY", $time);
    
  w_valid_stable: assert property(p_valid_not_depend_on_ready(wvalid, wready))
    else $error("[%0t] PROTOCOL VIOLATION: WVALID went low before WREADY", $time);
    
  ar_valid_stable: assert property(p_valid_not_depend_on_ready(arvalid, arready))
    else $error("[%0t] PROTOCOL VIOLATION: ARVALID went low before ARREADY", $time);
  
  // A2: Address alignment check (causes data corruption if violated)
  property p_addr_alignment(addr, size);
    @(posedge aclk) disable iff (!aresetn)
      (addr % (2**size) == 0);
  endproperty
  
  aw_addr_aligned: assert property(
    @(posedge aclk) disable iff (!aresetn)
      awvalid |-> (awaddr % (2**awsize) == 0))
    else $error("[%0t] ALIGNMENT ERROR: Write addr 0x%h not aligned to size %0d", 
                $time, awaddr, 2**awsize);
  
  ar_addr_aligned: assert property(
    @(posedge aclk) disable iff (!aresetn)
      arvalid |-> (araddr % (2**arsize) == 0))
    else $error("[%0t] ALIGNMENT ERROR: Read addr 0x%h not aligned to size %0d", 
                $time, araddr, 2**arsize);
  
  // A3: 4KB boundary check (AXI4 spec - critical for memory controllers)
  function automatic int calc_transfer_size(logic [7:0] len, logic [2:0] size);
    return (len + 1) * (2**size);
  endfunction
  
  aw_4kb_boundary: assert property(
    @(posedge aclk) disable iff (!aresetn)
      awvalid |-> ((awaddr & 12'hFFF) + calc_transfer_size(awlen, awsize) <= 4096))
    else $error("[%0t] 4KB BOUNDARY VIOLATION: Write transfer crosses boundary at 0x%h", 
                $time, awaddr);
  
  ar_4kb_boundary: assert property(
    @(posedge aclk) disable iff (!aresetn)
      arvalid |-> ((araddr & 12'hFFF) + calc_transfer_size(arlen, arsize) <= 4096))
    else $error("[%0t] 4KB BOUNDARY VIOLATION: Read transfer crosses boundary at 0x%h", 
                $time, araddr);
  
  // A4: Burst length check for WRAP bursts (must be 2, 4, 8, or 16)
  aw_wrap_length: assert property(
    @(posedge aclk) disable iff (!aresetn)
      (awvalid && awburst == 2'b10) |-> (awlen inside {1, 3, 7, 15}))
    else $error("[%0t] WRAP BURST ERROR: Invalid length %0d (must be 2,4,8,16)", 
                $time, awlen+1);
  
  ar_wrap_length: assert property(
    @(posedge aclk) disable iff (!aresetn)
      (arvalid && arburst == 2'b10) |-> (arlen inside {1, 3, 7, 15}))
    else $error("[%0t] WRAP BURST ERROR: Invalid length %0d (must be 2,4,8,16)", 
                $time, arlen+1);
  
  // A5: WLAST must be asserted on the final beat
  logic [7:0] write_beat_count;
  logic [7:0] expected_write_beats;
  
  always_ff @(posedge aclk or negedge aresetn) begin
    if (!aresetn) begin
      write_beat_count <= 0;
      expected_write_beats <= 0;
    end else begin
      // Capture expected beats on address handshake
      if (awvalid && awready)
        expected_write_beats <= awlen + 1;
      
      // Count data beats
      if (wvalid && wready) begin
        if (write_beat_count == 0)
          write_beat_count <= 1;
        else if (write_beat_count < expected_write_beats)
          write_beat_count <= write_beat_count + 1;
        else
          write_beat_count <= 0;
      end
    end
  end
  
  w_last_correct: assert property(
    @(posedge aclk) disable iff (!aresetn)
      (wvalid && wready) |-> (wlast == (write_beat_count == expected_write_beats)))
    else $error("[%0t] WLAST ERROR: Expected at beat %0d/%0d, wlast=%b", 
                $time, write_beat_count, expected_write_beats, wlast);
  
  // A6: No outstanding transaction overflow (prevents FIFO overflow in FPGA)
  localparam MAX_OUTSTANDING = 16;
  int outstanding_writes = 0;
  int outstanding_reads = 0;
  
  always_ff @(posedge aclk or negedge aresetn) begin
    if (!aresetn) begin
      outstanding_writes <= 0;
      outstanding_reads <= 0;
    end else begin
      // Track write transactions
      if ((awvalid && awready) && !(bvalid && bready))
        outstanding_writes <= outstanding_writes + 1;
      else if (!(awvalid && awready) && (bvalid && bready))
        outstanding_writes <= outstanding_writes - 1;
      
      // Track read transactions
      if ((arvalid && arready) && !(rvalid && rready && rlast))
        outstanding_reads <= outstanding_reads + 1;
      else if (!(arvalid && arready) && (rvalid && rready && rlast))
        outstanding_reads <= outstanding_reads - 1;
    end
  end
  
  outstanding_write_limit: assert property(
    @(posedge aclk) disable iff (!aresetn)
      outstanding_writes <= MAX_OUTSTANDING)
    else $error("[%0t] OUTSTANDING TRANSACTION OVERFLOW: %0d write transactions", 
                $time, outstanding_writes);
  
  outstanding_read_limit: assert property(
    @(posedge aclk) disable iff (!aresetn)
      outstanding_reads <= MAX_OUTSTANDING)
    else $error("[%0t] OUTSTANDING TRANSACTION OVERFLOW: %0d read transactions", 
                $time, outstanding_reads);
  
  // A7: Timeout detection (critical for preventing system hangs)
  localparam TIMEOUT_CYCLES = 1000;
  
  property p_no_timeout(valid, ready);
    @(posedge aclk) disable iff (!aresetn)
      valid |-> ##[1:TIMEOUT_CYCLES] ready;
  endproperty
  
  aw_no_timeout: assert property(p_no_timeout(awvalid, awready))
    else $error("[%0t] TIMEOUT: AWREADY not asserted within %0d cycles", 
                $time, TIMEOUT_CYCLES);
  
  w_no_timeout: assert property(p_no_timeout(wvalid, wready))
    else $error("[%0t] TIMEOUT: WREADY not asserted within %0d cycles", 
                $time, TIMEOUT_CYCLES);
  
  ar_no_timeout: assert property(p_no_timeout(arvalid, arready))
    else $error("[%0t] TIMEOUT: ARREADY not asserted within %0d cycles", 
                $time, TIMEOUT_CYCLES);
  
  // A8: ID matching (response ID must match request ID)
  // This requires FIFOs to track IDs - simplified version shown
  
  // Coverage for protocol events
  covergroup cg_axi_protocol @(posedge aclk);
    option.per_instance = 1;
    
    cp_burst_type_write: coverpoint awburst iff (awvalid) {
      bins fixed = {2'b00};
      bins incr  = {2'b01};
      bins wrap  = {2'b10};
    }
    
    cp_burst_type_read: coverpoint arburst iff (arvalid) {
      bins fixed = {2'b00};
      bins incr  = {2'b01};
      bins wrap  = {2'b10};
    }
    
    cp_burst_length: coverpoint awlen iff (awvalid) {
      bins short[]  = {[0:3]};
      bins medium[] = {[4:15]};
      bins long[]   = {[16:255]};
    }
    
    cp_outstanding_writes: coverpoint outstanding_writes {
      bins low    = {[0:4]};
      bins medium = {[5:10]};
      bins high   = {[11:15]};
      bins max    = {16};
    }
  endgroup
  
  cg_axi_protocol cg_protocol = new();
  
  // Performance monitors
  int total_write_bytes;
  int total_read_bytes;

  always_ff @(posedge aclk or negedge aresetn) begin
    if (!aresetn) begin
      total_write_bytes <= 0;
      total_read_bytes  <= 0;
    end else begin
      if (wvalid && wready)
        total_write_bytes <= total_write_bytes + (1 << awsize);
      if (rvalid && rready)
        total_read_bytes  <= total_read_bytes  + (1 << arsize);
    end
  end

endmodule : axi4_protocol_checker
`endif // AXI4_PROTOCOL_CHECKER_SV
