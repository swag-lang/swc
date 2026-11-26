# scrypt Salsa20/8 input fusion

BlockMix feeds each source chunk directly into the packed Salsa20/8
function. The function XORs the source into the running state in registers
and uses the same input words for Salsa's final feed-forward. The block
order, ROMix lookup, and secure clearing remain part of the measured call.

Both Swag builds used native Release, with `51fc17f2fe` as the standard
library baseline. Seventeen paired samples per profile ran on CPU 2 of an
AMD EPYC 9V74 under Linux 6.18.57. Each profile used one lane and one
worker. Every derivation returned the same 32-byte key as Python's
OpenSSL 3.5.8. The table shows median process CPU milliseconds and paired
95% time-ratio intervals.

| N | r | ROMix memory | Before | Fused | OpenSSL | Fused / before | Fused / OpenSSL |
| ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| 1024 | 1 | 128 KiB | 0.223 | 0.203 | 0.263 | 0.919 [0.828, 1.005] | 0.730 [0.699, 0.782] |
| 16384 | 8 | 16 MiB | 28.604 | 25.711 | 33.962 | 0.931 [0.895, 0.985] | 0.771 [0.738, 0.785] |
| 65536 | 8 | 64 MiB | 116.984 | 109.031 | 158.143 | 0.935 [0.924, 0.945] | 0.688 [0.674, 0.700] |

The 16 and 64 MiB profiles used 6.5–6.9% less CPU than the previous
Swag build and 23–31% less than OpenSSL. Both elapsed-time intervals
also excluded parity against both comparators. The 128 KiB Swag-to-Swag
interval included parity.

Twelve focused Core cases passed in both native Release and Release-safe.
They include the RFC 7914 16-lane stress vector and the smaller scrypt
vectors, including overlapping input and output.

[Reproduction](../../../workloads/scrypt/README.md) · [Raw timings and derived keys](scrypt-salsa-fusion.json)
