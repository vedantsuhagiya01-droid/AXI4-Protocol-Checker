// AXI4 Scoreboard - Data Integrity Checker
`ifndef AXI4_SCOREBOARD_SV
`define AXI4_SCOREBOARD_SV

`include "axi4_transaction.sv"

class axi4_scoreboard;
  import axi4_pkg::*;
  
  // Mailboxes for communication
  mailbox #(axi4_transaction) write_mb;
  mailbox #(axi4_transaction) read_mb;
  
  // Memory model (associative array for sparse addressing)
  bit [7:0] mem [bit[ADDR_WIDTH-1:0]];
  
  // Transaction tracking
  axi4_transaction write_queue[$];
  axi4_transaction read_queue[$];
  
  // Statistics
  int writes_processed;
  int reads_processed;
  int errors_detected;
  int mismatches;
  
  // Outstanding transactions tracking
  axi4_transaction outstanding_writes[bit[ID_WIDTH-1:0]];
  axi4_transaction outstanding_reads[bit[ID_WIDTH-1:0]];
  
  // Constructor
  function new(mailbox #(axi4_transaction) wr_mb, 
               mailbox #(axi4_transaction) rd_mb);
    write_mb = wr_mb;
    read_mb = rd_mb;
    writes_processed = 0;
    reads_processed = 0;
    errors_detected = 0;
    mismatches = 0;
  endfunction
  
  // Main processing task
  task run();
    fork
      process_writes();
      process_reads();
      check_timeouts();
    join_none
  endtask
  
  // Process write transactions
  task process_writes();
    axi4_transaction txn;
    forever begin
      write_mb.get(txn);
      
      if (txn.is_write) begin
        // Store write data in memory model
        write_to_memory(txn);
        writes_processed++;
        
        // Track outstanding write
        outstanding_writes[txn.id] = txn;
        
        $display("[SCOREBOARD %0t] Write processed: ID=%0d, Addr=0x%h, Len=%0d", 
                 $time, txn.id, txn.addr, txn.len+1);
      end
    end
  endtask
  
  // Process read transactions
  task process_reads();
    axi4_transaction txn;
    forever begin
      read_mb.get(txn);
      
      if (!txn.is_write) begin
        // Check read data against memory model
        check_read_data(txn);
        reads_processed++;
        
        // Track outstanding read
        outstanding_reads[txn.id] = txn;
        
        $display("[SCOREBOARD %0t] Read processed: ID=%0d, Addr=0x%h, Len=%0d", 
                 $time, txn.id, txn.addr, txn.len+1);
      end
    end
  endtask
  
  // Write data to memory model
  function void write_to_memory(axi4_transaction txn);
    bit [ADDR_WIDTH-1:0] addr;
    int byte_idx;
    
    addr = txn.addr;
    
    // Process each beat
    for (int beat = 0; beat <= txn.len; beat++) begin
      // Process each byte in the beat
      for (int byte_lane = 0; byte_lane < STRB_WIDTH; byte_lane++) begin
        // Check if this byte is valid (strobe bit set)
        if (txn.strb[beat][byte_lane]) begin
          byte_idx = byte_lane * 8;
          mem[addr + byte_lane] = txn.data[beat][byte_idx +: 8];
        end
      end
      
      // Calculate next address based on burst type
      addr = get_next_addr(addr, txn.size, txn.burst, beat, txn.len);
    end
    
    $display("[SCOREBOARD] Wrote %0d bytes starting at 0x%h", 
             (txn.len + 1) * (2**txn.size), txn.addr);
  endfunction
  
  // Check read data against memory model
  function void check_read_data(axi4_transaction txn);
    bit [ADDR_WIDTH-1:0] addr;
    bit [7:0] expected_byte, actual_byte;
    int byte_idx;
    bit mismatch_found = 0;
    
    addr = txn.addr;
    
    // Process each beat
    for (int beat = 0; beat <= txn.len; beat++) begin
      // Process each byte in the beat
      for (int byte_lane = 0; byte_lane < STRB_WIDTH; byte_lane++) begin
        byte_idx = byte_lane * 8;
        actual_byte = txn.data[beat][byte_idx +: 8];
        
        // Check if this address was written before
        if (mem.exists(addr + byte_lane)) begin
          expected_byte = mem[addr + byte_lane];
          
          if (actual_byte !== expected_byte) begin
            $error("[SCOREBOARD %0t] DATA MISMATCH at 0x%h: Expected=0x%h, Got=0x%h", 
                   $time, addr + byte_lane, expected_byte, actual_byte);
            mismatch_found = 1;
            mismatches++;
          end
        end else begin
          // Address was never written - could be valid if testing read before write
          $display("[SCOREBOARD] Read from unwritten address 0x%h (value=0x%h)", 
                   addr + byte_lane, actual_byte);
        end
      end
      
      // Calculate next address
      addr = get_next_addr(addr, txn.size, txn.burst, beat, txn.len);
    end
    
    if (!mismatch_found) begin
      $display("[SCOREBOARD] Read data verified successfully for ID=%0d", txn.id);
    end else begin
      errors_detected++;
    end
  endfunction
  
  // Calculate next address based on burst type (AXI4 addressing rules)
  function bit [ADDR_WIDTH-1:0] get_next_addr(
    bit [ADDR_WIDTH-1:0] current_addr,
    burst_size_e size,
    burst_type_e burst,
    int beat_num,
    int total_beats
  );
    bit [ADDR_WIDTH-1:0] next_addr;
    int increment;
    bit [ADDR_WIDTH-1:0] wrap_boundary;
    
    increment = 2**size;
    
    case (burst)
      FIXED: begin
        // Address stays the same
        next_addr = current_addr;
      end
      
      INCR: begin
        // Address increments
        next_addr = current_addr + increment;
      end
      
      WRAP: begin
        // Wrapping burst - address wraps at boundary
        wrap_boundary = (total_beats + 1) * increment;
        next_addr = (current_addr + increment) % wrap_boundary;
        
        // Preserve upper address bits
        next_addr = (current_addr & ~(wrap_boundary - 1)) | next_addr;
      end
      
      default: begin
        next_addr = current_addr + increment;
      end
    endcase
    
    return next_addr;
  endfunction
  
  // Check for transaction timeouts
  task check_timeouts();
    const int TIMEOUT_LIMIT = 10000;  // cycles
    time current_time;
    
    forever begin
      #(TIMEOUT_LIMIT * 1ns);  // Wait timeout period
      
      current_time = $time;
      
      // Check outstanding writes
      foreach (outstanding_writes[id]) begin
        if (outstanding_writes[id] != null) begin
          if ((current_time - outstanding_writes[id].start_time) > TIMEOUT_LIMIT) begin
            $error("[SCOREBOARD] Write transaction timeout: ID=%0d", id);
            errors_detected++;
            outstanding_writes[id] = null;
          end
        end
      end
      
      // Check outstanding reads
      foreach (outstanding_reads[id]) begin
        if (outstanding_reads[id] != null) begin
          if ((current_time - outstanding_reads[id].start_time) > TIMEOUT_LIMIT) begin
            $error("[SCOREBOARD] Read transaction timeout: ID=%0d", id);
            errors_detected++;
            outstanding_reads[id] = null;
          end
        end
      end
    end
  endtask
  
  // Report final statistics
  function void report();
    $display("\n==================== SCOREBOARD REPORT ====================");
    $display("Write Transactions: %0d", writes_processed);
    $display("Read Transactions:  %0d", reads_processed);
    $display("Total Transactions: %0d", writes_processed + reads_processed);
    $display("Data Mismatches:    %0d", mismatches);
    $display("Total Errors:       %0d", errors_detected);
    
    if (errors_detected == 0) begin
      $display("\n*** VERIFICATION PASSED - No errors detected ***");
    end else begin
      $display("\n*** VERIFICATION FAILED - %0d errors detected ***", errors_detected);
    end
    $display("===========================================================\n");
  endfunction
  
  // Memory dump for debugging
  function void dump_memory(bit [ADDR_WIDTH-1:0] start_addr, int num_bytes);
    bit [ADDR_WIDTH-1:0] addr;
    
    $display("\n==================== MEMORY DUMP ====================");
    $display("Address Range: 0x%h to 0x%h", start_addr, start_addr + num_bytes - 1);
    $display("-----------------------------------------------------");
    
    for (int i = 0; i < num_bytes; i++) begin
      addr = start_addr + i;
      if (mem.exists(addr)) begin
        $display("  [0x%h] = 0x%h", addr, mem[addr]);
      end
    end
    $display("=====================================================\n");
  endfunction
  
  // Clear memory model
  function void clear_memory();
    mem.delete();
    $display("[SCOREBOARD] Memory model cleared");
  endfunction
  
endclass : axi4_scoreboard
`endif // AXI4_SCOREBOARD_SV
