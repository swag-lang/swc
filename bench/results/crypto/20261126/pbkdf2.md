# PBKDF2-HMAC prefix reuse

November 26, 2026, on AMD EPYC 9V74 Linux x86-64. The
[comparison](../../../workloads/pbkdf2/README.md) used eleven paired rounds
pinned to CPU 1. Both Swag programs used the Release compiler built at
`d9bfeae85f` and the `release` program configuration. The standard-library
baseline was `cbbd215ed8`. Python 3.12.14 `hashlib.pbkdf2_hmac` used OpenSSL
3.5.8. Every derived byte matched in every round.

Each timed derivation includes its cleanup and follows an untimed warm-up.
Ratios use the paired process CPU times and exact 95% intervals.

| HMAC | Iterations | Password bytes | Salt bytes | Output bytes | Baseline CPU ms | Candidate CPU ms | OpenSSL CPU ms | Candidate / baseline | Candidate / OpenSSL |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| SHA-224 | 20000 | 8 | 16 | 80 | 67.452 | 32.379 | 8.113 | 0.477 [0.454, 0.499] | 3.972 [3.901, 4.029] |
| SHA-256 | 100000 | 8 | 16 | 32 | 117.875 | 55.981 | 13.057 | 0.473 [0.422, 0.487] | 4.257 [4.243, 4.376] |
| SHA-256 | 25000 | 200 | 150 | 96 | 161.874 | 41.934 | 9.872 | 0.259 [0.249, 0.267] | 4.241 [4.029, 4.473] |
| SHA-384 | 20000 | 200 | 150 | 100 | 138.655 | 46.006 | 23.449 | 0.332 [0.309, 0.342] | 1.967 [1.913, 2.028] |
| SHA-512 | 20000 | 8 | 16 | 64 | 32.620 | 15.335 | 8.008 | 0.459 [0.452, 0.512] | 1.908 [1.805, 2.068] |

Swag reduced CPU time by 52–74% from its baseline. The wall ratios also
exclude parity for each profile. OpenSSL used less CPU across this panel.

All four variants prepare the keyed HMAC pads once and cache the salted
prefix before writing output. Later output blocks reuse that prefix and
later iterations reuse the pads. An overlapping password or salt is
consumed before the first output write. The HMAC owners and temporary
digests are cleared as the derivation finishes.

Native Release Core tests covered PBKDF2, overlap with a long password and
salt, every existing output tail, and the scrypt consumer. The focused
`security.swg` and `scrypt.swg` selections passed twelve cases.
[Raw CPU times, wall times, and derived outputs](pbkdf2.json)
