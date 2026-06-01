# AXI4 Verification Makefile
# Supports: QuestaSim/ModelSim (vsim), Xcelium (xrun), VCS (vcs), Vivado (xvlog/xelab/xsim)
# Usage:  make sim           -> QuestaSim (default)
#         make sim_xrun      -> Cadence Xcelium
#         make sim_vcs       -> Synopsys VCS
#         make sim_vivado    -> Xilinx Vivado Simulator

TB_TOP   = axi4_test
RTL_DIR  = ../rtl
TB_DIR   = ..
SIM_DIR  = work

SV_FILES = \
    $(TB_DIR)/axi4_pkg.sv          \
    $(TB_DIR)/axi4_transaction.sv  \
    $(TB_DIR)/axi4_driver.sv       \
    $(TB_DIR)/axi4_monitor.sv      \
    $(TB_DIR)/axi4_scoreboard.sv   \
    $(TB_DIR)/axi4_coverage.sv     \
    $(TB_DIR)/axi4_env.sv          \
    $(TB_DIR)/axi4_test.sv

ASSERT_FILES = \
    $(TB_DIR)/axi4_protocol_checker.sv

RTL_FILES = \
    $(RTL_DIR)/axi4_slave.sv  \
    $(RTL_DIR)/axi4_master.sv

ALL_FILES = $(SV_FILES) $(ASSERT_FILES) $(RTL_FILES)

# ── QuestaSim / ModelSim ────────────────────────────────────────────────────
sim: compile_questa run_questa

compile_questa:
	vlib $(SIM_DIR)
	vmap work $(SIM_DIR)
	vlog -sv -work work +incdir+$(TB_DIR) +incdir+$(RTL_DIR) $(ALL_FILES)

run_questa:
	vsim -c work.$(TB_TOP) -do "run -all; quit -f"

sim_gui:
	vsim work.$(TB_TOP) -do "add wave -r /*; run -all"

# ── Cadence Xcelium ─────────────────────────────────────────────────────────
sim_xrun:
	xrun -sv +incdir+$(TB_DIR) +incdir+$(RTL_DIR) \
	     -top $(TB_TOP) $(ALL_FILES) \
	     -coverage all -covdut $(TB_TOP)

# ── Synopsys VCS ─────────────────────────────────────────────────────────────
sim_vcs:
	vcs -sverilog +incdir+$(TB_DIR) +incdir+$(RTL_DIR) \
	    -top $(TB_TOP) $(ALL_FILES) \
	    -cm line+cond+fsm+tgl+branch -o simv
	./simv -cm line+cond+fsm+tgl+branch

# ── Xilinx Vivado Simulator (xsim) ───────────────────────────────────────────
sim_vivado:
	xvlog --sv +incdir+$(TB_DIR) +incdir+$(RTL_DIR) $(ALL_FILES)
	xelab -debug typical $(TB_TOP) -s $(TB_TOP)_sim
	xsim $(TB_TOP)_sim --runall

# ── Coverage report ──────────────────────────────────────────────────────────
cov_report:
	vcover report -details -html $(SIM_DIR)

# ── Clean ─────────────────────────────────────────────────────────────────────
clean:
	rm -rf $(SIM_DIR) simv* csrc* xcelium.d* *.log *.jou *.pb *.wdb

.PHONY: sim compile_questa run_questa sim_gui sim_xrun sim_vcs sim_vivado cov_report clean
