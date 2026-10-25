"""Private Fios agent runtime; never imported into browser assets."""
import os

# Protocol stdout and diagnostics must be content-free, including SDK banners.
os.environ["PYDANTIC_AI_NO_BANNER"] = "1"
