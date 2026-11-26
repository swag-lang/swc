# Complete mixed addition for P-256 generator multiplication

The fixed-base comb now accumulates in homogeneous projective coordinates.
The unified mixed addition handles equal and opposite points in one
formula. The zero digit uses a finite table point for the calculation
and masks off the result. The code converts the accumulator back to
Jacobian coordinates when the comb finishes.

Seventeen paired native Release process CPU-time rounds on AMD EPYC
9V74 CPU 4 compared the two four-table implementations. Full keys and
deterministic signatures matched OpenSSL 3.5.7 for all timed trials and
365 additional cases. The six focused Core cases passed both native
Release configurations.

| Algorithm | Bytes | Offset | Swag build | Comparator | Unit | Swag rate | Comparator rate | Paired speed ratio (95% CI) |
| --- | ---: | ---: | --- | --- | --- | ---: | ---: | ---: |
| p256-public | 32 | 0 | homogeneous | jacobian | ops/s | 9.46e+03 | 8.15e+03 | 1.16 [1.15, 1.18] |
| p256-sign | 64 | 0 | homogeneous | jacobian | ops/s | 7.76e+03 | 6.75e+03 | 1.15 [1.13, 1.18] |
| p256-sign | 4096 | 0 | homogeneous | jacobian | ops/s | 7.59e+03 | 6.77e+03 | 1.13 [1.11, 1.14] |

The mixed addition and doubling follow the formulas for curves with
coefficient −3. [Renes, Costello and Batina](https://eprint.iacr.org/2015/1060) · [Explicit-Formulas Database](https://www.hyperelliptic.org/EFD/g1p/auto-shortw-projective-3.html).

[Raw paired trials](p256-complete-addition.json) · [External verification](p256-complete-addition-verification.json).
