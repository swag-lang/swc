# YMM AES rounds in XTS and CTR

A Swag Release prototype processed eight blocks at a time using four YMM states and a
broadcast round key. Core staged the states in an unaligned 128-byte buffer for the
instruction, which read and wrote the buffer. For XTS, one prototype stored the eight
tweaks in an array, while a second kept them in named SIMD locals. Both used the cached
inverse schedule, and the XMM path handled ciphertext stealing. In CTR, the buffer held
eight consecutive counters and the existing XMM path handled the remainder.

| 1 MiB through one worker | Swag XMM | Swag YMM array | Swag YMM named tweaks | OpenSSL 4.1.0 |
| --- | ---: | ---: | ---: | ---: |
| AES-256-XTS encryption | 6.01 | 3.82 | 4.31 | 13.8 |
| AES-256-XTS decryption | 5.10 | 3.18 | 4.25 | 11.4 |
| AES-256-CTR | 6.61 | 4.44 | — | 8.00 |

Rates are in GB/s. These tests used AMD EPYC 9V74 CPU 2, with nine interleaved rounds
targeting 15 ms of process CPU time per implementation and size. The Swag builds share
one scratch Release compiler and use `203fa9534e` for the XMM baseline library. The fastest
YMM version reached 71–74% of XMM throughput in XTS and 68% in CTR at 1 MiB. The project
kept the XMM implementation for these modes. [Workload and build instructions](../../../workloads/crypto/README.md)

The Swag XTS variants matched OpenSSL on 56 size-and-offset cases per direction, including
ciphertext stealing. CTR matched on 60 cases around the AES and eight-block boundaries.
QEMU with `-cpu max,-vaes` selected the XMM fallback and matched on the same inputs. A focused
native test checked the standalone VAES operation with AES-128 and AES-256, in both
directions, against single-block computation. The feature check also reported VAES as disabled
under that QEMU mask.

## C control

With the surrounding XTS operations and the AES rounds visible to GCC, the YMM implementation
reached 8.02 GB/s for encryption and 7.90 GB/s for decryption at 1 MiB. The four-state XMM
control reached 6.47 and 6.44 GB/s. Forcing a C call boundary between tweak XOR and the AES
rounds reduced the YMM rates to 7.63 and 7.66 GB/s. OpenSSL 3.5.7 reached 13.7 and 13.8 GB/s
in this separate run. The C controls include AES-256 key expansion and use eleven interleaved
rounds targeting 20 ms on the same CPU. All three models matched OpenSSL on 56 inputs per
direction, including the XMM fallback selected by QEMU with VAES masked.

Build the common reference, set `WORK` to an existing absolute scratch directory and set
`CPU` to an available CPU. Model 0 uses four XMM AES-NI states. Model 1 keeps four YMM states
across eight AES blocks. Model 2 adds the call boundary. GCC 14.2.0 reproduced the hashes for
all three executable models in the raw trials.

```sh
for model in 0 1 2; do
  gcc -O3 -march=x86-64-v3 -maes -DXTS_MODEL="$model" \
    bench/workloads/crypto/aes-xts-width.c -o "$WORK/xts-width-$model"
done
python3 -B bench/workloads/crypto/run.py \
  --swag "xmm=$WORK/xts-width-0" --swag "ymm=$WORK/xts-width-1" \
  --swag "boundary=$WORK/xts-width-2" --reference "$WORK/reference" --cpu "$CPU" \
  --algorithm aes-256-xts-encrypt --algorithm aes-256-xts-decrypt \
  --size 64 --size 4096 --size 65536 --size 1048576 --rounds 11 --target-ms 20 \
  --scratch "$WORK" --output "$WORK/xts-width.json"
```

[Swag XTS trials](aes-vaes-xts.json) · [Swag XTS verification](aes-vaes-xts-verification.json) · [Swag CTR trials](aes-vaes-ctr.json) · [Swag CTR verification](aes-vaes-ctr-verification.json) · [C XTS trials](aes-vaes-xts-c.json) · [C XTS verification](aes-vaes-xts-c-verification.json)
