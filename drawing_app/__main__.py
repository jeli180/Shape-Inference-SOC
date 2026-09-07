import argparse


def main():
    parser = argparse.ArgumentParser(description="Draw four shapes for the FPGA CPU")
    parser.add_argument("--port", default="", help="Serial port, e.g. COM3 or /dev/cu.usbserial-...")
    parser.add_argument("--baud", type=int, default=115200)
    parser.add_argument("--demo", action="store_true", help="Use a simulated CPU with fixed results")
    args = parser.parse_args()
    try:
        from .app import run
    except ImportError as exc:
        if exc.name in ("tkinter", "_tkinter"):
            parser.exit(1, "Tk support is missing from this Python. Use a Python with Tk installed.\n"
                        "See drawing_app/README.md for setup instructions.\n")
        raise
    run(args)


if __name__ == "__main__":
    main()
