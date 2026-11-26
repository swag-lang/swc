# Signed and fixed windows in modular arithmetic

## RSA private exponentiation

Thirteen paired Release rounds ran on one AMD EPYC 9V74 CPU. Four raw
key widths exercised the masked table scans at four, five and six bits
per step. The same Release compiler and the RSA source at `5f68346f72`
built the three arms. The larger variants share their signed-free word
arithmetic with the four-bit implementation. Every public verification
byte and private OAEP plaintext matched OpenSSL 4.1.0.

At 2048 and 2080 bits the OAEP intervals include parity for both larger
windows. Six bits gives 1.03× [1.01, 1.04] at 3072 bits and 1.05×
[1.02, 1.06] at 4096 bits. The six-bit table uses 32 KiB instead of
8 KiB and adds a cross-byte read to each window.

## P-256 ECDH

An independent integer model reconstructed 10,259 unsigned scalars
from each of four-, five- and six-bit signed Booth recodings, including
all single-bit positions and high end cases. The native variants
scanned every table entry and selected the sign with a mask.

Twenty-one paired Release rounds and OpenSSL 4.1.0 returned the same
32-byte shared secret in every timed repetition. The fixed unsigned
window ran at 3,860 operations/s. Four-bit Booth gave 1.02×
[1.01, 1.03], five-bit Booth 1.03× [0.986, 1.04] and six-bit Booth
0.991× [0.986, 1].

[RSA timings](rsa-private-window-widths.json) · [P-256 timings](p256-booth-widths.json)
