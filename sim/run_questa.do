# QuestaSim do-file for AXI4 verification
# Usage: vsim -do run_questa.do

quietly set TB_TOP  "axi4_test"
quietly set TB_DIR  ".."
quietly set RTL_DIR "../rtl"

vlib work
vmap work work

vlog -sv +incdir+$TB_DIR +incdir+$RTL_DIR \
    $TB_DIR/axi4_pkg.sv           \
    $TB_DIR/axi4_transaction.sv   \
    $TB_DIR/axi4_driver.sv        \
    $TB_DIR/axi4_monitor.sv       \
    $TB_DIR/axi4_scoreboard.sv    \
    $TB_DIR/axi4_coverage.sv      \
    $TB_DIR/axi4_env.sv           \
    $TB_DIR/axi4_test.sv          \
    $TB_DIR/axi4_protocol_checker.sv \
    $RTL_DIR/axi4_slave.sv        \
    $RTL_DIR/axi4_master.sv

vsim -c work.$TB_TOP

run -all

coverage report -details
quit -f
