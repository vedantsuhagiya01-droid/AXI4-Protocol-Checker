// AXI4 Functional Coverage Collector
`ifndef AXI4_COVERAGE_SV
`define AXI4_COVERAGE_SV

`include "axi4_transaction.sv"

class axi4_coverage;
  import axi4_pkg::*;
  
  // Transaction handle for sampling
  axi4_transaction txn;
  
  // Coverage metrics
  real total_coverage;
  int  transactions_sampled;
  
  // Main covergroup for AXI4 transactions
  covergroup cg_axi4_transaction;
    option.per_instance = 1;
    option.name = "axi4_txn_cov";
    
    // Transaction type coverage
    cp_type: coverpoint txn.is_write {
      bins write = {1};
      bins read  = {0};
    }
    
    // Address alignment coverage
    cp_addr_alignment: coverpoint (txn.addr % 8) {
      bins aligned_8B  = {0};
      bins aligned_4B  = {4};
      bins aligned_2B  = {2, 6};
      bins aligned_1B  = {1, 3, 5, 7};
    }
    
    // Burst length coverage
    cp_burst_length: coverpoint txn.len {
      bins single       = {0};
      bins short_burst  = {[1:3]};
      bins medium_burst = {[4:15]};
      bins long_burst   = {[16:63]};
      bins very_long    = {[64:255]};
    }
    
    // Burst size coverage
    cp_burst_size: coverpoint txn.size {
      bins byte_1   = {SIZE_1B};
      bins byte_2   = {SIZE_2B};
      bins byte_4   = {SIZE_4B};
      bins byte_8   = {SIZE_8B};
      bins byte_16  = {SIZE_16B};
      bins byte_32  = {SIZE_32B};
      bins byte_64  = {SIZE_64B};
      bins byte_128 = {SIZE_128B};
    }
    
    // Burst type coverage
    cp_burst_type: coverpoint txn.burst {
      bins fixed = {FIXED};
      bins incr  = {INCR};
      bins wrap  = {WRAP};
    }
    
    // QoS coverage
    cp_qos: coverpoint txn.qos {
      bins low     = {[0:3]};
      bins medium  = {[4:7]};
      bins high    = {[8:11]};
      bins highest = {[12:15]};
    }
    
    // Cache attributes
    cp_cache: coverpoint txn.cache {
      bins non_cacheable     = {4'b0000};
      bins bufferable        = {4'b0001};
      bins cacheable         = {4'b0010, 4'b0011};
      bins write_through     = {4'b0110, 4'b0111};
      bins write_back        = {4'b1110, 4'b1111};
    }
    
    // Cross coverage for critical combinations
    
    // WRAP burst must have specific lengths
    cross_wrap_length: cross cp_burst_type, cp_burst_length {
      bins valid_wrap_2   = binsof(cp_burst_type.wrap) && binsof(cp_burst_length) intersect {1};
      bins valid_wrap_4   = binsof(cp_burst_type.wrap) && binsof(cp_burst_length) intersect {3};
      bins valid_wrap_8   = binsof(cp_burst_type.wrap) && binsof(cp_burst_length) intersect {7};
      bins valid_wrap_16  = binsof(cp_burst_type.wrap) && binsof(cp_burst_length) intersect {15};
      
      // Illegal combinations should not occur
      illegal_bins invalid_wrap = binsof(cp_burst_type.wrap) && 
                                  binsof(cp_burst_length) intersect {[0:0], 2, [4:6], [8:14], [16:255]};
    }
    
    // Write vs Read with different burst types
    cross_type_burst: cross cp_type, cp_burst_type {
      bins write_fixed = binsof(cp_type.write) && binsof(cp_burst_type.fixed);
      bins write_incr  = binsof(cp_type.write) && binsof(cp_burst_type.incr);
      bins write_wrap  = binsof(cp_type.write) && binsof(cp_burst_type.wrap);
      bins read_fixed  = binsof(cp_type.read)  && binsof(cp_burst_type.fixed);
      bins read_incr   = binsof(cp_type.read)  && binsof(cp_burst_type.incr);
      bins read_wrap   = binsof(cp_type.read)  && binsof(cp_burst_type.wrap);
    }
    
    // Burst size vs length (important for bandwidth analysis)
    cross_size_length: cross cp_burst_size, cp_burst_length {
      bins max_bw_8B   = binsof(cp_burst_size.byte_8) && 
                         binsof(cp_burst_length.long_burst);
      bins max_bw_4B   = binsof(cp_burst_size.byte_4) && 
                         binsof(cp_burst_length.long_burst);
      bins single_1B   = binsof(cp_burst_size.byte_1) && 
                         binsof(cp_burst_length.single);
    }
    
    // QoS priority with transaction type
    cross_qos_type: cross cp_qos, cp_type;
    
  endgroup : cg_axi4_transaction
  
  // Corner case coverage for real-world scenarios
  covergroup cg_corner_cases;
    option.per_instance = 1;
    option.name = "axi4_corner_cov";
    
    // 4KB boundary proximity
    cp_4kb_proximity: coverpoint ((txn.addr & 12'hFFF) + ((txn.len + 1) * (2**txn.size))) {
      bins far_from_boundary   = {[0:3072]};
      bins near_boundary       = {[3073:4095]};
      bins exactly_at_boundary = {4096};
    }
    
    // Address patterns that stress address decoder
    cp_addr_patterns: coverpoint txn.addr[11:0] {
      bins all_zeros  = {12'h000};
      bins all_ones   = {12'hFFF};
      bins walking_1  = {12'h001, 12'h002, 12'h004, 12'h008, 
                        12'h010, 12'h020, 12'h040, 12'h080,
                        12'h100, 12'h200, 12'h400, 12'h800};
      bins walking_0  = {12'hFFE, 12'hFFD, 12'hFFB, 12'hFF7,
                        12'hFEF, 12'hFDF, 12'hFBF, 12'hF7F,
                        12'hEFF, 12'hDFF, 12'hBFF, 12'h7FF};
    }
    
    // Strobe patterns (for partial writes)
    cp_strobe_patterns: coverpoint txn.strb[0] {
      wildcard bins all_lanes   = {8'b11111111};
      wildcard bins first_half  = {8'b00001111};
      wildcard bins second_half = {8'b11110000};
      wildcard bins odd_lanes   = {8'b01010101};
      wildcard bins even_lanes  = {8'b10101010};
      wildcard bins single_byte = {8'b00000001, 8'b00000010, 8'b00000100, 8'b00001000,
                                   8'b00010000, 8'b00100000, 8'b01000000, 8'b10000000};
    }
    
  endgroup : cg_corner_cases
  
  // Performance-related coverage
  covergroup cg_performance;
    option.per_instance = 1;
    option.name = "axi4_perf_cov";
    
    // Back-to-back transactions (stress test)
    cp_addr_delay: coverpoint txn.addr_delay {
      bins no_delay      = {0};
      bins short_delay   = {[1:2]};
      bins medium_delay  = {[3:5]};
      bins long_delay    = {[6:10]};
    }
    
    // Total transfer size (bandwidth stress)
    cp_transfer_size: coverpoint ((txn.len + 1) * (2**txn.size)) {
      bins tiny   = {[1:8]};
      bins small  = {[9:64]};
      bins medium = {[65:256]};
      bins large  = {[257:1024]};
      bins huge   = {[1025:4096]};
    }
    
  endgroup : cg_performance
  
  // ID coverage for transaction ordering
  covergroup cg_transaction_ids;
    option.per_instance = 1;
    option.name = "axi4_id_cov";
    
    cp_id: coverpoint txn.id {
      bins ids[] = {[0:15]};  // All possible IDs
    }
    
    cp_id_reuse: coverpoint txn.id {
      bins consecutive_same = (0=>0), (1=>1), (2=>2);  // ID reuse
      bins consecutive_diff = (0=>1), (1=>2), (2=>3);  // Different IDs
    }
    
  endgroup : cg_transaction_ids
  
  // Constructor
  function new();
    cg_axi4_transaction = new();
    cg_corner_cases = new();
    cg_performance = new();
    cg_transaction_ids = new();
    transactions_sampled = 0;
  endfunction
  
  // Sample coverage
  task sample(axi4_transaction t);
    txn = t;
    cg_axi4_transaction.sample();
    cg_corner_cases.sample();
    cg_performance.sample();
    cg_transaction_ids.sample();
    transactions_sampled++;
    update_coverage();
  endtask
  
  // Update total coverage percentage
  function void update_coverage();
    total_coverage = (cg_axi4_transaction.get_coverage() + 
                     cg_corner_cases.get_coverage() + 
                     cg_performance.get_coverage() + 
                     cg_transaction_ids.get_coverage()) / 4.0;
  endfunction
  
  // Report coverage
  function void report();
    $display("\n==================== COVERAGE REPORT ====================");
    $display("Total Transactions Sampled: %0d", transactions_sampled);
    $display("Overall Coverage: %.2f%%", total_coverage);
    $display("\nDetailed Coverage:");
    $display("  Transaction Coverage: %.2f%%", cg_axi4_transaction.get_coverage());
    $display("  Corner Case Coverage: %.2f%%", cg_corner_cases.get_coverage());
    $display("  Performance Coverage: %.2f%%", cg_performance.get_coverage());
    $display("  ID Coverage: %.2f%%", cg_transaction_ids.get_coverage());
    $display("=========================================================\n");
    
    // Check for coverage holes
    if (total_coverage < 90.0) begin
      $display("WARNING: Coverage is below 90%% - more testing needed!");
    end else if (total_coverage < 95.0) begin
      $display("INFO: Good coverage, but some corner cases may be missing");
    end else begin
      $display("EXCELLENT: Coverage goal achieved!");
    end
  endfunction
  
endclass : axi4_coverage
`endif // AXI4_COVERAGE_SV
