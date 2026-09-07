# Drawing application and CPU program changes

These changes are recorded here for completeness, although they did not cause
the FPGA LUT or timing reductions.

## Drawing application

The new `drawing_app` package provides the Tk drawing UI, serial worker,
protocol state machine, demo port, and protocol tests. It implements INIT,
DRAW, Wait, and Done states; recognizes reset as the special 31-credit grant;
spends one credit per transmitted byte; and consumes the two-byte shape reply.

Each 240 x 240 quadrant is OR-pooled in 4 x 4 cells to 60 x 60 bits. Bits are
packed 30 per word in row-major quadrant order, with valid in bit 30 and the
last-drawing marker in bit 31. Words are transmitted little-endian, producing
1,920 bytes per drawing. Twelve protocol tests pass.

## Assembly program

`assembly/int_everything.asm` was made into an explicit `.text` program with a
global `_start`. It also received three functional corrections:

- reset the cross-word pack count and accumulator at each quadrant boundary;
- form the four cache addresses in registers before using legal `lw 0(reg)`
  instructions;
- repeat the first-layer input traversal 16 times for all 64 neurons.

These are intentional program fixes, not cycle-equivalent substitutions for
the previous assembly. `instruction_memory.memh` contains 153 RV32I words and
was checked instruction-for-instruction against the assembled source. It uses
no compressed instructions.
