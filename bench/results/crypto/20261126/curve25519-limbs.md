# Five-limb Curve25519 field arithmetic

X25519 and Ed25519 share a five-limb radix-2^51 field representation, wide
multiplication, and fixed carry and canonicalization schedules. The Release
selection passed 48 Curve, Math, parse and format tests. The nine focused native
Release-safe Curve tests also passed. An additional 24 outputs matched OpenSSL,
including shared secrets and Ed25519 signatures and verification.

The common paired comparison used the preceding inversion-chain campaign as the
baseline on a pinned AMD EPYC 9V74 CPU. Rates are operations per second.

| Operation | Before | After | OpenSSL 3.5.7 |
| --- | ---: | ---: | ---: |
| X25519 public key | 806 | 3410 | 27800 |
| X25519 shared secret | 807 | 3410 | 14400 |
| Ed25519 public key | 429 | 1840 | 27200 |
| Ed25519 sign, 64 B | 212 | 886 | 13500 |
| Ed25519 sign, 4096 B | 207 | 836 | 11500 |

An independent 20-sample process CPU run moved Ed25519 verification from 10,483
to 2,423 microseconds per operation.

[Raw paired comparison and output fingerprints](curve25519-limbs.json).
