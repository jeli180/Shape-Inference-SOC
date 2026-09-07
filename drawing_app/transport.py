"""Serial I/O worker and a small simulated CPU for the demo."""

import queue
import threading

from .protocol import DRAWING_BYTES, Session


class DemoPort:
    """Emulate pixel consumption and credits; classes are fixed, not inferred."""

    def __init__(self):
        self.pending = bytearray(b"\x5f\x00")
        self.received = 0

    @property
    def in_waiting(self):
        return len(self.pending)

    def read(self, count):
        data = bytes(self.pending[:count])
        del self.pending[:count]
        return data

    def write(self, data):
        for _ in data:
            self.received += 1
            if self.received % 4 == 0:
                self.pending.append(0)  # CPU pixel acknowledgment
            if self.received % 8 == 0:
                self.pending.append(0x48)
            if self.received == DRAWING_BYTES:
                self.pending.extend(b"\x80\x79")  # Q1 line, Q2 square, Q3 circle, Q4 line
                self.received = 0
        return len(data)

    def reset_output_buffer(self):
        pass

    def close(self):
        pass


class SerialWorker(threading.Thread):
    def __init__(self, events, port, baud=115200, demo=False):
        super().__init__(daemon=True)
        self.events = events
        self.commands = queue.Queue()
        self.stop_event = threading.Event()
        self.port_name, self.baud, self.demo = port, baud, demo

    def run(self):
        port = None
        try:
            if self.demo:
                port = DemoPort()
            else:
                import serial
                port = serial.Serial(self.port_name, self.baud, timeout=0,
                                     write_timeout=0.5, xonxoff=False,
                                     rtscts=False, dsrdtr=False)
            self.events.put(("connected", "Demo" if self.demo else self.port_name))
            session = Session()
            previous = None
            while not self.stop_event.is_set():
                # Process received reset/credit messages before any further writes.
                incoming = port.read(min(port.in_waiting, 4096))
                if incoming and session.receive(incoming):
                    port.reset_output_buffer()
                while True:
                    try:
                        kind, generation, payload = self.commands.get_nowait()
                    except queue.Empty:
                        break
                    if kind == "submit":
                        session.submit(payload, generation)
                    elif kind == "next":
                        session.next_drawing(generation)
                outgoing = session.outgoing()
                if outgoing:
                    # Charge only bytes accepted by write; no uncredited queued data.
                    written = port.write(outgoing)
                    session.transmitted(written)
                current = session.snapshot()
                if current != previous:
                    self.events.put(("snapshot", current))
                    previous = current
                self.stop_event.wait(0.002)
        except Exception as exc:
            # A write timeout may have sent a partial buffer. Abort the session
            # instead of retrying bytes whose delivery is unknown.
            self.events.put(("error", str(exc)))
        finally:
            if port is not None:
                port.close()
            self.events.put(("closed", None))
