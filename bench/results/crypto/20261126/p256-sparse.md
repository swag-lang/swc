# Sparse P-256 prime reduction

The field path specializes Montgomery reduction for the words of the P-256
prime. The reduction factor cancels the low word and the other products reduce
to shifts and additions. Order arithmetic keeps its generic multiplication.
An independent integer model checked 8,196 full-word reduction cases.

Six native P-256 cases passed in Release and Release-safe. OpenSSL 3.5.7 matched
the public keys and signatures for all timed calls, plus 19 empty, short and
unaligned inputs. The common workload used 17 process CPU-time rounds on AMD EPYC
9V74 CPU 4. Rates are operations per second.

| Operation | Before | Sparse reduction | OpenSSL | Paired speedup (95% CI) |
| --- | ---: | ---: | ---: | ---: |
| Public key | 3920 | 5220 | 89900 | 1.34 [1.31, 1.38] |
| Sign, 64 B | 3410 | 4430 | 31800 | 1.27 [1.25, 1.34] |
| Sign, 4096 B | 3310 | 4210 | 30400 | 1.28 [1.26, 1.31] |

[Raw trials and output fingerprints](p256-sparse.json).
