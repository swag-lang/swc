# Ed25519 fixed-base comb

Compile-time generator multiples reduce the number of doublings from 256 to 64.
The selection scans every entry and wipes each selected point. Micro review
confirmed masked selection and a branch on the public table index.

Four native Ed25519 tests passed in both Release and Release-safe. Twenty-four
additional cases matched OpenSSL. Twenty paired process CPU-time samples ran
on CPU 3 of the AMD EPYC 9V74.

| Operation | Before (µs) | After (µs) | Paired speedup (95% CI) |
| --- | ---: | ---: | ---: |
| Public key | 362.9 | 158.2 | 2.29 [2.22, 2.37] |
| Sign | 759.8 | 360.7 | 2.10 [2.02, 2.15] |
| Verify | 1569.6 | 1327.8 | 1.16 [1.13, 1.20] |

[Raw trials](ed25519-comb.json).
