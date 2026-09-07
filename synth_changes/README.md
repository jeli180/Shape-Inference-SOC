# Synthesis-change record

This directory records the RTL and build changes made during the full-system
pre-flash audit. The changes reduced the synthesized design from roughly
144,027 LUT4s (172% of the ECP5-85K) to 19,689 LUT4s before packing. The final
routed design uses 23,835 `TRELLIS_COMB` sites (28%), 5,362 flip-flops (6%),
and 128 DP16KD blocks (61%), and closes the 12.5 MHz clock at 24.65 MHz.

## Equivalence summary

"Cycle-equivalent" below means that, for the same inputs on each active local
clock edge after reset, the module produces the same externally visible value
on the same local clock edge.

| Change | Result |
| --- | --- |
| `dcache.sv` write-enable refactor | Cycle-equivalent |
| `dcache.sv` packed payload memories | Cycle-equivalent at the cache interface; invalid payload is gated by reset valid bits |
| `mshr.sv` circular FIFO | Cycle-equivalent for reset-reachable queue operation |
| `wb_1cycle.sv` block-ROM inference refactor | Cycle-equivalent for valid ROM addresses |
| `wb_simulator.sv` block-RAM inference refactor | Cycle-equivalent |
| UART `CLK_HZ` parameter plumbing | Cycle-equivalent when the parameter remains at its old 25 MHz default |
| Weight-ROM depth 57,800 -> 57,731 | Cycle-equivalent for all addresses used by the controller |
| Tensor ReLU/quantization serialization | Functionally equivalent result, intentionally 126 local clocks longer |
| Tensor banked result storage | Cycle-equivalent at the controller interface |
| Tensor `ct2` width 6 -> 7 bits | Intentional correctness fix, not strictly equivalent to the wrapping 6-bit counter |
| Whole-SoC clock 25 -> 12.5 MHz | Same edge-by-edge RTL behavior outside the two tensor exceptions, but not wall-clock equivalent |
| Router selection and timing constraint | Build-only; no RTL behavior change |

The blanket statement that every change except neuron serialization is
strictly cycle-equivalent would therefore be inaccurate. The `ct2` correction
changes an erroneous terminal-counter case, and the clock change doubles the
wall-clock duration of a fixed number of SoC cycles. Details and validation
scope are in the module-specific files.

## Documents

- [dcache.md](dcache.md)
- [mshr.md](mshr.md)
- [wb_1cycle.md](wb_1cycle.md)
- [wb_simulator.md](wb_simulator.md)
- [tensor_controller.md](tensor_controller.md)
- [clock_uart.md](clock_uart.md)
- [build.md](build.md)
- [integration_top.md](integration_top.md)
- [software_and_program.md](software_and_program.md)
