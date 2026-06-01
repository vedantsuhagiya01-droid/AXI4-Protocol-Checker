// AXI4 Verification Environment - Wires all components together
`ifndef AXI4_ENV_SV
`define AXI4_ENV_SV

`include "axi4_driver.sv"
`include "axi4_monitor.sv"
`include "axi4_scoreboard.sv"
`include "axi4_coverage.sv"

class axi4_env;
  import axi4_pkg::*;

  // Components
  axi4_driver    driver;
  axi4_monitor   monitor;
  axi4_scoreboard scoreboard;
  axi4_coverage  coverage;

  // Inter-component mailboxes
  mailbox #(axi4_transaction) drv_mb;       // generator -> driver
  mailbox #(axi4_transaction) wr_mon_mb;    // monitor   -> scoreboard (writes)
  mailbox #(axi4_transaction) rd_mon_mb;    // monitor   -> scoreboard (reads)

  // Direct-path mailboxes used by axi4_test (bypasses driver/monitor for unit tests)
  mailbox #(axi4_transaction) write_mb;
  mailbox #(axi4_transaction) read_mb;

  function new();
    drv_mb    = new();
    wr_mon_mb = new();
    rd_mon_mb = new();
    write_mb  = wr_mon_mb;   // alias so test can put directly
    read_mb   = rd_mon_mb;

    driver     = new(drv_mb);
    monitor    = new(wr_mon_mb, rd_mon_mb);
    scoreboard = new(wr_mon_mb, rd_mon_mb);
    coverage   = new();
  endfunction

  // Build: connect components (called before run)
  function void build();
    $display("[ENV] Building verification environment");
  endfunction

  // Run: start all parallel threads
  task run();
    $display("[ENV] Starting environment");
    fork
      scoreboard.run();
    join_none
  endtask

  // Sample coverage for a transaction
  task sample_coverage(axi4_transaction txn);
    coverage.sample(txn);
  endtask

  // Wrap-up: print all reports
  function void report();
    $display("\n[ENV] ===== FINAL VERIFICATION REPORT =====");
    monitor.report();
    scoreboard.report();
    coverage.report();
    driver.report();
  endfunction

endclass : axi4_env
`endif // AXI4_ENV_SV
