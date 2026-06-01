// AXI4 Verification Package
`ifndef AXI4_PKG_SV
`define AXI4_PKG_SV

package axi4_pkg;
  
  // AXI4 Protocol Parameters
  parameter int ADDR_WIDTH = 32;
  parameter int DATA_WIDTH = 64;
  parameter int ID_WIDTH = 4;
  parameter int STRB_WIDTH = DATA_WIDTH/8;
  
  // Burst Types
  typedef enum bit [1:0] {
    FIXED = 2'b00,
    INCR  = 2'b01,
    WRAP  = 2'b10
  } burst_type_e;
  
  // Response Types
  typedef enum bit [1:0] {
    OKAY   = 2'b00,
    EXOKAY = 2'b01,
    SLVERR = 2'b10,
    DECERR = 2'b11
  } resp_type_e;
  
  // Burst Sizes
  typedef enum bit [2:0] {
    SIZE_1B   = 3'b000,
    SIZE_2B   = 3'b001,
    SIZE_4B   = 3'b010,
    SIZE_8B   = 3'b011,
    SIZE_16B  = 3'b100,
    SIZE_32B  = 3'b101,
    SIZE_64B  = 3'b110,
    SIZE_128B = 3'b111
  } burst_size_e;
  
  // Coverage groups for functional coverage
  typedef enum {
    WRITE_ADDR_CH,
    WRITE_DATA_CH,
    WRITE_RESP_CH,
    READ_ADDR_CH,
    READ_DATA_CH
  } channel_type_e;
  
  // Transaction Status
  typedef enum {
    IDLE,
    ACTIVE,
    WAITING,
    COMPLETED,
    ERROR
  } transaction_status_e;
  
endpackage : axi4_pkg
`endif // AXI4_PKG_SV
