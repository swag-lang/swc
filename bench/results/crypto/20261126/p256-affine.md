# P-256 mixed affine and projective addition

Fixed-base generator additions use the affine table coordinates directly. The
shared completion step still handles equality and infinity through masked selection.
The five focused native Release Core tests passed, including the known-answer
public keys, deterministic signatures and ECDH cases.

In 17 paired process CPU-time trials on CPU 4 of the AMD EPYC
9V74, P-256 public-key generation rose from 3,156 to 3,490
operations/second. The paired speedup was 1.12x
(95% CI 1.06–1.13x). OpenSSL 3.5.7 ran at
90,875 operations/second. Every timed public key matched.

[Raw trials and matching output fingerprints](p256-affine.json).
