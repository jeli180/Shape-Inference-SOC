# MSHR synthesis changes

## Original problem

The original queue used six separate unpacked current/next arrays and dynamic
destinations such as `last_filled + 1`. Yosys created an out-of-range index-zero
path and reported an inferred latch. Replacing those writes with fixed cases
removed the latch, and packing each slot into one 72-bit entry reduced the
complete-design estimate from about 13,269 to 7,678 LUT4s.

## Circular FIFO

The packed queue still copied and shifted all four 72-bit entries on each
completion. It is now a four-slot circular FIFO with:

- two-bit `head` and `tail` pointers;
- a three-bit entry count;
- four stationary packed entries;
- explicit per-slot write enables;
- at most one pop and two load-before-eviction appends per clock.

When a full FIFO pops and appends on the same clock, the append intentionally
overrides clearing the reused physical slot. The head still advances to the
previous second entry, so transaction order is unchanged.

`addr1` through `addr4` are rotated by `head` and continue to expose logical
queue order. This is stricter than the dcache requires—the dcache only compares
all four addresses—but preserves the previous MSHR interface exactly.

The `full` threshold remains three occupied entries, reserving the fourth slot
for a possible load-plus-eviction pair. If only one slot is available and both
arrive, the load is retained and the eviction is dropped, matching the old
priority. The `IDLE -> REQ -> WAIT` request timing and registered completion
outputs are unchanged.

## Synthesis result

Standalone ECP5 synthesis with the project's `-noabc9` setting reports:

| Version | LUT4 | TRELLIS_FF | DP16KD |
| --- | ---: | ---: | ---: |
| Packed shifting queue | 3,160 | 520 | 4 |
| Circular FIFO | 2,250 | 523 | 4 |

The circular FIFO saves 910 standalone LUT4s, about 29%, without changing the
backing-memory implementation. In the complete SoC netlist, total LUT4 use fell
from 61,691 to 55,061, a reduction of 6,630 LUT4s. The larger system-level
change includes cross-module optimization around the MSHR/dcache/CPU interface,
so it should not be interpreted as 6,630 cells physically located only inside
the MSHR hierarchy.

## Validation

Validation performed on 2026-09-06:

- Yosys process conversion and structural checking reported zero problems.
- A five-cycle SAT miter and an eight-cycle SAT miter both proved every
  externally visible MSHR output and backing-memory request equal for arbitrary
  request inputs and arbitrary memory response/data inputs after reset.
- The eight-cycle proof used 1,631,559 SAT variables and 4,402,991 clauses and
  completed successfully.
- An independent shift-queue/ring-queue model passed 1,000,000 seeded random
  cycles, including pointer wraparound, full queues, stalled waits, and
  simultaneous pop plus one/two-entry append cases.
- The block-RAM transaction wrapper is separately proven cycle-equivalent to
  its original implementation; see `wb_simulator.md`.

The ring representation is therefore cycle-equivalent at the complete MSHR
interface for reset-reachable queue operation under the existing no-overflow
contract.
