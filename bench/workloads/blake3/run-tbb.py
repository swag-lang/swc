"""Measure BLAKE3 one-shot scaling against the official C and oneTBB APIs."""

from pathlib import Path
import sys

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "crypto"))
from run import main

REFERENCES = {"blake3": {
    "BLAKE3 C": "blake3",
    "BLAKE3 C TBB 2": "blake3-tbb2",
    "BLAKE3 C TBB 4": "blake3-tbb4",
}}

if __name__ == "__main__":
    main(references=REFERENCES, default_algorithms=tuple(REFERENCES))
