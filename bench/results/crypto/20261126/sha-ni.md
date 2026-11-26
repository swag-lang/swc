# SHA-NI block compression

SHA-1 and SHA-224/256 select native round and schedule instructions after the
runtime feature check. All 21 selected native Release Core tests passed on the
host and with SHA instructions masked under QEMU. Eight JIT and five Release-safe
SHA cases also passed. Every digest in the timed workload matched Python hashlib.

Each row below processes 8 MiB using 1 MiB messages. Fifteen pinned thread
CPU-time samples per implementation ran on CPU 3 of the AMD EPYC 9V74.

| Algorithm | Before (µs) | SHA-NI (µs) | OpenSSL 3.5.7 (µs) | Speedup (95% CI) |
| --- | ---: | ---: | ---: | ---: |
| sha1 | 27489 | 4425 | 4491 | 6.21 [6.11, 6.32] |
| sha224 | 31007 | 4723 | 4759 | 6.57 [6.51, 6.62] |
| sha256 | 30769 | 4759 | 4692 | 6.47 [6.32, 6.62] |

[Raw samples for six message sizes and output digests](sha-ni.json).
