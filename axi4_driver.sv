// AXI4 Driver - Drives transactions onto AXI4 bus signals
`ifndef AXI4_DRIVER_SV
`define AXI4_DRIVER_SV

`include "axi4_transaction.sv"

class axi4_driver;
  import axi4_pkg::*;

  // Mailbox to receive transactions from generator
  mailbox #(axi4_transaction) drv_mb;

  // Virtual interface handle (set by environment)
  // In a real UVM env this would be a virtual interface;
  // here we use mailboxes to scoreboard directly.

  int transactions_driven;

  function new(mailbox #(axi4_transaction) mb);
    drv_mb = mb;
    transactions_driven = 0;
  endfunction

  // Main driver loop
  task run();
    axi4_transaction txn;
    forever begin
      drv_mb.get(txn);
      drive_transaction(txn);
      transactions_driven++;
    end
  endtask

  // Drive a single transaction (models bus timing)
  task drive_transaction(axi4_transaction txn);
    txn.start_time = $time;
    txn.status     = ACTIVE;

    if (txn.is_write)
      drive_write(txn);
    else
      drive_read(txn);

    txn.end_time = $time;
    txn.status   = COMPLETED;
  endtask

  // Simulate write transaction timing
  task drive_write(axi4_transaction txn);
    // Address phase delay
    repeat(txn.addr_delay) #1ns;

    $display("[DRIVER %0t] WRITE: ID=%0d Addr=0x%h Len=%0d Size=%0dB Burst=%s",
             $time, txn.id, txn.addr, txn.len+1, 2**txn.size, txn.burst.name());

    // Data phase: one beat per data_delay cycle
    for (int i = 0; i <= txn.len; i++) begin
      repeat(txn.data_delay[i]) #1ns;
      $display("[DRIVER %0t]   Beat[%0d] Data=0x%h Strb=0x%h Last=%0b",
               $time, i, txn.data[i], txn.strb[i], txn.last[i]);
    end
  endtask

  // Simulate read transaction timing
  task drive_read(axi4_transaction txn);
    repeat(txn.addr_delay) #1ns;

    $display("[DRIVER %0t] READ:  ID=%0d Addr=0x%h Len=%0d Size=%0dB Burst=%s",
             $time, txn.id, txn.addr, txn.len+1, 2**txn.size, txn.burst.name());
  endtask

  function void report();
    $display("[DRIVER] Transactions driven: %0d", transactions_driven);
  endfunction

endclass : axi4_driver
`endif // AXI4_DRIVER_SV
