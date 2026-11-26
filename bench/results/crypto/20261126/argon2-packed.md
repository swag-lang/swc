# Argon2id packed BlaMka permutation

November 26, 2026, on the AMD EPYC 9V74 Linux x86-64 host used for the
[scalar campaign](argon2.md). The standard-library baseline was `bfc8c126b5`,
which includes the scalar improvements. Both compiled programs used Release.
The baseline compiler was built at `d9bfeae85f`. The candidate added masked
vector multiplication lowering to that compiler.

The [runner](../../../workloads/argon2/README.md#native-comparison-with-libargon2-and-openssl)
shuffled the implementations in each of eleven paired rounds per profile.
The references were libargon2 20190702 (`62358ba212`) built with GCC 14.2
and `OPTTARGET=znver4` (AVX-512), and OpenSSL 3.5.7. Each call used four lanes,
three passes, and version 0x13, and every 32-byte tag matched. CPU 0 ran the
one-worker profiles. CPUs 0–3 ran the four-worker profiles. The ratios are
medians of paired process CPU times with exact 95% intervals.

| MiB | Workers | Scalar CPU ms | Packed CPU ms | libargon2 CPU ms | OpenSSL CPU ms | Packed / scalar | Packed / libargon2 | Packed / OpenSSL |
| ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| 1 | 1 | 2.148 | 1.511 | 0.943 | 1.743 | 0.707 [0.643, 0.789] | 1.577 [1.448, 1.865] | 0.832 [0.706, 1.070] |
| 64 | 1 | 215.287 | 152.579 | 114.321 | 164.611 | 0.753 [0.656, 0.774] | 1.273 [1.223, 1.623] | 0.889 [0.803, 1.066] |
| 256 | 1 | 934.898 | 759.037 | 488.142 | 705.024 | 0.791 [0.715, 0.833] | 1.430 [1.341, 1.648] | 1.077 [1.007, 1.180] |
| 1 | 4 | 3.004 | 2.827 | 1.929 | 2.684 | 0.845 [0.624, 0.996] | 1.408 [0.987, 2.754] | 1.030 [0.495, 1.667] |
| 64 | 4 | 199.472 | 153.246 | 54.702 | 76.620 | 0.739 [0.643, 0.786] | 2.682 [2.212, 3.860] | 1.923 [1.505, 2.407] |
| 256 | 4 | 933.177 | 796.211 | 461.415 | 635.882 | 0.847 [0.739, 0.936] | 1.694 [1.470, 1.915] | 1.249 [1.020, 1.431] |

Process CPU time fell 15–29% from the scalar baseline. Wall time also
improved at 256 MiB with one worker and 64 MiB with four workers. The
other wall-time intervals included parity under concurrent VM work.
libargon2 used less CPU at both larger sizes.

The permutation keeps two independent G lanes per packed vector and realigns
the lanes for the diagonal step. Compile-time strides preserve direct accesses
for both halves of a block. The compiler uses unsigned widening multiply when
both packed operands have zero upper halves. On the same packed permutation
before stride specialization, this replaced 48 partial products with 16
`vpmuludq` products, reducing final Micro instructions from 319 to 203.

The native Release `argon2.swg` selection passed all six cases, and
`native/simd/operators.swg` passed all 15 cases. The twelve Release benchmark
tasks matched checksums and normalized final Micro, including two generated
helper renames. Six paired rebuilds of the same packed workload showed
no detectable compiler CPU or peak RSS change. The candidate/baseline
ratios were 0.965 [0.929, 1.041] for CPU and 0.992 [0.789, 1.033] for
maximum RSS. [Raw timing, tags, and compiler samples](argon2-packed.json)

A follow-up restricted the masked-product matcher to built-in operators. All 16 native
SIMD cases passed, including explicit conversion of an overloaded AND result. The 12
standard benchmark checksums and normalized Micro listings matched, as did the Argon2
compression listing.
