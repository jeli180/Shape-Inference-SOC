# SoC clock and UART changes

## Clock change

The integrated UART-only top now clocks the CPU, MMIO, dcache, MSHR, UART
tower, tensor controller, and systolic array from the existing 12.5 MHz divider
output. Keeping every connected state machine in one domain avoids adding any
clock-domain crossing.

The LPF declares `clk_12_5mhz` as a 12.5 MHz generated-clock net. Preliminary
placement reported 15.71 MHz maximum for that domain, passing its 12.5 MHz
constraint. The earlier 25 MHz build reported only about 13.8 MHz and failed
timing.

This change preserves edge-by-edge logic behavior when cycles are counted in
the local SoC clock. It is not wall-clock equivalent: a fixed number of SoC
cycles takes twice as long.

## UART parameter propagation

`CLK_HZ` was added to `ingress_buffer`, `egress_buffer`, and `uart_tower` and is
passed into `uart_reciever` and `uart_transmitter`. Defaults remain 25 MHz, so
existing instantiations that do not override the parameter are cycle-equivalent
to the old RTL. The integrated top overrides it with 12.5 MHz so UART bit timing
tracks the slower clock while retaining the configured 115,200 baud protocol.

No UART framing, byte ordering, credit accounting, or MMIO behavior was
changed by this parameter plumbing.

At the unchanged 25 MHz default, Yosys equivalence checks on 2026-09-06 proved
593/593 ingress-buffer points, 115/115 egress-buffer points, and 873/873 points
for the complete flattened UART tower. This confirms exact cycle equivalence
of the parameter-plumbing change at the old default.
