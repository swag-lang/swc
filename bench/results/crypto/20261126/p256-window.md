# P-256 four-bit scalar multiplication

All scalar windows perform four doublings and scan the point multiples in public
index order before the addition. Carry and exceptional-point selection use masked
integer operations. The five focused native Release Core tests passed. The public
key also matched OpenSSL for 64 scalars, including edge values and offsets 0–15.

Fifteen paired process CPU-time trials on CPU 4 of the AMD EPYC 9V74 increased
P-256 public-key generation from 1,070 to 1,560 operations/second. The speedup was
1.47x (95% CI 1.46–1.48x) against the preceding ladder implementation. OpenSSL 3.5.7
reached 92,000 operations/second.

[Raw trials and matching public-key fingerprints](p256-window.json).
