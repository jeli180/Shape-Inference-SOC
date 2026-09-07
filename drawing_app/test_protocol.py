import queue
import time
import unittest

from drawing_app.protocol import DRAWING_BYTES, Drawing, Session, encode_pixels
from drawing_app.transport import SerialWorker


class PixelTests(unittest.TestCase):
    def test_blank_and_full_flags(self):
        for fill, ordinary, last in ((0, 0x40000000, 0xC0000000),
                                     (1, 0x7FFFFFFF, 0xFFFFFFFF)):
            encoded = encode_pixels(bytes([fill]) * (480 * 480))
            self.assertEqual(len(encoded), 1920)
            self.assertEqual(encoded[:-4], ordinary.to_bytes(4, "little") * 479)
            self.assertEqual(encoded[-4:], last.to_bytes(4, "little"))

    def test_pooling_bit_order_quadrants_and_row_boundary(self):
        drawing = Drawing()
        for x, y in [(3, 3), (4, 0), (120, 0), (0, 4),
                     (240, 0), (0, 240), (240, 240), (479, 479)]:
            drawing.pixels[y * 480 + x] = 1
        encoded = encode_pixels(drawing.pixels)
        expected = [0x40000000] * 480
        expected[0] |= 3
        expected[1] |= 1
        expected[2] |= 1
        for word in (120, 240, 360):
            expected[word] |= 1
        expected[479] |= (1 << 29) | (1 << 31)
        self.assertEqual(encoded, b"".join(word.to_bytes(4, "little") for word in expected))

    def test_stroke_continuity_and_clipping(self):
        drawing = Drawing()
        drawing.stroke((200, 100), (260, 100), width=5)
        self.assertTrue(all(drawing.pixels[100 * 480 + x] for x in range(200, 240)))
        self.assertFalse(any(drawing.pixels[100 * 480 + 240:100 * 480 + 270]))
        drawing.clear()
        self.assertFalse(any(drawing.pixels))


class SessionTests(unittest.TestCase):
    def ready(self):
        session = Session()
        session.receive(b"\x5f\x00")
        return session

    def test_init_requires_reset_and_zero(self):
        session = Session()
        session.receive(b"\x00")
        self.assertEqual(session.state, "INIT")
        session.receive(b"\x5f")
        self.assertEqual((session.state, session.credits), ("INIT", 31))
        session.receive(b"\x00")
        self.assertEqual(session.state, "DRAW")

    def test_zero_credit_stall_partial_word_and_partial_write(self):
        session = self.ready()
        session.submit(bytes(DRAWING_BYTES), session.generation)
        session.transmitted(len(session.outgoing()))
        session.transmitted(len(session.outgoing()))
        self.assertEqual((session.credits, session.sent), (0, 31))
        self.assertEqual(session.outgoing(), b"")
        session.receive(b"\x48")
        self.assertEqual(len(session.outgoing()), 8)
        session.transmitted(3)
        self.assertEqual((session.credits, session.sent), (5, 34))

    def test_reset_aborts_upload_and_rejects_stale_submit(self):
        session = self.ready()
        old_generation = session.generation
        session.submit(bytes(DRAWING_BYTES), old_generation)
        session.transmitted(16)
        session.receive(b"\x5f\x00")
        self.assertEqual((session.credits, session.sent, session.state), (31, 0, "DRAW"))
        self.assertEqual(session.outgoing(), b"")
        self.assertFalse(session.submit(bytes(DRAWING_BYTES), old_generation))
        self.assertEqual(session.payload, b"")

    def test_ack_zeros_do_not_restart_upload(self):
        session = self.ready()
        session.submit(bytes(DRAWING_BYTES), session.generation)
        session.receive(b"\x00\x48\x00")
        self.assertEqual((session.state, session.credits), ("SENDING", 39))

    def wait_session(self):
        session = self.ready()
        session.submit(bytes(DRAWING_BYTES), session.generation)
        while session.state == "SENDING":
            data = session.outgoing()
            if data:
                session.transmitted(len(data))
            else:
                session.receive(b"\x48")
        return session

    def test_every_shape_byte_including_control_values(self):
        for payload in range(256):
            session = self.wait_session()
            credits, generation = session.credits, session.generation
            session.receive(b"\x80")
            session.receive(bytes([payload]))
            self.assertEqual(session.state, "DONE")
            self.assertEqual(session.shapes, tuple((payload >> (2 * q)) & 3 for q in range(4)))
            self.assertEqual((session.credits, session.generation), (credits, generation))

    def test_next_preserves_credits_and_sends_nothing(self):
        session = self.wait_session()
        session.receive(b"\x80\x79")
        self.assertEqual(session.shapes, (1, 2, 3, 1))
        credits = session.credits
        session.next_drawing(session.generation)
        self.assertEqual((session.state, session.credits), ("DRAW", credits))
        self.assertEqual(session.outgoing(), b"")

    def test_reset_from_done_clears_classes(self):
        session = self.wait_session()
        session.receive(b"\x80\xff\x5f")
        self.assertEqual((session.state, session.shapes, session.credits), ("INIT", (), 31))

    def test_unexpected_shape_header_still_consumes_payload(self):
        session = self.ready()
        session.receive(b"\x80\x5f")
        self.assertEqual((session.state, session.generation), ("DRAW", 1))


class WorkerTests(unittest.TestCase):
    def test_two_demo_rounds(self):
        events = queue.Queue()
        worker = SerialWorker(events, "", demo=True)
        worker.start()

        def await_state(state):
            deadline = time.monotonic() + 5
            while time.monotonic() < deadline:
                kind, value = events.get(timeout=5)
                self.assertNotEqual(kind, "error", value)
                if kind == "snapshot" and value.state == state:
                    return value
            self.fail("Timed out waiting for " + state)

        try:
            draw = await_state("DRAW")
            for _ in range(2):
                worker.commands.put(("submit", draw.generation, encode_pixels(bytes(480 * 480))))
                done = await_state("DONE")
                self.assertEqual(done.sent, 1920)
                self.assertEqual(done.shapes, (1, 2, 3, 1))
                self.assertEqual(done.credits, 31)
                worker.commands.put(("next", done.generation, None))
                draw = await_state("DRAW")
                self.assertEqual(draw.credits, 31)
        finally:
            worker.stop_event.set()
            worker.join(timeout=2)
        self.assertFalse(worker.is_alive())


if __name__ == "__main__":
    unittest.main()
