"""Compare Swag, OpenSSL and libsodium on equal-length byte sequences."""

from pathlib import Path
import sys

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "crypto"))
from run import main

CASES = ("equal", "first", "last")
REFERENCES = {
    f"ct-{case}": {"OpenSSL": f"openssl-{case}", "libsodium": f"sodium-{case}"}
    for case in CASES
}

if __name__ == "__main__":
    main(references=REFERENCES, default_algorithms=tuple(REFERENCES))
