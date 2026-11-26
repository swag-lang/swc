# P-256 field inversion addition chain

Affine export now uses a fixed addition chain for p - 2. Consecutive one bits
reuse intermediate powers, cutting multiplication work while keeping a fixed
sequence. All five native Release Core P-256 tests passed. This report selects
two Swag builds from the interleaved experiment with the wide-word candidate.

In 17 paired process CPU-time trials on CPU 4 of the AMD EPYC
9V74, P-256 public-key generation rose from 2,705 to 2,819
operations/second. The paired speedup was 1.05x
(95% CI 1.04–1.06x). OpenSSL 3.5.7 ran at
91,759 operations/second. Every timed public key matched.

[Raw trials and matching output fingerprints](p256-inverse.json).
