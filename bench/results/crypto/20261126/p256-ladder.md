# P-256 ladder arithmetic

The scalar ladder reuses the point doubling needed by addition, combines adjacent
masked swaps, and computes one field inverse for both exported coordinates.
All five focused native Release tests passed, including RFC 6979 signatures, ECDH,
invalid points and edge scalars. A separate comparison matched OpenSSL on 64
private scalars, including values near the group order and input offsets 0–15.

In 15 paired process CPU-time trials on CPU 4 of the AMD EPYC 9V74, public-key
derivation rose from 653 to 1,050 operations/second. The paired speedup was
1.60x (95% CI 1.57–1.62x). OpenSSL 3.5.7 reached 90,700 operations/second with
its fixed-base EC routine.

[Raw trials and public-key fingerprints](p256-ladder.json).
