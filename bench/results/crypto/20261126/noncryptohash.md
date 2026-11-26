# CityHash32 short inputs and MurmurHash64A pointer walking

CityHash32 inlines the short-input methods. MurmurHash64A advances a byte pointer
through unaligned words without recomputing offsets. Forty-six native Release Core
tests passed. The upstream comparison checked 322 exact outputs across both hashes.
Swag preserved its existing unsigned-byte behavior on very short CityHash32 input.

CPU 2 of the AMD EPYC 9V74 ran 21 paired process CPU-time trials. The CityHash32
baseline includes the earlier direct loads and scalar state rotation. Rates are GB/s.

| Algorithm | Bytes | Before | After | Upstream | Speedup (95% CI) |
| --- | ---: | ---: | ---: | ---: | ---: |
| cityhash32 | 5 | 0.486 | 0.584 | 1.08 | 1.2 [1.17, 1.22] |
| cityhash32 | 24 | 1.74 | 2.54 | 3.31 | 1.46 [1.44, 1.48] |
| cityhash32 | 64 | 3.08 | 3.08 | 3.46 | 1.01 [0.983, 1.01] |
| cityhash32 | 4096 | 5.87 | 5.89 | 5.61 | 1 [0.98, 1.02] |
| cityhash32 | 65536 | 5.99 | 5.97 | 5.69 | 1 [0.989, 1.01] |
| cityhash32 | 1048576 | 5.93 | 5.92 | 5.63 | 1 [0.992, 1.01] |
| murmur64a | 5 | 1.37 | 1.37 | 1.62 | 1 [0.994, 1.01] |
| murmur64a | 24 | 4.5 | 4.6 | 4.99 | 1.02 [1.01, 1.03] |
| murmur64a | 64 | 5.91 | 6.76 | 6.74 | 1.14 [1.13, 1.15] |
| murmur64a | 4096 | 6.63 | 6.99 | 7.17 | 1.05 [1.04, 1.06] |
| murmur64a | 65536 | 6.69 | 7.07 | 7.13 | 1.06 [1.05, 1.07] |
| murmur64a | 1048576 | 6.72 | 7 | 7.15 | 1.04 [1.03, 1.05] |

[Raw trials](noncryptohash.json) · [Runnable comparison](../../../workloads/noncryptohash/README.md).
