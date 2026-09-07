# One-cycle weight-ROM synthesis changes

## Problem

The weight table was described as an asynchronous array read feeding an
asynchronously reset output register. On ECP5, that form did not infer block
RAM for the 57,731-word table and expanded the ROM into logic.

## Change

- Add `ADDR_WIDTH = $clog2(DEPTH)` and index only the implemented address bits.
- Mark the memory with `ram_style = "block"`.
- Register the memory read in an always block without reset logic.
- Register `ren` separately as `ren_d` and drive zero when the previous cycle
  did not request a read.

The visible contract remains: one cycle after `ren`, `rdata` contains the
selected word; one cycle after `ren` is low, `rdata` is zero. Standalone ECP5
synthesis maps the weight ROM to 104 DP16KD blocks.

## Equivalence

The control/read refactor is cycle-equivalent for addresses in `0..DEPTH-1`.
On 2026-09-06, Yosys proved all 32 `rdata` bits against the pre-change module.
The proof used a four-word instance so the complete initialized memory could be
mapped into SAT state; depth does not alter the read-control equation.

Truncating the address to `$clog2(DEPTH)` bits does not make arbitrary
out-of-range accesses meaningful. The tensor controller only requests valid
weight addresses, which is the interface domain covered by this equivalence
claim.
