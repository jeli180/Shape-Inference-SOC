.PHONY: all bitstream flash flash-spi reload identify clean

TOP      ?= top
SRCS     ?= src/top.sv
LPF      ?= constraints/ulx3s_v20.lpf
DEVICE   ?= --85k
PACKAGE  ?= CABGA381
BUILD    ?= build
SYNTH_FLAGS ?= -noabc9
PNR_FLAGS   ?= --router router2

JSON     := $(BUILD)/$(TOP).json
CONFIG   := $(BUILD)/$(TOP).config
BIT      := $(BUILD)/$(TOP).bit

all: bitstream

bitstream: $(BIT)

$(BUILD):
	mkdir -p $(BUILD)

$(JSON): $(SRCS) | $(BUILD)
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

clean:
	rm -rf $(BUILD)
