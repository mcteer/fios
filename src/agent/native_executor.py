"""Bind an MLX process group to its native worker's lifetime."""

import os
import runpy
import signal
import sys
from threading import Event, Thread


def watch_parent(expected):
    def guard():
        sleeper = Event()
        while os.getppid() == expected:
            sleeper.wait(0.1)
        # The executor owns a dedicated process group and a private lock.
        os.killpg(os.getpgrp(), signal.SIGKILL)

    Thread(target=guard, daemon=True).start()


def main():
    expected = int(sys.argv.pop(1))
    entry = sys.argv.pop(1)
    if entry not in ("mlx_lm.server", "mlx_vlm.server"):
        raise ValueError("Unsupported MLX entry point")
    if os.getpgrp() != os.getpid():
        raise ValueError("The executor requires its own process group")
    if os.getppid() != expected:
        return
    watch_parent(expected)
    if entry == "mlx_vlm.server":
        from mlx_vlm.server.cli import main as serve
        serve()
    else:
        runpy.run_module(entry, run_name="__main__")


if __name__ == "__main__":
    main()
