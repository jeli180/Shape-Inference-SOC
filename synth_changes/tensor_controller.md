# Tensor-controller synthesis changes

## Weight ROM depth

The instantiated depth was reduced from 57,800 words to the exact 57,731 words
present in `memh/mlp_weights.memh`. All controller-generated weight addresses remain
in that range, so this change is cycle-equivalent for every reachable request.

## Serialized ReLU and quantization

The original `RELU` state updated 64 neurons in parallel, and `QUANT` performed
four repeated rounding, shifting, and saturation expressions for all 64
neurons in parallel. This was the largest LUT and critical-path source.

Both states now use `col_ct[5:0]` to process one neuron in each of the four
quadrants per cycle. After neuron 63, the controller resets `col_ct` and moves
to the next state. The final values are the same because each neuron's ReLU and
quantization depend only on that neuron's stored accumulator and the fixed
shift value.

This intentionally changes latency:

- old sequence: one `RELU` cycle plus one `QUANT` cycle;
- new sequence: 64 `RELU` cycles plus 64 `QUANT` cycles;
- added latency: 126 local clocks, or 10.08 microseconds at 12.5 MHz.

The CPU already polls/waits for the tensor controller, so no interface timeout
or fixed-cycle consumer is crossed. The tensor block fell from about 75,516 to
24,690 LUT4s.

## Banked layer-result storage

The four 64-word layer-one quadrant arrays and their four complete next-state
copies were replaced by four interleaved banks. A bank word is 128 bits and
holds one neuron's four quadrant results as `{q4, q3, q2, q1}`. Neuron index
bits `[1:0]` select the bank and bits `[5:2]` select its address.

This organization matches the existing access schedule:

- `STORE_1` still stores four consecutive neurons in one clock by writing one
  word to each of the four banks;
- bias, ReLU, and quantization still update one logical neuron per clock;
- `L2_FILL` reads the same neuron values in the same order;
- the four quadrants retain the same low-to-high order at the systolic-array
  input and class-result output.

Writes use explicit enables instead of assigning every stored word through a
large combinational next-state mux. The banks are written from a reset-free
clocked process. Resetting their payload is unnecessary because every one of
the 64 layer-one locations is overwritten by `STORE_1` before bias or layer two
can consume it. The three layer-two entries are likewise completely
overwritten by `STORE_2` before use.

The original single-array packed experiment was rejected: its effective
multiport access expanded to 38,935 standalone LUT4s and 9,422 flip-flops. The
interleaved four-bank implementation maps to 144 `TRELLIS_DPR16X4` distributed
RAM primitives. With identical standalone synthesis settings, it reduced the
controller from 94,412 to 9,009 LUT4s and from 9,293 to 1,102 flip-flops. Those
standalone figures expose all controller ports and are useful as a relative
comparison; complete-SoC synthesis is the implementation metric.

With the circular MSHR already present, complete-SoC synthesis fell from
55,061 to 46,471 LUT4s and from 20,614 to 12,530 flip-flops. The new version
uses 144 distributed-RAM primitives and retains all 128 block-RAM instances.

Structural checking reports no problems. A 10,000-case seeded randomized model
confirmed that the interleaved representation produces the same results for
the layer-one STORE, bias, ReLU, and quantization passes and reconstructs every
logical neuron and quadrant identically. The banked-storage change is
cycle-equivalent at the controller interface; only the previously documented
one-neuron-per-clock ReLU/quantization change alters latency.

## `ct2` width correction

`ct2` was widened from six to seven bits. The `L2_FILL` code explicitly tests
`ct2 < 64`, so the counter must be able to hold the terminal value 64. With six
bits, an increment from 63 wrapped to zero and could reintroduce layer-one
values instead of stopping.

This is an intentional correctness fix and is not cycle-equivalent to the old
wrapping behavior. It preserves the behavior intended by the existing
comparison and comments.
