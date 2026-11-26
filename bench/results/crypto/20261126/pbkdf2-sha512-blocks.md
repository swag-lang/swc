# PBKDF2-HMAC-SHA-384/512 fixed final blocks

After the first iteration, each HMAC half hashes one digest after a
precomputed key pad. Swag prepares its final SHA-512 block once per output
block, reuses the padding and length, and reloads only the eight keyed
state words for each compression. Packed stores serialize the result and
XOR the outer digest into the accumulator. The temporary block and hash
state are cleared.

Both Swag builds use native Release with the phased SHA-512 compressor from
`1858c17b50`. Seventeen paired rounds ran on CPU 2 of an AMD EPYC 9V74
under Linux 6.18.57. Each timed derivation includes cleanup and matches
every output byte. The table reports median process CPU milliseconds and
paired 95% time-ratio intervals.

| HMAC | Iterations | Password / salt / output bytes | Before | Fixed blocks | OpenSSL 3.5.8 | Fixed / before | Fixed / OpenSSL |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| SHA-224 | 20000 | 8 / 16 / 80 | 5.692 | 5.644 | 8.461 | 0.992 [0.969, 1.005] | 0.665 [0.645, 0.675] |
| SHA-256 | 100000 | 8 / 16 / 32 | 9.146 | 8.840 | 13.889 | 0.991 [0.944, 1.003] | 0.639 [0.624, 0.667] |
| SHA-256 | 25000 | 200 / 150 / 96 | 6.639 | 6.576 | 10.344 | 0.995 [0.972, 1.023] | 0.645 [0.615, 0.659] |
| SHA-384 | 20000 | 200 / 150 / 100 | 33.760 | 29.759 | 23.390 | 0.873 [0.851, 0.921] | 1.252 [1.223, 1.311] |
| SHA-512 | 20000 | 8 / 16 / 64 | 11.176 | 9.591 | 7.755 | 0.852 [0.836, 0.882] | 1.233 [1.228, 1.238] |

SHA-384 used 13% less CPU and SHA-512 used 15% less. Their elapsed-time
intervals also excluded parity against the Swag baseline. These profiles
still took 23–25% more CPU than OpenSSL. The SHA-224/256 intervals span
parity with the previous Swag build and show 34–36% less CPU than OpenSSL.

Seventeen focused Core cases passed in each of native Release and
Release-safe, covering PBKDF2 output tails and overlap, SHA-512 and
HMAC vectors, and scrypt.

[Reproduction](../../../workloads/pbkdf2/README.md) · [Raw samples and derived outputs](pbkdf2-sha512-blocks.json)
