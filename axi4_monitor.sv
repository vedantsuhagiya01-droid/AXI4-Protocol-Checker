// AXI4 Monitor - Observes bus activity and forwards to scoreboard/coverage
`ifndef AXI4_MONITOR_SV
`define AXI4_MONITOR_SV

`include "axi4_transaction.sv"

class axi4_monitor;
  import axi4_pkg::*;

  // Output mailboxes (to scoreboard)
  mailbox #(axi4_transaction) write_mon_mb;
  mailbox #(axi4_transaction) read_mon_mb;

  int writes_observed;
  int reads_observed;
  int protocol_errors;

  function new(mailbox #(axi4_transaction) wr_mb,
               mailbox #(axi4_transaction) rd_mb);
    write_mon_mb   = wr_mb;
    read_mon_mb    = rd_mb;
    writes_observed  = 0;
    reads_observed   = 0;
    protocol_errors  = 0;
  endfunction

  // Forward a completed transaction to the appropriate mailbox
  task observe(axi4_transaction txn);
    if (!check_protocol(txn)) begin
      protocol_errors++;
      return;
    end

    if (txn.is_write) begin
      write_mon_mb.put(txn);
      writes_observed++;
      $display("[MONITOR %0t] Observed WRITE: ID=%0d Addr=0x%h Beats=%0d",
               $time, txn.id, txn.addr, txn.len+1);
    end else begin
      read_mon_mb.put(txn);
      reads_observed++;
      $display("[MONITOR %0t] Observed READ:  ID=%0d Addr=0x%h Beats=%0d",
               $time, txn.id, txn.addr, txn.len+1);
    end
  endtask

  // Lightweight protocol checks (gate before scoreboard)
  function bit check_protocol(axi4_transaction txn);
    // Address alignment
    if (txn.addr % (2**txn.size) != 0) begin
      $error("[MONITOR %0t] ALIGNMENT VIOLATION: Addr=0x%h Size=%0dB",
             $time, txn.addr, 2**txn.size);
      return 0;
    end

    // 4KB boundary
    if ((txn.addr & 32'hFFF) + ((txn.len + 1) * (2**txn.size)) > 4096) begin
      $error("[MONITOR %0t] 4KB BOUNDARY VIOLATION: Addr=0x%h",
             $time, txn.addr);
      return 0;
    end

    // WRAP burst length
    if (txn.burst == WRAP && !(txn.len inside {1, 3, 7, 15})) begin
      $error("[MONITOR %0t] WRAP LEN VIOLATION: len=%0d (must be 1/3/7/15)",
             $time, txn.len);
      return 0;
    end

    // WLAST on last beat
    if (txn.is_write && txn.last.size() > 0 && !txn.last[txn.len]) begin
      $error("[MONITOR %0t] WLAST missing on last beat: ID=%0d",
             $time, txn.id);
      return 0;
    end

    return 1;
  endfunction

  function void report();
    $display("\n==================== MONITOR REPORT ====================");
    $display("Writes Observed:   %0d", writes_observed);
    $display("Reads Observed:    %0d", reads_observed);
    $display("Protocol Errors:   %0d", protocol_errors);
    $display("=========================================================\n");
  endfunction

endclass : axi4_monitor
`endif // AXI4_MONITOR_SV
