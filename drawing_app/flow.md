# App / CPU protocol

UART is 115200 baud, 8N1 by default. Each frame carries one byte.

## CPU to app

- `01cccccc`: grant the bottom six bits in byte credits. Add ordinary grants.
- `0x5F` (31 credits): hardware reset; replace credits with 31, abort the upload,
  clear the drawing/results and return to INIT. Hardware must send this before
  its initialization zero. Normal operation must reserve grants of 31 for reset.
- `0x00`: enter DRAW from INIT after the reset grant. Ignore pixel acknowledgment
  zeros in other states.
- `0x80`: shape header. The next byte is unconditionally the shape payload:
  `[Q4:2][Q3:2][Q2:2][Q1:2]`. Codes: 00 blank/unclassified, 01 line,
  10 square, 11 circle. Header and payload must be consecutive UART bytes.

## App to CPU

Only pixel bytes are sent. Every byte spends a credit. Pause at zero credits,
including in the middle of a word, while continuing to receive UART messages.

Quadrants are Q1 top left, Q2 top right, Q3 bottom left, Q4 bottom right.
Each is 240x240 binary pixels (ink=1). OR each 4x4 cluster to produce 60x60 bits.
Traverse each quadrant left to right, top to bottom, then advance to the next
quadrant. Pack 30 pixels into bits 0..29, earliest pixel in bit 0. Bit 30 is
always 1 (valid); bit 31 is 1 only on the last word of Q4. Send each word as
four bytes, least significant byte first. Total: 120 words per quadrant,
480 words / 1920 bytes per drawing.

## Interface flow

INIT -> reset grant then CPU zero -> DRAW -> Submit -> Wait (upload/inference)
-> header and classes -> Done -> Next -> DRAW.

Drawing is enabled only in DRAW. Next clears locally, sends nothing, and
preserves credits. This matches the polling loop in assembly/int_everything.asm;
there is no full-done byte or restart acknowledgment between normal rounds.

## Accepted reset limitations

After a shape header, 0x5F is valid shape data and is not treated as a reset.
A reset between header and payload can therefore be missed; reset hardware
again to recover. This is the agreed tradeoff, not an escaping/framing scheme.
On a recognized reset the app cancels queued upload data and asks the serial
driver to discard pending output. Bytes already on the wire or inside a USB
adapter cannot necessarily be recalled. If resetting during an upload leaves
the hardware out of sync, reset it again after transmission has stopped.
Connect the app before resetting hardware so it receives the startup grant.
