"""Compare non-cryptographic Core hashes with their upstream implementations."""

from pathlib import Path
import sys

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "crypto"))
from run import main

REFERENCES = {
    "cityhash32": {"CityHash C++": "cityhash32"},
    "murmur64a": {"SMHasher": "murmur64a"},
}

if __name__ == "__main__":
    main(references=REFERENCES, default_algorithms=tuple(REFERENCES))
