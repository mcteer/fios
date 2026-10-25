"""Fixed worker entry point: inherited private pipes, never a network listener."""
import asyncio
import sys

from .worker import main

if __name__ == "__main__":
    try:
        sys.exit(asyncio.run(main()))
    except KeyboardInterrupt:
        sys.exit(130)
