"""Measure one-shot and streaming BLAKE3 with the shared paired runner."""

from pathlib import Path
import sys

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "crypto"))
from run import main

REFERENCES = {name: {"BLAKE3 C": name} for name in
              ("blake3", "blake3-stream-4096", "blake3-stream-65536", "blake3-stream-1048576")}

if __name__ == "__main__":
    main(references=REFERENCES, default_algorithms=tuple(REFERENCES))
