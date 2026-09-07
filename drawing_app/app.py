"""Tk interface; the binary drawing buffer is the source of displayed ink."""

import queue
import tkinter as tk
from tkinter import ttk

from .protocol import Drawing, SIZE, Snapshot, encode_pixels
from .transport import SerialWorker


class App:
    def __init__(self, root, args):
        self.root = root
        self.args = args
        self.worker = None
        self.events = queue.Queue()
        self.drawing = Drawing()
        self.snapshot = Snapshot("INIT", 0, 0, -1, ())
        self.last_point = None
        self.stroke_quadrant = None
        self.action_pending = False
        self.connected = False
        root.title("Shape drawing · UART")
        root.resizable(False, False)
        frame = ttk.Frame(root, padding=16)
        frame.pack()

        connection = ttk.Frame(frame)
        connection.pack(fill="x", pady=(0, 14))
        ttk.Label(connection, text="Port").pack(side="left")
        self.port = ttk.Combobox(connection, width=27)
        self.port.pack(side="left", padx=6)
        self.refresh_ports()
        if args.port:
            self.port.set(args.port)
        self.refresh = ttk.Button(connection, text="Refresh", command=self.refresh_ports)
        self.refresh.pack(side="left")
        self.connect_button = ttk.Button(connection, text="Connect", command=self.toggle_connection)
        self.connect_button.pack(side="right")

        header = ttk.Frame(frame)
        header.pack(fill="x", pady=(0, 10))
        self.status = ttk.Label(header, text="INIT", font=("Helvetica", 20, "bold"))
        self.status.pack(side="left")
        self.action = ttk.Button(header, text="Submit", command=self.action_clicked, state="disabled")
        self.action.pack(side="right")
        # A four-pixel gutter keeps dividers separate from the 240x240 quadrants.
        self.canvas = tk.Canvas(frame, width=484, height=484, background="#b5bcc7",
                                highlightthickness=0)
        self.canvas.pack()
        self.photos = [tk.PhotoImage(width=240, height=240) for _ in range(4)]
        for q, photo in enumerate(self.photos):
            self.canvas.create_image((q % 2) * 244, (q // 2) * 244,
                                     image=photo, anchor="nw")
        self.canvas.bind("<ButtonPress-1>", self.press)
        self.canvas.bind("<B1-Motion>", self.motion)
        self.canvas.bind("<ButtonRelease-1>", self.release)
        self.info = ttk.Label(frame, text="Connect, then reset the hardware.", wraplength=484)
        self.info.pack(fill="x", pady=(10, 4))
        self.progress = ttk.Progressbar(frame, maximum=1920)
        self.progress.pack(fill="x")
        self.counter = ttk.Label(frame, text="Credits: 0   ·   Sent: 0 / 1920 bytes")
        self.counter.pack(anchor="w", pady=(4, 0))
        if args.demo:
            ttk.Label(frame, text="DEMO · Fixed example classes; no hardware inference.").pack(anchor="w")
        self.render_ink()
        root.protocol("WM_DELETE_WINDOW", self.close)
        root.after(20, self.poll)
        if args.demo or args.port:
            self.toggle_connection()

    def refresh_ports(self):
        try:
            from serial.tools import list_ports
            ports = [entry.device for entry in list_ports.comports()]
        except ImportError:
            ports = []
        self.port["values"] = ports
        if ports and not self.port.get():
            self.port.set(ports[0])

    def toggle_connection(self):
        if self.worker:
            self.worker.stop_event.set()
            self.connect_button.configure(state="disabled")
            self.connected = False
            self.action.configure(state="disabled")
            return
        if not self.args.demo and not self.port.get().strip():
            self.info.configure(text="Select or enter a serial port first.")
            return
        self.events = queue.Queue()
        self.snapshot = Snapshot("INIT", 0, 0, -1, ())
        self.action_pending = False
        self.drawing.clear()
        self.render_ink()
        self.update_status()
        self.worker = SerialWorker(self.events, self.port.get().strip(), self.args.baud, self.args.demo)
        self.port.configure(state="disabled")
        self.refresh.configure(state="disabled")
        self.connect_button.configure(text="Connecting…", state="disabled")
        self.info.configure(text="Opening connection…")
        self.worker.start()

    def action_clicked(self):
        if not self.connected or self.action_pending:
            return
        state = self.snapshot.state
        if state == "DRAW":
            self.action_pending = True
            self.release()
            self.status.configure(text="Wait")
            self.action.configure(state="disabled")
            self.worker.commands.put(("submit", self.snapshot.generation,
                                      encode_pixels(self.drawing.pixels)))
        elif state == "DONE":
            self.action_pending = True
            self.action.configure(state="disabled")
            self.worker.commands.put(("next", self.snapshot.generation, None))

    def logical_point(self, event):
        x, y = event.x, event.y
        if not (0 <= x < 484 and 0 <= y < 484) or 240 <= x < 244 or 240 <= y < 244:
            return None
        return x - (4 if x >= 244 else 0), y - (4 if y >= 244 else 0)

    def press(self, event):
        if self.snapshot.state != "DRAW" or not self.connected or self.action_pending:
            return
        point = self.logical_point(event)
        if point:
            self.stroke_quadrant = (point[0] // 240, point[1] // 240)
            self.last_point = point
            self.drawing.stroke(point, point)
            self.render_ink(self.stroke_quadrant)

    def motion(self, event):
        if self.stroke_quadrant is None:
            return
        if self.snapshot.state != "DRAW" or self.action_pending or not self.connected:
            self.release()
            return
        point = self.logical_point(event)
        if point is None or (point[0] // 240, point[1] // 240) != self.stroke_quadrant:
            self.last_point = None
            return
        self.drawing.stroke(self.last_point or point, point)
        self.last_point = point
        self.render_ink(self.stroke_quadrant)

    def release(self, event=None):
        self.last_point = None
        self.stroke_quadrant = None

    def render_ink(self, quadrant=None):
        self.canvas.delete("result")
        for q, photo in enumerate(self.photos):
            col, row = q % 2, q // 2
            if quadrant is not None and quadrant != (col, row):
                continue
            ox, oy = col * 240, row * 240
            rows = []
            for y in range(oy, oy + 240):
                pixels = self.drawing.pixels[y * SIZE + ox:y * SIZE + ox + 240]
                rows.append("{" + " ".join("#172033" if bit else "white" for bit in pixels) + "}")
            photo.put(" ".join(rows))

    def render_shapes(self):
        for photo in self.photos:
            photo.put("white", to=(0, 0, 240, 240))
        self.canvas.delete("result")
        for q, shape in enumerate(self.snapshot.shapes):
            ox, oy = (q % 2) * 244, (q // 2) * 244
            box = (ox + 40, oy + 40, ox + 200, oy + 200)
            if shape == 1:
                self.canvas.create_line(*box, fill="#172033", width=4, tags="result")
            elif shape == 2:
                self.canvas.create_rectangle(*box, outline="#172033", width=4, tags="result")
            elif shape == 3:
                self.canvas.create_oval(*box, outline="#172033", width=4, tags="result")

    def update_status(self):
        snap = self.snapshot
        self.status.configure(text={"SENDING": "Wait", "WAIT": "Wait", "DONE": "Done"}.get(snap.state, snap.state))
        self.action.configure(text="Next" if snap.state == "DONE" else "Submit",
                              state="normal" if self.connected and snap.state in ("DRAW", "DONE")
                              and not self.action_pending else "disabled")
        self.progress["value"] = snap.sent
        self.counter.configure(text="Credits: {}   ·   Sent: {} / 1920 bytes".format(snap.credits, snap.sent))
        messages = {"INIT": "Waiting for hardware startup. Reset the hardware after connecting.",
                    "DRAW": "Draw one shape in each quadrant, then press Submit.",
                    "SENDING": "Sending drawing…" if snap.credits else "Waiting for more credits…",
                    "WAIT": "Waiting for CPU classifications…",
                    "DONE": "Press Next to clear the shapes and draw again."}
        self.info.configure(text=messages[snap.state])

    def poll(self):
        while True:
            try:
                kind, data = self.events.get_nowait()
            except queue.Empty:
                break
            if kind == "connected":
                self.connected = True
                self.connect_button.configure(text="Disconnect", state="normal")
            elif kind == "snapshot":
                previous = self.snapshot
                self.snapshot = data
                if data.generation != previous.generation:
                    self.release()
                    self.drawing.clear()
                    self.render_ink()
                    self.action_pending = False
                if data.state != previous.state:
                    self.action_pending = False
                    self.release()
                if data.state == "DONE" and (previous.state != "DONE" or data.shapes != previous.shapes):
                    self.render_shapes()
                self.update_status()
            elif kind == "error":
                self.info.configure(text="Connection error: {}. Reconnect and reset the hardware.".format(data))
            elif kind == "closed":
                self.connected = False
                self.worker = None
                self.release()
                self.status.configure(text="INIT")
                self.action.configure(state="disabled")
                self.connect_button.configure(text="Connect", state="normal")
                self.port.configure(state="normal")
                self.refresh.configure(state="normal")
                if not self.info.cget("text").startswith("Connection error:"):
                    self.info.configure(text="Disconnected. Reconnect, then reset the hardware.")
        self.root.after(20, self.poll)

    def close(self):
        if self.worker:
            self.worker.stop_event.set()
            self.worker.join(timeout=1)
        self.root.destroy()


def run(args):
    root = tk.Tk()
    App(root, args)
    root.mainloop()
