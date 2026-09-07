# UART shape drawing app

Four independent 240x240 drawing quadrants, credit-controlled UART upload, and
CPU classification display. Python 3.9+ with Tk is required. Run commands below
from the repository root.

## Setup and launch

```sh
python3 -m venv drawing_app/.venv
source drawing_app/.venv/bin/activate
python -m pip install -r drawing_app/requirements.txt
python -m drawing_app
```

Select or enter the FPGA serial port and press Connect, **then reset the
hardware**. The app stays in INIT until it receives the reset credit grant and
CPU initialization zero. Draw one shape in each quadrant, press Submit, and
wait for the perfect shapes. Press Next to draw again.

Port and baud can also be passed at launch:

```sh
python -m drawing_app --port /dev/cu.usbserial-DEVICE --baud 115200
```

On Windows, use a port such as `COM3`. RTS/CTS, DSR/DTR flow control and XON/XOFF
are disabled; the application byte-credit protocol controls transmission.
On connection failure, reconnect and reset hardware to start a fresh session.
No automatic retransmission occurs after serial errors because partial writes
can leave byte alignment uncertain.

Check Tk availability with `python3 -m tkinter`. If Homebrew Python reports
`No module named '_tkinter'`, install its matching Tk package (for example,
`brew install python-tk@3.14` for Python 3.14) before creating the virtual
environment, or use another Python installation with Tk. Tk is not installed
by pip. Some system Python installations have old Tk versions; a current Tk
installation is preferable for the GUI.

## Demo and verification

```sh
python -m drawing_app --demo
python -m unittest discover -s drawing_app -p 'test_*.py' -v
```

The demo requires Tk but not pyserial or hardware. It exercises credits and the
full repeated drawing flow, returning fixed example classes: line, square,
circle, line for Q1 through Q4. It does not run shape inference. The tests need
neither Tk nor pyserial.

The canvas displays the binary ink buffer itself, with a five-pixel round brush
and interpolated strokes. A stroke stays in the quadrant where it began;
release the mouse to start in another quadrant. A separate four-pixel divider
gutter and the status/button toolbar never enter the compressed image.
Class 00 displays an empty quadrant.

See [flow.md](flow.md) for exact byte packing, state transitions, and the agreed
reset limitations. The app does not modify CPU assembly or RTL.

## Files

- `app.py`: Tk interface and drawing interaction.
- `protocol.py`: binary raster, compression, receive parser, and session state.
- `transport.py`: serial worker and simulated CPU; no Tk calls from the worker.
- `test_protocol.py`: pixel layout, control-byte parsing, credit/reset handling,
  and two complete simulated drawing rounds.
