# Ed25519 coordinate square-root chain

Coordinate recovery uses one fixed exponentiation and verifies the root against
the original denominator. This removes the separate inversion. Nine focused
native Curve tests passed in Release and Release-safe, with 24 additional
OpenSSL differential cases.

Twenty paired process CPU-time samples per version ran on AMD EPYC 9V74 CPU 3.
Ed25519 verification moved from 1654.1 to 1535.4 µs, a
1.076x speedup (95% CI 1.062–1.119x).
Key generation and signing ran as controls.

[Raw trials](ed25519-sqrt.json).
