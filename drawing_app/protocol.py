"""Drawing model and byte protocol; independent of Tk and serial hardware."""

from dataclasses import dataclass

SIZE = 480
QUADRANT = 240
DRAWING_BYTES = 1920


class Drawing:
    def __init__(self):
        self.pixels = bytearray(SIZE * SIZE)

    def clear(self):
        self.pixels[:] = bytes(SIZE * SIZE)

    def stroke(self, start, end, width=5):
        """Rasterize a continuous round stroke, clipped to its starting quadrant."""
        x0, y0 = start
        x1, y1 = end
        if not (0 <= x0 < SIZE and 0 <= y0 < SIZE):
            return
        left, top = x0 // QUADRANT * QUADRANT, y0 // QUADRANT * QUADRANT
        steps = max(abs(x1 - x0), abs(y1 - y0), 1)
        radius = width // 2
        for step in range(steps + 1):
            x = round(x0 + (x1 - x0) * step / steps)
            y = round(y0 + (y1 - y0) * step / steps)
            for dy in range(-radius, radius + 1):
                for dx in range(-radius, radius + 1):
                    px, py = x + dx, y + dy
                    if (dx * dx + dy * dy <= radius * radius
                            and left <= px < left + QUADRANT
                            and top <= py < top + QUADRANT):
                        self.pixels[py * SIZE + px] = 1


def encode_pixels(pixels):
    """4x4 OR pool, Q1..Q4 row-major, 30 bits/word, little-endian."""
    if len(pixels) != SIZE * SIZE:
        raise ValueError("Expected a 480 by 480 binary drawing")
    output = bytearray()
    for ox, oy in ((0, 0), (240, 0), (0, 240), (240, 240)):
        word, bit = 0, 0
        for y in range(oy, oy + QUADRANT, 4):
            for x in range(ox, ox + QUADRANT, 4):
                ink = any(any(pixels[row * SIZE + x:row * SIZE + x + 4])
                          for row in range(y, y + 4))
                word |= int(ink) << bit
                bit += 1
                if bit == 30:
                    word |= 1 << 30
                    if len(output) == DRAWING_BYTES - 4:
                        word |= 1 << 31
                    output.extend(word.to_bytes(4, "little"))
                    word, bit = 0, 0
    return bytes(output)


@dataclass(frozen=True)
class Snapshot:
    state: str
    credits: int
    sent: int
    generation: int
    shapes: tuple


class Session:
    """Owned by the serial worker so receive/reset/send decisions are serialized."""

    def __init__(self):
        self.state = "INIT"
        self.credits = 0
        self.sent = 0
        self.generation = 0
        self.shapes = ()
        self.payload = b""
        self.expect_shapes = False
        self.saw_reset = False

    def snapshot(self):
        return Snapshot(self.state, self.credits, self.sent,
                        self.generation, self.shapes)

    def receive(self, data):
        """Return whether a reset grant was recognized in this chunk."""
        reset = False
        for byte in data:
            # A payload may equal any control byte, including 0x5f.
            if self.expect_shapes:
                self.expect_shapes = False
                if self.state == "WAIT":
                    self.shapes = tuple((byte >> (2 * q)) & 3 for q in range(4))
                    self.state = "DONE"
                continue
            if byte & 0xC0 == 0x40:
                grant = byte & 0x3F
                if grant == 31:
                    self.credits = 31
                    self.state = "INIT"
                    self.sent = 0
                    self.payload = b""
                    self.shapes = ()
                    self.expect_shapes = False
                    self.saw_reset = True
                    self.generation += 1
                    reset = True
                else:
                    self.credits += grant
            elif byte == 0x80:
                self.expect_shapes = True
            elif byte == 0 and self.state == "INIT" and self.saw_reset:
                self.state = "DRAW"
        return reset

    def submit(self, payload, generation):
        if self.state != "DRAW" or generation != self.generation:
            return False
        if len(payload) != DRAWING_BYTES:
            raise ValueError("A drawing must contain 1920 UART bytes")
        self.payload = payload
        self.sent = 0
        self.state = "SENDING"
        return True

    def next_drawing(self, generation):
        if self.state == "DONE" and generation == self.generation:
            self.payload = b""
            self.sent = 0
            self.shapes = ()
            self.generation += 1
            self.state = "DRAW"

    def outgoing(self, limit=16):
        if self.state != "SENDING":
            return b""
        count = min(limit, self.credits, len(self.payload) - self.sent)
        return self.payload[self.sent:self.sent + count]

    def transmitted(self, count):
        if not 0 <= count <= min(self.credits, len(self.payload) - self.sent):
            raise ValueError("Invalid serial write count")
        self.credits -= count
        self.sent += count
        if self.state == "SENDING" and self.sent == len(self.payload):
            self.state = "WAIT"
