# UART-only integration top

`fpga_test/all/top.sv` is the complete board wrapper prepared for this build.
It instantiates and connects:

- CPU and MMIO decoder;
- two-way data cache and four-entry MSHR;
- UART tower, including its ingress receiver and egress transmitter;
- tensor controller and 4 x 4 systolic array;
- the existing board-clock divider and button edge detectors.

The physical-screen DPU instance was removed at the user's direction because
MMIO addresses 4 and 8 are assigned to the UART drawing interface for this
build. FPGA `ftdi_txd` feeds the UART receiver and UART transmit drives
`ftdi_rxd`. Button 0 is the active-low board reset. Unused `gp` and `gn` pins
are tri-stated.

This file is new integration behavior rather than a refactor of a committed
equivalent top, so a before/after cycle-equivalence claim does not apply. Yosys
hierarchy checking confirms that the complete wrapper resolves all instances
and ports. The module-level refactors instantiated by it are covered in the
other documents in this directory.
