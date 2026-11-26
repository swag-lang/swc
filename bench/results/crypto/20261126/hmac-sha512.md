# HMAC-SHA-384/512 key pads and digest serialization

Swag XORs each 16-byte chunk of the normalized key with both pad constants
and serializes two digest words per packed endian conversion. The measured
one-shot call sets up both pads, hashes the message and finalizes the tag.
The OpenSSL comparator reuses an allocated EVP MAC context and supplies the
same 32-byte key for every operation.

Both Swag builds use native Release and the same toolchain. The baseline
standard library is `87c7f68c67`. Fifteen paired samples ran on CPU 2 of
an AMD EPYC 9V74 with a 30 ms target per sample. The table shows median
process CPU nanoseconds per operation and paired 95% time-ratio intervals.

| HMAC | Bytes | Before | Packed | OpenSSL 3.5.7 | Packed / before |
| --- | ---: | ---: | ---: | ---: | ---: |
| SHA-384 | 16 | 1656 | 1501 | 838 | 0.915 [0.895, 0.931] |
| SHA-384 | 64 | 1656 | 1523 | 837 | 0.928 [0.912, 0.944] |
| SHA-384 | 111 | 1656 | 1525 | 833 | 0.910 [0.903, 0.949] |
| SHA-384 | 112 | 1981 | 1902 | 1004 | 0.936 [0.913, 0.983] |
| SHA-384 | 128 | 1948 | 1841 | 982 | 0.937 [0.931, 0.959] |
| SHA-384 | 4096 | 11925 | 11801 | 5591 | 0.991 [0.982, 0.995] |
| SHA-512 | 16 | 1691 | 1501 | 833 | 0.897 [0.869, 0.913] |
| SHA-512 | 64 | 1621 | 1496 | 842 | 0.920 [0.898, 0.973] |
| SHA-512 | 111 | 1653 | 1502 | 829 | 0.906 [0.883, 0.940] |
| SHA-512 | 112 | 1942 | 1848 | 976 | 0.948 [0.924, 0.977] |
| SHA-512 | 128 | 1989 | 1831 | 992 | 0.930 [0.911, 0.942] |
| SHA-512 | 4096 | 12032 | 11779 | 5558 | 0.992 [0.959, 1.006] |

The 16–128-byte profiles used 5–10% less CPU than the Swag baseline.
The 4 KiB differences were about 1%, with the SHA-512 interval spanning
parity. Swag took 1.8–2.1 times OpenSSL's CPU time across these profiles. An
alternative fixed outer block reduced CPU time further by about 2% in
one of twelve pilot profiles at the 95% interval. The packed pads and
serialization changes were selected for this campaign.

Every timed tag matched OpenSSL. Additional verification passed 28 HMAC
fixtures including empty, unaligned and padding-boundary inputs, and eight
existing MAC and encryption fixtures using the same comparator. The
native Release and Release-safe Core selections cover the RFC 4231 HMAC
vectors, the 131-byte key path, incremental hashing and PBKDF2.

[Reproduction](../../../workloads/crypto/README.md) · [Raw samples, validation fingerprints and pilot intervals](hmac-sha512.json)
