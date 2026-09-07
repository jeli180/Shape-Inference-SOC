# Data-cache synthesis changes

## Problem

The original combinational block copied every data, tag, valid, dirty, and MRU
entry into parallel `next_*` arrays on every cycle. That expressed a full-bank
next-state mux even though one transaction can modify at most one cache line.
In the complete design, the cache accounted for about 33,899 LUT4s.

## Change

The `next_*` cache arrays were replaced with one write address, one write value
per field, and explicit write enables. The sequential block now updates only
the selected set and way. Registered CPU/MSHR outputs and their priority remain
unchanged:

1. complete an MSHR load and install the returned line;
2. detect an address dependency;
3. service way 1, then way 0;
4. handle a full-MSHR store or stall;
5. issue a load miss or replace a line for a store miss.

This reduced `dcache0` to about 20,270 LUT4s, a saving of roughly 13,600 LUTs.
It also removes the wide feedback muxes created by copying the full cache bank.

## Equivalence

This refactor is cycle-equivalent. A Yosys equivalence check against the
pre-change implementation proved all 7,676 comparison points in the full
64-set design. A fresh reduced two-set run on 2026-09-06 proved all 503 points;
the reduced instance exercises the same hit, miss, replacement, stall, and
per-field write logic with a smaller replicated array.

The write enables do not permit two cache entries to change in one cycle. This
matches the original priority-ordered combinational block, whose later branch
selection also produced only one selected line update per cycle.

## Packed, reset-free payload memories

The data and tag arrays are now combined into one 56-bit payload per line. Each
way has its own 64-entry memory, and each payload is `{tag, data}`. A store hit
preserves the stored tag and replaces only the low 32 data bits; a fill or store
miss writes the complete payload. Splitting the two ways into separate memories
gives each memory one asynchronous read port and one write port, matching the
actual cache access pattern.

Payload reset was removed. The valid and dirty arrays remain reset exactly as
before, and every hit or eviction use is guarded by the selected line's valid
bit. An invalid payload therefore cannot affect any cache output. Payload writes
are also suppressed while reset is asserted.

Standalone ECP5 synthesis with `-noabc9` changed as follows:

| Version | LUT4 | TRELLIS_FF | TRELLIS_DPR16X4 |
| --- | ---: | ---: | ---: |
| Separate reset data/tag arrays | 27,157 | 7,530 | 0 |
| Packed payload memories | 4,057 | 362 | 112 |

With the circular MSHR and banked tensor result store already present, the full
SoC fell from 46,471 to 19,689 LUT4s and from 12,530 to 5,362 flip-flops. Total
distributed-RAM use is 256 `TRELLIS_DPR16X4` primitives: 144 for tensor results
and 112 for the dcache payloads.

The complete 64-set formal miter reached its 300-second bound without producing
a counterexample. A tractable two-set, two-way miter then proved every visible
output cycle-equivalent over a five-cycle trace with four arbitrary post-reset
cycles. That sequence can
fill both replacement ways and observe a later hit or eviction, while retaining
the complete tag/data widths and all controller branches. A separate seeded
model passed 1,000,000 randomized payload writes, data-only store-hit writes,
invalidations, and valid reads over all 64 sets. Structural checking and full
SoC synthesis both report zero problems.
