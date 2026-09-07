#!/usr/bin/env python3
"""
Generate memh/mlp_weights.memh from:
  1) W1_int8.txt   : 64 lines, each with 3600 signed int8 values
  2) W2_int8.txt   : 3 lines, each with 64 signed int8 values
  3) b1_int32.txt  : 1 line (or multiple lines), total 64 signed int32 values
  4) b2_int32.txt  : 1 line (or multiple lines), total 3 signed int32 values

Output:
  memh/mlp_weights.memh

Packing format:
- W1 first:
    Pack 4 rows at a time.
    For each column:
      row0 -> byte0 (LSB)
      row1 -> byte1
      row2 -> byte2
      row3 -> byte3 (MSB)
    Total: 16 groups * 3600 cols = 57600 words

- b1 next:
    64 int32 values, one 32-bit word per line

- W2 next:
    For each column:
      row0 -> byte0 (LSB)
      row1 -> byte1
      row2 -> byte2
      byte3 -> 0x00
    Total: 64 words

- b2 last:
    3 int32 values, one 32-bit word per line

Total output lines: 57731
"""

from pathlib import Path

BASE_DIR = Path(__file__).resolve().parent

W1_FILE = BASE_DIR / "W1_int8.txt"
W2_FILE = BASE_DIR / "W2_int8.txt"
B1_FILE = BASE_DIR / "b1_int32.txt"
B2_FILE = BASE_DIR / "b2_int32.txt"
OUT_FILE = BASE_DIR.parent / "memh" / "mlp_weights.memh"


def read_all_ints(path: str) -> list[int]:
    """Read all whitespace-separated integers from a text file."""
    try:
        text = Path(path).read_text(encoding="utf-8")
    except FileNotFoundError:
        raise FileNotFoundError(f"Could not find input file: {path}")
    except OSError as exc:
        raise OSError(f"Could not read file {path}: {exc}") from exc

    vals: list[int] = []
    for tok in text.split():
        try:
            vals.append(int(tok))
        except ValueError as exc:
            raise ValueError(f"Invalid integer '{tok}' in file {path}") from exc
    return vals


def read_matrix(path: str, rows: int, cols: int) -> list[list[int]]:
    """Read a matrix with exactly rows*cols integers, allowing arbitrary whitespace."""
    vals = read_all_ints(path)
    expected = rows * cols
    if len(vals) != expected:
        raise ValueError(
            f"{path}: expected {expected} integers for a {rows}x{cols} matrix, "
            f"but found {len(vals)}"
        )

    out: list[list[int]] = []
    idx = 0
    for _ in range(rows):
        out.append(vals[idx:idx + cols])
        idx += cols
    return out


def read_vector(path: str, length: int) -> list[int]:
    """Read exactly length integers from a text file, allowing arbitrary whitespace."""
    vals = read_all_ints(path)
    if len(vals) != length:
        raise ValueError(
            f"{path}: expected {length} integers, but found {len(vals)}"
        )
    return vals


def check_int8(val: int, name: str) -> None:
    if not (-128 <= val <= 127):
        raise ValueError(f"{name}: value {val} is out of signed int8 range")


def check_int32(val: int, name: str) -> None:
    if not (-2**31 <= val <= 2**31 - 1):
        raise ValueError(f"{name}: value {val} is out of signed int32 range")


def int8_to_u8(val: int) -> int:
    """Convert signed int8 to unsigned 8-bit two's-complement representation."""
    check_int8(val, "int8")
    return val & 0xFF


def int32_to_u32(val: int) -> int:
    """Convert signed int32 to unsigned 32-bit two's-complement representation."""
    check_int32(val, "int32")
    return val & 0xFFFFFFFF


def word_to_hex(word: int) -> str:
    """Format a 32-bit word as 8 hex digits."""
    return f"{word & 0xFFFFFFFF:08x}"


def build_memh_lines(
    w1: list[list[int]],
    w2: list[list[int]],
    b1: list[int],
    b2: list[int],
) -> list[str]:
    lines: list[str] = []

    # -------------------------
    # W1: 64 x 3600 int8
    # Pack 4 rows at a time.
    # For each column:
    #   row0 -> bits [7:0]
    #   row1 -> bits [15:8]
    #   row2 -> bits [23:16]
    #   row3 -> bits [31:24]
    # -------------------------
    for row_base in range(0, 64, 4):
        for col in range(3600):
            b0 = int8_to_u8(w1[row_base + 0][col])
            b1_ = int8_to_u8(w1[row_base + 1][col])
            b2_ = int8_to_u8(w1[row_base + 2][col])
            b3 = int8_to_u8(w1[row_base + 3][col])

            word = (
                b0
                | (b1_ << 8)
                | (b2_ << 16)
                | (b3 << 24)
            )
            lines.append(word_to_hex(word))

    # -------------------------
    # b1: 64 int32
    # One 32-bit word per line
    # -------------------------
    for val in b1:
        lines.append(word_to_hex(int32_to_u32(val)))

    # -------------------------
    # W2: 3 x 64 int8
    # For each column:
    #   row0 -> bits [7:0]
    #   row1 -> bits [15:8]
    #   row2 -> bits [23:16]
    #   bits [31:24] = 0
    # -------------------------
    for col in range(64):
        b0 = int8_to_u8(w2[0][col])
        b1_ = int8_to_u8(w2[1][col])
        b2_ = int8_to_u8(w2[2][col])

        word = (
            b0
            | (b1_ << 8)
            | (b2_ << 16)
        )
        lines.append(word_to_hex(word))

    # -------------------------
    # b2: 3 int32
    # One 32-bit word per line
    # -------------------------
    for val in b2:
        lines.append(word_to_hex(int32_to_u32(val)))

    return lines


def main() -> None:
    w1 = read_matrix(W1_FILE, rows=64, cols=3600)
    w2 = read_matrix(W2_FILE, rows=3, cols=64)
    b1 = read_vector(B1_FILE, length=64)
    b2 = read_vector(B2_FILE, length=3)

    memh_lines = build_memh_lines(w1, w2, b1, b2)

    expected_lines = 57600 + 64 + 64 + 3
    if len(memh_lines) != expected_lines:
        raise RuntimeError(
            f"Internal error: expected {expected_lines} output lines, "
            f"but generated {len(memh_lines)}"
        )

    OUT_FILE.parent.mkdir(parents=True, exist_ok=True)
    try:
        Path(OUT_FILE).write_text("\n".join(memh_lines) + "\n", encoding="utf-8")
    except OSError as exc:
        raise OSError(f"Could not write output file {OUT_FILE}: {exc}") from exc

    print(f"Wrote {OUT_FILE} with {len(memh_lines)} lines.")
    print("Address map:")
    print("  W1 :     0 .. 57599")
    print("  b1 : 57600 .. 57663")
    print("  W2 : 57664 .. 57727")
    print("  b2 : 57728 .. 57730")


if __name__ == "__main__":
    main()
