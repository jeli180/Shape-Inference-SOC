# Build and routing changes

## Router selection

The Makefile now defines `PNR_FLAGS ?= --router router2` and appends it to the
`nextpnr-ecp5` command. This selects nextpnr's second router for the dense
ECP5-85K design; it changes implementation tooling only and has no RTL or
cycle-level behavior.

## Optimization checkpoints

The pre-optimization design synthesized to 61,691 LUT4s. Router2 could not
route it: the best observed iteration still had 23,404 overused wires.

The circular MSHR checkpoint synthesized to 55,061 LUT4s. Its route was stopped
after congestion flattened at 27,780 overused wires. This was a different
placement from the earlier attempt, so its routing count is not a monotonic
measure of the LUT reduction.

Adding banked tensor result storage reduced synthesis to 46,471 LUT4s and
12,530 flip-flops. That checkpoint routed successfully and reached 17.67 MHz in
the 12.5 MHz clock domain. Its retained bitstream is
`build/all_uart_tensor_banked/top.bit`.

## Final routed build

The final build includes the circular MSHR, banked tensor result storage, and
packed dcache payload memories. Yosys reports:

- 19,689 LUT4s;
- 5,362 flip-flops;
- 256 `TRELLIS_DPR16X4` distributed-RAM primitives;
- 128 DP16KD block-RAM instances;
- 17 `MULT18X18D` multipliers.

After packing, nextpnr reports 23,835 of 83,640 `TRELLIS_COMB` sites (28%),
5,362 flip-flops (6%), and 128 of 208 block RAMs (61%). Router2 reached zero
overused wires at iteration 55 and completed with zero errors. Final routed
timing is 24.65 MHz for the 12.5 MHz SoC clock, leaving 12.15 MHz of reported
frequency margin.

`ecppack` successfully produced `build/all_uart_optimized/top.bit`. The file is
930 KiB and has SHA-256:

`e939752a7822474b6a85fc024581e972b902398b86fc38d1c59d2f92e133d8a5`

This artifact is ready to flash, but it has not been programmed onto hardware.
