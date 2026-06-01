#!/usr/bin/env bash
# AXI4 Verification Run Script (Linux/Mac)
# Auto-detects available simulator
set -e

TB_TOP="axi4_test"
TB_DIR=".."
RTL_DIR="../rtl"

SV_FILES="
  $TB_DIR/axi4_pkg.sv
  $TB_DIR/axi4_transaction.sv
  $TB_DIR/axi4_driver.sv
  $TB_DIR/axi4_monitor.sv
  $TB_DIR/axi4_scoreboard.sv
  $TB_DIR/axi4_coverage.sv
  $TB_DIR/axi4_env.sv
  $TB_DIR/axi4_test.sv
  $TB_DIR/axi4_protocol_checker.sv
  $RTL_DIR/axi4_slave.sv
  $RTL_DIR/axi4_master.sv
"

run_questa() {
  echo "[INFO] Running with QuestaSim/ModelSim"
  vlib work
  vlog -sv +incdir+$TB_DIR +incdir+$RTL_DIR $SV_FILES
  vsim -c $TB_TOP -do "run -all; quit -f" | tee sim.log
}

run_xcelium() {
  echo "[INFO] Running with Cadence Xcelium"
  xrun -sv +incdir+$TB_DIR +incdir+$RTL_DIR \
       -top $TB_TOP -coverage all $SV_FILES 2>&1 | tee sim.log
}

run_vcs() {
  echo "[INFO] Running with Synopsys VCS"
  vcs -sverilog +incdir+$TB_DIR +incdir+$RTL_DIR \
      -top $TB_TOP $SV_FILES -o simv
  ./simv 2>&1 | tee sim.log
}

run_vivado() {
  echo "[INFO] Running with Xilinx Vivado xsim"
  xvlog --sv +incdir+$TB_DIR +incdir+$RTL_DIR $SV_FILES
  xelab -debug typical $TB_TOP -s ${TB_TOP}_sim
  xsim ${TB_TOP}_sim --runall 2>&1 | tee sim.log
}

# Auto-detect
if   command -v vsim  &>/dev/null; then run_questa
elif command -v xrun  &>/dev/null; then run_xcelium
elif command -v vcs   &>/dev/null; then run_vcs
elif command -v xsim  &>/dev/null; then run_vivado
else
  echo "ERROR: No supported simulator found."
  echo "Install one of: QuestaSim, Xcelium, VCS, Vivado"
  exit 1
fi

echo ""
echo "Simulation log: sim.log"
grep -E "PASS|FAIL|ERROR|Coverage" sim.log || true
