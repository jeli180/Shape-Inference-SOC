# Backing-memory synthesis changes

## Problem

The backing memory read and write ports were inside an asynchronously reset
transaction process. That structure prevented reliable ECP5 block-RAM
inference and contributed a large distributed-logic implementation.

## Change

The RAM port was moved into a separate clocked block without reset:

- a read is sampled when a non-write request is accepted;
- the sampled value remains private until the original completion cycle;
- a write still updates memory on the original completion cycle;
- `busy`, `valid`, request capture, latency count, and visible `rdata` remain in
  the original handshake process.

The memory is marked with `ram_style = "block"`. A 2,048 x 32 standalone
instance maps to four DP16KD blocks.

## Equivalence

This refactor is cycle-equivalent. On 2026-09-06, Yosys proved all 234
state/output equivalence points on a four-word instance. Combinational matching
proved 74 points, and five-step sequential induction proved the remaining 160
memory and `rdata` points. The reduced depth keeps the same transaction state
machine and memory-port timing while making the complete proof tractable.
