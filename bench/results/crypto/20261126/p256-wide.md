# Four-word P-256 Montgomery products

The Montgomery kernel now works with four 64-bit words and retains carry from
both top-word additions. The five focused P-256 tests passed in native Release
and Release-safe, covering public keys, ECDH and deterministic ECDSA. OpenSSL
matched 128 additional public keys over order, word and alignment boundaries.
The comparison uses two Swag builds from the same interleaved experiment.

In 17 paired process CPU-time trials on CPU 4 of the AMD EPYC
9V74, P-256 public-key generation rose from 2,819 to 3,166
operations/second. The paired speedup was 1.13x
(95% CI 1.07–1.14x). OpenSSL 3.5.7 ran at
91,759 operations/second. Every timed public key matched.

[Raw trials and matching output fingerprints](p256-wide.json).
