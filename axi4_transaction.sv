// AXI4 Transaction Class
`ifndef AXI4_TRANSACTION_SV
`define AXI4_TRANSACTION_SV

`include "axi4_pkg.sv"

class axi4_transaction;
  import axi4_pkg::*;
  
  // Transaction Type
  rand bit is_write;
  
  // Address Channel
  rand bit [ADDR_WIDTH-1:0] addr;
  rand bit [ID_WIDTH-1:0]   id;
  rand bit [7:0]            len;      // Burst length (0-255)
  rand burst_size_e         size;
  rand burst_type_e         burst;
  rand bit                  lock;
  rand bit [3:0]            cache;
  rand bit [2:0]            prot;
  rand bit [3:0]            qos;
  
  // Data Channel (Write)
  rand bit [DATA_WIDTH-1:0] data[];
  rand bit [STRB_WIDTH-1:0] strb[];
  rand bit                  last[];
  
  // Response Channel
  resp_type_e               resp[];
  
  // Timing
  int unsigned              addr_delay;
  int unsigned              data_delay[];
  time                      start_time;
  time                      end_time;
  
  // Status
  transaction_status_e      status;
  
  // Constraints for realistic traffic patterns
  
  // CRITICAL: Address must be aligned to burst size
  constraint c_addr_alignment {
    addr % (2**size) == 0;
  }
  
  // Burst length constraints (AXI4 spec)
  constraint c_burst_len {
    len inside {[0:255]};
    
    // WRAP bursts must be 2, 4, 8, or 16 beats
    if (burst == WRAP) {
      len inside {1, 3, 7, 15};
    }
    
    // Realistic: Most bursts are short
    len dist {[0:3] := 60, [4:15] := 30, [16:255] := 10};
  }
  
  // Burst size should not exceed data bus width
  constraint c_burst_size {
    2**size <= DATA_WIDTH/8;
    
    // Realistic: Prefer full data width transfers
    size dist {SIZE_8B := 50, SIZE_4B := 30, SIZE_2B := 15, SIZE_1B := 5};
  }
  
  // 4KB boundary constraint (AXI4 spec requirement)
  constraint c_4kb_boundary {
    // Address + total transfer size must not cross 4KB boundary
    (addr & 12'hFFF) + ((len + 1) * (2**size)) <= 4096;
  }
  
  // Cache and protection bits
  constraint c_cache_prot {
    cache inside {4'b0000, 4'b0010, 4'b0011, 4'b1111};
    prot inside {3'b000, 3'b001, 3'b010};
  }
  
  // QoS realistic values
  constraint c_qos {
    qos dist {0 := 40, [1:3] := 40, [4:15] := 20};
  }
  
  // Constructor
  function new();
    status = IDLE;
    addr_delay = 0;
  endfunction
  
  // Post-randomize to allocate dynamic arrays
  function void post_randomize();
    int num_beats = len + 1;
    
    data = new[num_beats];
    strb = new[num_beats];
    last = new[num_beats];
    resp = new[num_beats];
    data_delay = new[num_beats];
    
    // Randomize data and strobes
    foreach(data[i]) begin
      data[i] = $random;
      strb[i] = {STRB_WIDTH{1'b1}};  // All bytes valid by default
      last[i] = (i == num_beats-1);
      data_delay[i] = $urandom_range(0, 3);  // Add random delays
    end
  endfunction
  
  // Convert transaction to string for debugging
  function string convert2string();
    string s;
    s = $sformatf("\n=== AXI4 Transaction ===");
    s = {s, $sformatf("\nType: %s", is_write ? "WRITE" : "READ")};
    s = {s, $sformatf("\nID: 0x%0h", id)};
    s = {s, $sformatf("\nAddress: 0x%0h", addr)};
    s = {s, $sformatf("\nLength: %0d beats", len+1)};
    s = {s, $sformatf("\nSize: %0d bytes", 2**size)};
    s = {s, $sformatf("\nBurst: %s", burst.name())};
    s = {s, $sformatf("\nStatus: %s", status.name())};
    if (end_time > start_time)
      s = {s, $sformatf("\nLatency: %0t", end_time - start_time)};
    return s;
  endfunction
  
  // Deep copy
  function axi4_transaction copy();
    axi4_transaction txn = new();
    txn.is_write = this.is_write;
    txn.addr = this.addr;
    txn.id = this.id;
    txn.len = this.len;
    txn.size = this.size;
    txn.burst = this.burst;
    txn.lock = this.lock;
    txn.cache = this.cache;
    txn.prot = this.prot;
    txn.qos = this.qos;
    
    txn.data = new[this.data.size()];
    txn.strb = new[this.strb.size()];
    txn.last = new[this.last.size()];
    
    foreach(this.data[i]) begin
      txn.data[i] = this.data[i];
      txn.strb[i] = this.strb[i];
      txn.last[i] = this.last[i];
    end
    
    return txn;
  endfunction
  
endclass : axi4_transaction
`endif // AXI4_TRANSACTION_SV
