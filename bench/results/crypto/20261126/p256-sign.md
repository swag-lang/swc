# P-256 deterministic signing and digest reduction

RFC 6979 reduces the SHA-256 digest modulo the P-256 group order before it seeds
HMAC. The fixed-size seed buffer replaces the heap-backed concatenation. Six
native Release P-256 tests passed. The new test checks digests equal to and just
above the order and fails if the reduction is removed.

OpenSSL 3.5.7 produced identical deterministic signatures in every timing round
and ten additional aligned and unaligned cases, including empty input.
Fifteen paired process CPU-time trials on AMD EPYC 9V74 CPU 4 measured about
3,000 complete Swag operations/second for 64 bytes against 32,900 for OpenSSL.
The before/after confidence intervals included parity at 64 bytes and 4 KiB.

[Raw trials and signature fingerprints](p256-sign.json).
