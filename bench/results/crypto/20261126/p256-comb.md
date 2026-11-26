# P-256 fixed-base generator comb

The generator path divides the scalar into four columns and uses a 960-byte table
of Montgomery field coordinates. It doubles once per step and scans the whole
table in index order. General-point multiplication still handles ECDH and the
non-generator term of ECDSA verification.

All five focused native Release P-256 tests passed, including deterministic
signature and public-key vectors. OpenSSL matched an additional 86 public keys over
order boundaries, single bits around word and column boundaries, random scalars
and offsets 0–15.

Fifteen paired process CPU-time trials on CPU 4 of the AMD EPYC 9V74 increased
public-key generation from 1,550 to 2,690 operations/second. The paired speedup
was 1.75x (95% CI 1.70–1.94x). OpenSSL 3.5.7 reached 89,800 operations/second.

[Raw trials and output fingerprints](p256-comb.json).
