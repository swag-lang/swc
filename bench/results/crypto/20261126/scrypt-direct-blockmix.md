# scrypt direct BlockMix output

Each Salsa20/8 call writes its result straight into the target chunk.
The next call reads the previous result from that chunk. The source and
target blocks are separate throughout ROMix's alternating-buffer loop.
The target is in either the ROMix allocation or the temporary lane buffer,
each of which its owner securely clears.

Both Swag builds used native Release with `d81f3cd6b5` as the standard
library baseline. Seventeen shuffled paired rounds ran on CPU 2 of an
AMD EPYC 9V74 under Linux 6.18.57. Each derivation used one lane, one
worker and a 32-byte result. The native OpenSSL executables used the same
probe source and linked OpenSSL 3.5.7 or static OpenSSL 4.1.0. The
libsodium reference uses version 1.0.18.

The table shows median process CPU milliseconds and paired 95% time-ratio
intervals. The matrix prototype additionally fills the first-pass ROMix
matrix directly.

| N | r | Before | Direct | Matrix prototype | OpenSSL 3.5.7 | OpenSSL 4.1.0 | libsodium | Direct / before |
| ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| 1024 | 1 | 0.207 | 0.195 | 0.195 | 0.302 | 0.262 | 0.183 | 0.947 [0.901, 0.966] |
| 16384 | 8 | 24.654 | 24.150 | 23.869 | 40.216 | 34.037 | 25.283 | 0.983 [0.961, 1.001] |
| 65536 | 8 | 110.071 | 107.410 | 108.128 | 178.790 | 150.810 | 122.394 | 0.963 [0.945, 1.011] |

At 128 KiB, direct output used 5.3% less CPU than the Swag baseline. A
separate run of 31 pairs confirmed 5.8% less CPU [0.907, 0.970] and 5.3%
less elapsed time [0.914, 0.961]. CPU intervals against libsodium
included parity in both runs. Swag took 6.6% longer than libsodium in
the repeat's elapsed measurements. The 16 and 64 MiB Swag-to-Swag
intervals spanned parity. Direct output used 27–30% less CPU than
OpenSSL 4.1.0 across these profiles. The matrix prototype gave a further
1.2% reduction at 16 MiB and its 128 KiB comparison against the baseline
spanned parity. The direct output change was selected.

Every measured key matched the external references. A further 42
profiles crossed six powers of two from `N=2` through `N=256` with
seven values of `r` from 1 through 15. Each matched OpenSSL and libsodium.
Twelve focused Core cases passed in each of native Release and
Release-safe, including the 16-lane RFC 7914 vector.

[Reproduction](../../../workloads/kdf-replay/README.md#standalone-openssl-versions) · [Raw times and derived keys](scrypt-direct-blockmix.json)
