.PHONY: all bitstream flash flash-spi reload identify sim wave clean-sim clean

TOP      ?= top
SRCS     ?= src/top.sv
LPF      ?= constraints/ulx3s_v20.lpf
DEVICE   ?= --85k
PACKAGE  ?= CABGA381
BUILD    ?= build
MEMH     ?= memh/instruction_memory.memh memh/data.memh memh/mlp_weights.memh
SYNTH_FLAGS ?= -noabc9
PNR_FLAGS   ?= --router router2

IVERILOG  ?= iverilog
VVP        ?= vvp
GTKWAVE    ?= gtkwave
TB         ?=
SIM_BUILD  ?= build/sim
SIM_WAVE   ?= sim/waves.vcd
RTL_SRCS   := $(sort $(wildcard src/*.v src/*.sv src/*/*.v src/*/*.sv))
TB_SRCS    := $(sort $(wildcard tb/*.v tb/*.sv tb/*/*.v tb/*/*.sv))

JSON     := $(BUILD)/$(TOP).json
CONFIG   := $(BUILD)/$(TOP).config
BIT      := $(BUILD)/$(TOP).bit

all: bitstream

bitstream: $(BIT)

$(BUILD):
	mkdir -p $(BUILD)

$(JSON): $(SRCS) $(MEMH) | $(BUILD)
	yosys -p 'read_verilog -sv $(SRCS); synth_ecp5 $(SYNTH_FLAGS) -top $(TOP) -json $(JSON)'

$(CONFIG): $(JSON) $(LPF)
	nextpnr-ecp5 $(DEVICE) --package $(PACKAGE) --json $(JSON) --lpf $(LPF) --textcfg $(CONFIG) $(PNR_FLAGS)

$(BIT): $(CONFIG)
	ecppack $(CONFIG) $(BIT)

# Programs FPGA SRAM. This does not persist after power cycle.
flash: $(BIT)
	fujprog $(BIT)

# Writes the bitstream to SPI flash. This persists after power cycle.
flash-spi: $(BIT)
	fujprog -j FLASH $(BIT)

reload:
	fujprog -r

identify:
	fujprog -i

# Compile and run a SystemVerilog testbench, for example:
#   make sim TB=tb_icache
sim:
	@test -n "$(TB)" || { echo "Usage: make sim TB=<testbench_top_module>"; exit 2; }
	mkdir -p $(SIM_BUILD) sim
	$(IVERILOG) -g2012 -s $(TB) -o $(SIM_BUILD)/sim_$(TB).out $(RTL_SRCS) $(TB_SRCS)
	$(VVP) $(SIM_BUILD)/sim_$(TB).out

# Run the testbench, then open the VCD it produced.
wave: sim
	@test -f $(SIM_WAVE) || { echo "No $(SIM_WAVE) was produced by $(TB)"; exit 2; }
	$(GTKWAVE) $(SIM_WAVE)

clean-sim:
	rm -rf $(SIM_BUILD) $(SIM_WAVE)

clean:
	rm -rf $(BUILD)
