// AXI4 Test Examples
`ifndef AXI4_TEST_SV
`define AXI4_TEST_SV

`include "axi4_pkg.sv"
`include "axi4_transaction.sv"
`include "axi4_coverage.sv"
`include "axi4_scoreboard.sv"

module axi4_test;
  import axi4_pkg::*;
  
  // Testbench components
  axi4_transaction txn;
  axi4_coverage cov;
  axi4_scoreboard sb;
  
  // Mailboxes for communication
  mailbox #(axi4_transaction) write_mb;
  mailbox #(axi4_transaction) read_mb;
  
  // Statistics
  int tests_run;
  int tests_passed;
  int tests_failed;
  
  // Initial setup
  initial begin
    // Create mailboxes
    write_mb = new();
    read_mb = new();
    
    // Create verification components
    cov = new();
    sb = new(write_mb, read_mb);
    
    // Start scoreboard
    sb.run();
    
    // Run tests
    run_all_tests();
    
    // Report results
    report_results();
    
    $finish;
  end
  
  // ========================================================================
  // TEST SUITE
  // ========================================================================
  
  task run_all_tests();
    $display("\n");
    $display("================================================================================");
    $display("                    AXI4 VERIFICATION TEST SUITE");
    $display("================================================================================\n");
    
    // Basic functionality tests
    test_single_write();
    test_single_read();
    test_write_read_verify();
    
    // Burst tests
    test_incr_burst();
    test_fixed_burst();
    test_wrap_burst();
    test_maximum_burst();
    
    // Corner case tests
    test_4kb_boundary();
    test_address_alignment();
    test_back_to_back_transactions();
    test_outstanding_transactions();
    
    // Stress tests
    test_random_traffic(1000);
    test_corner_case_stress(500);
    
  endtask
  
  // ========================================================================
  // BASIC FUNCTIONALITY TESTS
  // ========================================================================
  
  // TEST 1: Single Write Transaction
  task test_single_write();
    $display("\n[TEST 1] Single Write Transaction");
    $display("--------------------------------------------------");
    
    txn = new();
    assert(txn.randomize() with {
      is_write == 1;
      len == 0;          // Single beat
      size == SIZE_8B;
      burst == INCR;
      addr[2:0] == 0;    // Aligned
    });
    
    $display("Generated: %s", txn.convert2string());
    write_mb.put(txn);
    cov.sample(txn);
    
    #100ns;
    
    if (sb.errors_detected == 0) begin
      $display("PASS: Single write completed without errors");
      tests_passed++;
    end else begin
      $display("FAIL: Errors detected in single write");
      tests_failed++;
    end
    tests_run++;
  endtask
  
  // TEST 2: Single Read Transaction
  task test_single_read();
    $display("\n[TEST 2] Single Read Transaction");
    $display("--------------------------------------------------");
    
    txn = new();
    assert(txn.randomize() with {
      is_write == 0;
      len == 0;
      size == SIZE_8B;
      addr[2:0] == 0;
    });
    
    $display("Generated: %s", txn.convert2string());
    read_mb.put(txn);
    cov.sample(txn);
    
    #100ns;
    
    if (sb.errors_detected == 0) begin
      $display("PASS: Single read completed without errors");
      tests_passed++;
    end else begin
      $display("FAIL: Errors detected in single read");
      tests_failed++;
    end
    tests_run++;
  endtask
  
  // TEST 3: Write-Read-Verify (Data Integrity)
  task test_write_read_verify();
    $display("\n[TEST 3] Write-Read-Verify (Data Integrity)");
    $display("--------------------------------------------------");
    
    axi4_transaction write_txn, read_txn;
    bit [ADDR_WIDTH-1:0] test_addr = 32'h1000;
    
    // Write transaction
    write_txn = new();
    assert(write_txn.randomize() with {
      is_write == 1;
      addr == test_addr;
      len == 3;          // 4 beats
      size == SIZE_8B;
      burst == INCR;
    });
    
    $display("Write: %s", write_txn.convert2string());
    write_mb.put(write_txn);
    cov.sample(write_txn);
    
    #200ns;
    
    // Read same address
    read_txn = new();
    assert(read_txn.randomize() with {
      is_write == 0;
      addr == test_addr;
      len == 3;
      size == SIZE_8B;
      burst == INCR;
    });
    
    // Copy expected data from write
    foreach(read_txn.data[i])
      read_txn.data[i] = write_txn.data[i];
    
    $display("Read:  %s", read_txn.convert2string());
    read_mb.put(read_txn);
    cov.sample(read_txn);
    
    #200ns;
    
    if (sb.mismatches == 0) begin
      $display("PASS: Data integrity verified");
      tests_passed++;
    end else begin
      $display("FAIL: Data mismatch detected");
      tests_failed++;
    end
    tests_run++;
  endtask
  
  // ========================================================================
  // BURST TYPE TESTS
  // ========================================================================
  
  // TEST 4: Incrementing Burst
  task test_incr_burst();
    $display("\n[TEST 4] Incrementing Burst");
    $display("--------------------------------------------------");
    
    txn = new();
    assert(txn.randomize() with {
      is_write == 1;
      len == 15;         // 16 beats
      size == SIZE_8B;
      burst == INCR;
      addr[2:0] == 0;
    });
    
    $display("Generated: %s", txn.convert2string());
    write_mb.put(txn);
    cov.sample(txn);
    
    #500ns;
    
    if (sb.errors_detected == 0) begin
      $display("PASS: INCR burst completed successfully");
      tests_passed++;
    end else begin
      $display("FAIL: INCR burst had errors");
      tests_failed++;
    end
    tests_run++;
  endtask
  
  // TEST 5: Fixed Burst
  task test_fixed_burst();
    $display("\n[TEST 5] Fixed Burst (Address Stays Same)");
    $display("--------------------------------------------------");
    
    txn = new();
    assert(txn.randomize() with {
      is_write == 1;
      len inside {[4:7]};
      size == SIZE_4B;
      burst == FIXED;
      addr[1:0] == 0;
    });
    
    $display("Generated: %s", txn.convert2string());
    write_mb.put(txn);
    cov.sample(txn);
    
    #300ns;
    
    if (sb.errors_detected == 0) begin
      $display("PASS: FIXED burst completed successfully");
      tests_passed++;
    end else begin
      $display("FAIL: FIXED burst had errors");
      tests_failed++;
    end
    tests_run++;
  endtask
  
  // TEST 6: Wrapping Burst
  task test_wrap_burst();
    $display("\n[TEST 6] Wrapping Burst");
    $display("--------------------------------------------------");
    
    txn = new();
    assert(txn.randomize() with {
      is_write == 1;
      burst == WRAP;
      len == 7;          // 8 beats (valid for WRAP)
      size == SIZE_8B;
      addr % ((len + 1) * (2**size)) == 0;  // Start at wrap boundary
    });
    
    $display("Generated: %s", txn.convert2string());
    $display("Wrap boundary: Every %0d bytes", (txn.len + 1) * (2**txn.size));
    write_mb.put(txn);
    cov.sample(txn);
    
    #400ns;
    
    if (sb.errors_detected == 0) begin
      $display("PASS: WRAP burst completed successfully");
      tests_passed++;
    end else begin
      $display("FAIL: WRAP burst had errors");
      tests_failed++;
    end
    tests_run++;
  endtask
  
  // TEST 7: Maximum Burst Length
  task test_maximum_burst();
    $display("\n[TEST 7] Maximum Burst Length (256 beats)");
    $display("--------------------------------------------------");
    
    txn = new();
    assert(txn.randomize() with {
      is_write == 1;
      len == 255;        // 256 beats (maximum)
      size == SIZE_8B;
      burst == INCR;
      addr[2:0] == 0;
    });
    
    $display("Generated: %s", txn.convert2string());
    $display("Total transfer: %0d bytes", (txn.len + 1) * (2**txn.size));
    write_mb.put(txn);
    cov.sample(txn);
    
    #2000ns;
    
    if (sb.errors_detected == 0) begin
      $display("PASS: Maximum burst completed successfully");
      tests_passed++;
    end else begin
      $display("FAIL: Maximum burst had errors");
      tests_failed++;
    end
    tests_run++;
  endtask
  
  // ========================================================================
  // CORNER CASE TESTS
  // ========================================================================
  
  // TEST 8: 4KB Boundary Compliance
  task test_4kb_boundary();
    $display("\n[TEST 8] 4KB Boundary Compliance");
    $display("--------------------------------------------------");
    
    // Test address close to 4KB boundary
    txn = new();
    assert(txn.randomize() with {
      is_write == 1;
      addr == 32'h0FF0;  // 16 bytes before 4KB
      len == 1;          // 2 beats * 8 bytes = 16 bytes total
      size == SIZE_8B;
      burst == INCR;
    });
    
    $display("Generated: %s", txn.convert2string());
    $display("Address: 0x%h, Transfer ends at: 0x%h", 
             txn.addr, txn.addr + (txn.len + 1) * (2**txn.size));
    
    write_mb.put(txn);
    cov.sample(txn);
    
    #200ns;
    
    if (sb.errors_detected == 0) begin
      $display("PASS: 4KB boundary respected");
      tests_passed++;
    end else begin
      $display("FAIL: 4KB boundary violation");
      tests_failed++;
    end
    tests_run++;
  endtask
  
  // TEST 9: Address Alignment
  task test_address_alignment();
    $display("\n[TEST 9] Address Alignment Verification");
    $display("--------------------------------------------------");
    
    // Test various alignment scenarios
    for (int i = 0; i <= 3; i++) begin
      txn = new();
      assert(txn.randomize() with {
        is_write == 1;
        size == burst_size_e'(i);  // 1B, 2B, 4B, 8B
        addr % (2**size) == 0;     // Properly aligned
        len inside {[0:3]};
        burst == INCR;
      });
      
      $display("  Size=%0dB, Addr=0x%h (aligned to %0d bytes)", 
               2**txn.size, txn.addr, 2**txn.size);
      
      write_mb.put(txn);
      cov.sample(txn);
      #100ns;
    end
    
    if (sb.errors_detected == 0) begin
      $display("PASS: All alignments correct");
      tests_passed++;
    end else begin
      $display("FAIL: Alignment errors detected");
      tests_failed++;
    end
    tests_run++;
  endtask
  
  // TEST 10: Back-to-Back Transactions
  task test_back_to_back_transactions();
    $display("\n[TEST 10] Back-to-Back Transactions (Zero Delay)");
    $display("--------------------------------------------------");
    
    for (int i = 0; i < 5; i++) begin
      txn = new();
      assert(txn.randomize() with {
        is_write == 1;
        len inside {[0:3]};
        size == SIZE_8B;
        burst == INCR;
        addr[2:0] == 0;
      });
      
      txn.addr_delay = 0;  // Zero cycle delay
      
      $display("  Transaction %0d: Addr=0x%h, Len=%0d", i, txn.addr, txn.len+1);
      write_mb.put(txn);
      cov.sample(txn);
    end
    
    #500ns;
    
    if (sb.errors_detected == 0) begin
      $display("PASS: Back-to-back transactions successful");
      tests_passed++;
    end else begin
      $display("FAIL: Back-to-back transaction errors");
      tests_failed++;
    end
    tests_run++;
  endtask
  
  // TEST 11: Outstanding Transactions
  task test_outstanding_transactions();
    $display("\n[TEST 11] Outstanding Transactions (Concurrent IDs)");
    $display("--------------------------------------------------");
    
    // Issue multiple transactions with different IDs without waiting
    for (int i = 0; i < 8; i++) begin
      txn = new();
      assert(txn.randomize() with {
        is_write == 1;
        id == i[ID_WIDTH-1:0];
        len inside {[0:2]};
        size == SIZE_8B;
        burst == INCR;
        addr[2:0] == 0;
      });
      
      $display("  Issuing transaction with ID=%0d", txn.id);
      write_mb.put(txn);
      cov.sample(txn);
      #10ns;  // Small delay between issues
    end
    
    #1000ns;  // Wait for all to complete
    
    if (sb.errors_detected == 0) begin
      $display("PASS: Outstanding transactions handled correctly");
      tests_passed++;
    end else begin
      $display("FAIL: Outstanding transaction errors");
      tests_failed++;
    end
    tests_run++;
  endtask
  
  // ========================================================================
  // STRESS TESTS
  // ========================================================================
  
  // TEST 12: Random Traffic Generator
  task test_random_traffic(int num_transactions);
    int errors_before;
    int errors_found;
    $display("\n[TEST 12] Random Traffic Test (%0d transactions)", num_transactions);
    $display("--------------------------------------------------");

    errors_before = sb.errors_detected;
    
    for (int i = 0; i < num_transactions; i++) begin
      txn = new();
      assert(txn.randomize());  // Fully random, constrained by class
      
      if (i % 100 == 0)
        $display("  Progress: %0d/%0d transactions", i, num_transactions);
      
      if (txn.is_write)
        write_mb.put(txn);
      else
        read_mb.put(txn);
      
      cov.sample(txn);
      
      #50ns;  // Spacing between transactions
    end
    
    #1000ns;

    errors_found = sb.errors_detected - errors_before;

    if (errors_found == 0) begin
      $display("PASS: All %0d random transactions successful", num_transactions);
      tests_passed++;
    end else begin
      $display("FAIL: %0d errors in random traffic", errors_found);
      tests_failed++;
    end
    tests_run++;
  endtask

  // TEST 13: Corner Case Stress
  task test_corner_case_stress(int num_transactions);
    int errors_before;
    int errors_found;
    $display("\n[TEST 13] Corner Case Stress Test");
    $display("--------------------------------------------------");

    errors_before = sb.errors_detected;
    
    for (int i = 0; i < num_transactions; i++) begin
      txn = new();
      
      // Force corner cases
      assert(txn.randomize() with {
        // Bias toward corner cases
        (len dist {0 := 20, 255 := 20, [1:254] := 60});
        (burst == WRAP) -> (len inside {1, 3, 7, 15});
        (addr[11:0] dist {12'h000 := 10, 12'hFF0 := 10, [12'h001:12'hFEF] := 80});
      });
      
      if (txn.is_write)
        write_mb.put(txn);
      else
        read_mb.put(txn);
      
      cov.sample(txn);
      
      #50ns;
    end
    
    #1000ns;

    errors_found = sb.errors_detected - errors_before;

    if (errors_found == 0) begin
      $display("PASS: Corner case stress test successful");
      tests_passed++;
    end else begin
      $display("FAIL: %0d errors in corner case stress", errors_found);
      tests_failed++;
    end
    tests_run++;
  endtask
  
  // ========================================================================
  // REPORTING
  // ========================================================================
  
  task report_results();
    $display("\n");
    $display("================================================================================");
    $display("                        TEST RESULTS SUMMARY");
    $display("================================================================================");
    $display("Total Tests Run:    %0d", tests_run);
    $display("Tests Passed:       %0d", tests_passed);
    $display("Tests Failed:       %0d", tests_failed);
    $display("Pass Rate:          %.1f%%", real'(tests_passed)/real'(tests_run)*100.0);
    $display("================================================================================");
    
    // Coverage report
    cov.report();
    
    // Scoreboard report
    sb.report();
    
    // Final verdict
    if (tests_failed == 0 && sb.errors_detected == 0) begin
      $display("========================================================================");
      $display("         *** VERIFICATION PASSED - All tests completed OK ***");
      $display("========================================================================");
    end else begin
      $display("========================================================================");
      $display("         *** VERIFICATION FAILED ***");
      $display("  Tests Failed: %0d  |  Errors Found: %0d", tests_failed, sb.errors_detected);
      $display("========================================================================");
    end
  endtask
  
endmodule : axi4_test
`endif // AXI4_TEST_SV
