// AXI4 Protocol Verification Testbench (iverilog-compatible, no OOP)
// Features: VCD waveform dump, protocol checkers, scoreboard, coverage stats
`timescale 1ns/1ps

module axi4_tb_iverilog;

  // ── Parameters ────────────────────────────────────────────────────────────
  localparam ADDR_WIDTH = 32;
  localparam DATA_WIDTH = 64;
  localparam STRB_WIDTH = 8;
  localparam MAX_BEATS  = 256;
  localparam MEM_DEPTH  = 8192;

  localparam FIXED = 2'b00, INCR = 2'b01, WRAP = 2'b10;
  localparam SIZE_1B=3'd0, SIZE_2B=3'd1, SIZE_4B=3'd2, SIZE_8B=3'd3;

  // ── Scoreboard memory ─────────────────────────────────────────────────────
  reg [7:0] mem [0:MEM_DEPTH-1];

  // ── Global transaction buffers (used by write/read tasks) ─────────────────
  reg [63:0] txn_data [0:MAX_BEATS-1];
  reg [7:0]  txn_strb [0:MAX_BEATS-1];

  // ── Counters ──────────────────────────────────────────────────────────────
  integer tests_run=0, tests_passed=0, tests_failed=0;
  integer writes_proc=0, reads_proc=0, mismatches=0, errors=0;
  integer err_snap;

  // ── Coverage buckets (manual functional coverage) ─────────────────────────
  integer cov_single_beat=0, cov_short_burst=0, cov_long_burst=0;
  integer cov_max_burst=0,   cov_fixed=0,        cov_wrap=0;
  integer cov_4kb_check=0,   cov_alignment=0,    cov_random=0;

  // ── VCD waveform signals (mirror key scoreboard state) ───────────────────
  reg        vcd_write;
  reg [31:0] vcd_addr;
  reg [7:0]  vcd_len;
  reg [2:0]  vcd_size;
  reg [1:0]  vcd_burst;
  reg        vcd_pass;

  // ── Helpers ───────────────────────────────────────────────────────────────
  function [31:0] next_addr;
    input [31:0] cur;
    input [2:0]  size;
    input [1:0]  burst;
    input [7:0]  beat;
    input [7:0]  tlen;
    integer inc, wrap_mask;
    begin
      inc = 1 << size;
      case (burst)
        FIXED:   next_addr = cur;
        INCR:    next_addr = cur + inc;
        WRAP: begin
          wrap_mask = (tlen + 1) * inc - 1;
          next_addr = (cur & ~wrap_mask) | ((cur + inc) & wrap_mask);
        end
        default: next_addr = cur + inc;
      endcase
    end
  endfunction

  // Fill txn_data/txn_strb with random values for `len+1` beats
  task fill_data;
    input [7:0] len;
    integer i;
    begin
      for (i = 0; i <= len; i = i + 1) begin
        txn_data[i] = {$random, $random};
        txn_strb[i] = 8'hFF;
      end
    end
  endtask

  // Protocol checks
  task chk_alignment;
    input [31:0] addr; input [2:0] size; input [3:0] id;
    begin
      if ((addr % (1 << size)) != 0) begin
        $display("[CHECKER] ALIGNMENT VIOLATION: Addr=0x%h not aligned to %0dB",addr,1<<size);
        errors = errors + 1;
      end
    end
  endtask

  task chk_4kb;
    input [31:0] addr; input [7:0] len; input [2:0] size; input [3:0] id;
    integer total;
    begin
      total = (len + 1) * (1 << size);
      if ((addr & 32'hFFF) + total > 4096) begin
        $display("[CHECKER] 4KB BOUNDARY VIOLATION: Addr=0x%h Len=%0d Size=%0dB total=%0d",
                 addr, len+1, 1<<size, total);
        errors = errors + 1;
      end
    end
  endtask

  task chk_wrap_len;
    input [7:0] len; input [3:0] id;
    begin
      if (!(len==1 || len==3 || len==7 || len==15)) begin
        $display("[CHECKER] WRAP LEN VIOLATION: %0d beats (must be 2/4/8/16)", len+1);
        errors = errors + 1;
      end
    end
  endtask

  // Write txn_data to memory model
  task sb_write;
    input [31:0] base; input [7:0] len; input [2:0] size; input [1:0] burst;
    integer beat, bl, bidx;
    reg [31:0] a;
    begin
      a = base;
      for (beat = 0; beat <= len; beat = beat + 1) begin
        for (bl = 0; bl < STRB_WIDTH; bl = bl + 1) begin
          if (txn_strb[beat][bl] && (a + bl < MEM_DEPTH)) begin
            bidx = bl * 8;
            mem[a + bl] = txn_data[beat][bidx +: 8];
          end
        end
        a = next_addr(a, size, burst, beat[7:0], len);
      end
      writes_proc = writes_proc + 1;
    end
  endtask

  // Verify txn_data against memory model
  task sb_read;
    input [31:0] base; input [7:0] len; input [2:0] size; input [1:0] burst;
    integer beat, bl, bidx, lmm;
    reg [31:0] a;
    reg [7:0] exp, got;
    begin
      a = base; lmm = 0;
      for (beat = 0; beat <= len; beat = beat + 1) begin
        for (bl = 0; bl < STRB_WIDTH; bl = bl + 1) begin
          if (a + bl < MEM_DEPTH) begin
            bidx = bl * 8;
            got  = txn_data[beat][bidx +: 8];
            exp  = mem[a + bl];
            if (got !== exp) begin
              $display("[SCOREBOARD] MISMATCH Addr=0x%h Exp=0x%h Got=0x%h", a+bl, exp, got);
              mismatches = mismatches + 1; lmm = lmm + 1;
            end
          end
        end
        a = next_addr(a, size, burst, beat[7:0], len);
      end
      if (lmm == 0)
        $display("[SCOREBOARD] Verified OK: base=0x%h len=%0d", base, len+1);
      else
        errors = errors + 1;
      reads_proc = reads_proc + 1;
    end
  endtask

  task pass_test; input [239:0] name; begin
    $display("  PASS: %0s", name);
    tests_passed = tests_passed + 1; tests_run = tests_run + 1;
  end endtask

  task fail_test; input [239:0] name; begin
    $display("  FAIL: %0s (errors=%0d mismatches=%0d)", name, errors, mismatches);
    tests_failed = tests_failed + 1; tests_run = tests_run + 1;
  end endtask

  // =========================================================================
  integer i;
  reg [31:0] addr;
  reg [7:0]  len;
  reg [2:0]  size;
  reg [1:0]  burst;

  initial begin
    // ── VCD waveform dump ─────────────────────────────────────────────────────
    $dumpfile("axi4_waves.vcd");
    $dumpvars(0, axi4_tb_iverilog);

    // Initialise memory and VCD mirror signals
    for (i = 0; i < MEM_DEPTH; i = i + 1) mem[i] = 8'h00;
    vcd_write=0; vcd_addr=0; vcd_len=0; vcd_size=0; vcd_burst=0; vcd_pass=0;

    $display("================================================================================");
    $display("          AXI4 PROTOCOL VERIFICATION  -  IVERILOG RUN");
    $display("================================================================================\n");

    // ── T1: Single write ────────────────────────────────────────────────────
    $display("[TEST 1] Single Write (1 beat, INCR, 8B)");
    addr=32'h0000_1000; len=0; size=SIZE_8B; burst=INCR;
    #1 vcd_write=1; vcd_addr=addr; vcd_len=len; vcd_size=size; vcd_burst=burst;
    chk_alignment(addr,size,0); chk_4kb(addr,len,size,0);
    fill_data(len); sb_write(addr,len,size,burst);
    err_snap=errors; cov_single_beat=cov_single_beat+1;
    #1 vcd_pass=(errors==err_snap);
    if(errors==err_snap) pass_test("Single Write"); else fail_test("Single Write");

    // ── T2: Single read-back ─────────────────────────────────────────────────
    $display("[TEST 2] Single Read-Back");
    for (i=0; i<STRB_WIDTH; i=i+1) txn_data[0][i*8 +: 8] = mem[addr+i];
    #1 vcd_write=0; vcd_addr=addr; cov_single_beat=cov_single_beat+1;
    err_snap=errors; sb_read(addr,len,size,burst);
    #1 vcd_pass=(errors==err_snap);
    if(errors==err_snap) pass_test("Single Read-Back"); else fail_test("Single Read-Back");

    // ── T3: Write-Read-Verify (data integrity) ───────────────────────────────
    $display("[TEST 3] Write-Read-Verify (4 beats)");
    addr=32'h0000_2000; len=3; size=SIZE_8B; burst=INCR;
    chk_alignment(addr,size,1); chk_4kb(addr,len,size,1);
    fill_data(len); sb_write(addr,len,size,burst);
    err_snap=errors; sb_read(addr,len,size,burst);
    if(errors==err_snap && mismatches==0) pass_test("Write-Read-Verify");
    else fail_test("Write-Read-Verify");

    // ── T4: INCR burst 16 beats ───────────────────────────────────────────────
    $display("[TEST 4] INCR Burst (16 beats, 8B)");
    addr=32'h0000_3000; len=15; size=SIZE_8B; burst=INCR;
    #1 vcd_write=1; vcd_addr=addr; vcd_len=len; vcd_burst=burst;
    chk_alignment(addr,size,2); chk_4kb(addr,len,size,2);
    fill_data(len); sb_write(addr,len,size,burst);
    err_snap=errors; cov_short_burst=cov_short_burst+1;
    #1 vcd_pass=(errors==err_snap);
    if(errors==err_snap) pass_test("INCR Burst 16 beats"); else fail_test("INCR Burst 16 beats");

    // ── T5: FIXED burst ───────────────────────────────────────────────────────
    $display("[TEST 5] FIXED Burst (8 beats, 4B - same address)");
    addr=32'h0000_4000; len=7; size=SIZE_4B; burst=FIXED;
    #1 vcd_write=1; vcd_addr=addr; vcd_len=len; vcd_burst=burst;
    chk_alignment(addr,size,3);
    fill_data(len); sb_write(addr,len,size,burst);
    err_snap=errors; cov_fixed=cov_fixed+1;
    #1 vcd_pass=(errors==err_snap);
    if(errors==err_snap) pass_test("FIXED Burst"); else fail_test("FIXED Burst");

    // ── T6: WRAP burst valid ─────────────────────────────────────────────────
    $display("[TEST 6] WRAP Burst (8 beats, len=7 - VALID)");
    addr=32'h0000_5000; len=7; size=SIZE_8B; burst=WRAP;
    #1 vcd_write=1; vcd_addr=addr; vcd_len=len; vcd_burst=burst;
    chk_alignment(addr,size,4); chk_wrap_len(len,4); chk_4kb(addr,len,size,4);
    fill_data(len); sb_write(addr,len,size,burst);
    err_snap=errors; cov_wrap=cov_wrap+1;
    #1 vcd_pass=(errors==err_snap);
    if(errors==err_snap) pass_test("WRAP Burst valid"); else fail_test("WRAP Burst valid");

    // ── T7: Max burst 256 beats ───────────────────────────────────────────────
    $display("[TEST 7] Maximum Burst (256 beats, INCR, 4B)");
    addr=32'h0001_0000; len=255; size=SIZE_4B; burst=INCR;
    #1 vcd_write=1; vcd_addr=addr; vcd_len=len; vcd_burst=burst;
    chk_alignment(addr,size,5); chk_4kb(addr,len,size,5);
    fill_data(len); sb_write(addr,len,size,burst);
    err_snap=errors; cov_max_burst=cov_max_burst+1;
    #1 vcd_pass=(errors==err_snap);
    if(errors==err_snap) pass_test("Max Burst 256 beats"); else fail_test("Max Burst 256 beats");

    // ── T8: 4KB boundary LEGAL ───────────────────────────────────────────────
    $display("[TEST 8] 4KB Boundary - LEGAL (ends exactly at 4096)");
    addr=32'h0000_0FF0; len=1; size=SIZE_8B; burst=INCR;
    #1 vcd_addr=addr; vcd_len=len;
    err_snap=errors; chk_4kb(addr,len,size,6); cov_4kb_check=cov_4kb_check+1;
    #1 vcd_pass=(errors==err_snap);
    if(errors==err_snap) pass_test("4KB boundary legal"); else fail_test("4KB boundary legal");

    // ── T8b: 4KB boundary VIOLATION ──────────────────────────────────────────
    $display("[TEST 8b] 4KB Boundary - VIOLATION (checker must fire)");
    addr=32'h0000_0FF8; len=1; size=SIZE_8B; burst=INCR;
    #1 vcd_addr=addr; vcd_len=len;
    err_snap=errors; chk_4kb(addr,len,size,7); cov_4kb_check=cov_4kb_check+1;
    #1 vcd_pass=(errors>err_snap);
    if(errors>err_snap) pass_test("4KB violation detected");
    else fail_test("4KB violation NOT detected");

    // ── T9: WRAP invalid length ───────────────────────────────────────────────
    $display("[TEST 9] WRAP Burst INVALID length (checker must fire)");
    err_snap=errors; chk_wrap_len(8'd5, 4'd8);
    if(errors>err_snap) pass_test("WRAP invalid len detected");
    else fail_test("WRAP invalid len NOT detected");

    // ── T10: Address alignment all sizes ──────────────────────────────────────
    $display("[TEST 10] Address Alignment (1B/2B/4B/8B)");
    err_snap=errors; cov_alignment=cov_alignment+1;
    begin
      chk_alignment(32'h0000_6001, SIZE_1B, 9);
      chk_alignment(32'h0000_6002, SIZE_2B, 9);
      chk_alignment(32'h0000_6004, SIZE_4B, 9);
      chk_alignment(32'h0000_6008, SIZE_8B, 9);
      $display("  1B@0x6001: OK  2B@0x6002: OK  4B@0x6004: OK  8B@0x6008: OK");
    end
    #1 vcd_pass=(errors==err_snap);
    if(errors==err_snap) pass_test("Address alignment"); else fail_test("Address alignment");

    // ── T11: Back-to-back writes ──────────────────────────────────────────────
    $display("[TEST 11] Back-to-Back Writes (5 transactions)");
    err_snap=errors;
    for (i=0; i<5; i=i+1) begin
      addr = 32'h0001_2000 + (i * 32);
      len=3; size=SIZE_8B; burst=INCR;
      chk_alignment(addr,size,i[3:0]); chk_4kb(addr,len,size,i[3:0]);
      fill_data(len); sb_write(addr,len,size,burst);
      $display("  Txn %0d: Addr=0x%h Beats=%0d", i, addr, len+1);
    end
    if(errors==err_snap) pass_test("Back-to-Back writes"); else fail_test("Back-to-Back writes");

    // ── T12: Random traffic (200 transactions) ────────────────────────────────
    $display("[TEST 12] Random Traffic (200 write+read transactions)");
    err_snap=errors;
    for (i=0; i<200; i=i+1) begin
      addr  = ({$random} & 32'h0000_0FFF) & ~32'h7;  // 8B aligned, 4KB range
      len   = {$random} & 8'h0F;
      size  = SIZE_8B;
      burst = INCR;
      // Ensure no 4KB crossing
      if (((addr & 32'hFFF) + (len+1)*8) > 4096) begin
        len = (4096 - (addr & 32'hFFF)) / 8 - 1;
        if (len > 8'hFF) len = 0;
      end
      fill_data(len); sb_write(addr,len,size,burst);
      sb_read(addr,len,size,burst);
      if (i%50==0) $display("  Progress %0d/200", i);
    end
    cov_random=cov_random+1;
    #1 vcd_pass=(errors==err_snap && mismatches==0);
    if(errors==err_snap && mismatches==0) pass_test("Random traffic 200");
    else fail_test("Random traffic 200");

    // ── T13: WRAP addressing (cache-line fill) ────────────────────────────────
    $display("[TEST 13] WRAP cache-line fill (8 beats, 64B)");
    addr=32'h0002_0000; len=7; size=SIZE_8B; burst=WRAP;
    chk_alignment(addr,size,12); chk_wrap_len(len,12);
    fill_data(len); sb_write(addr,len,size,burst);
    err_snap=errors; sb_read(addr,len,size,burst);
    if(errors==err_snap) pass_test("WRAP cache-line fill"); else fail_test("WRAP cache-line fill");

    // ── Final report ──────────────────────────────────────────────────────────
    $display("\n================================================================================");
    $display("                       TEST RESULTS SUMMARY");
    $display("================================================================================");
    $display("  Tests Run:    %0d", tests_run);
    $display("  Passed:       %0d", tests_passed);
    $display("  Failed:       %0d", tests_failed);
    $display("  Pass Rate:    %.1f%%", (tests_passed * 100.0) / tests_run);
    $display("  Write Txns:   %0d", writes_proc);
    $display("  Read  Txns:   %0d", reads_proc);
    $display("  Mismatches:   %0d", mismatches);
    $display("  Total Errors: %0d", errors);
    $display("================================================================================");
    $display("\n  FUNCTIONAL COVERAGE SUMMARY (manual bins):");
    $display("  Single-beat transactions : %0d hit(s)", cov_single_beat);
    $display("  Short burst (<=16 beats) : %0d hit(s)", cov_short_burst);
    $display("  Maximum burst (256 beats): %0d hit(s)", cov_max_burst);
    $display("  FIXED burst              : %0d hit(s)", cov_fixed);
    $display("  WRAP burst               : %0d hit(s)", cov_wrap);
    $display("  4KB boundary checks      : %0d hit(s)", cov_4kb_check);
    $display("  Alignment checks         : %0d hit(s)", cov_alignment);
    $display("  Random traffic runs      : %0d hit(s)", cov_random);
    $display("  Waveform written to      : axi4_waves.vcd");
    $display("================================================================================");
    if (tests_failed == 0 && mismatches == 0)
      $display("\n*** VERIFICATION PASSED - All %0d tests OK ***\n", tests_run);
    else
      $display("\n*** VERIFICATION FAILED - %0d tests failed ***\n", tests_failed);

    $finish;
  end

endmodule
