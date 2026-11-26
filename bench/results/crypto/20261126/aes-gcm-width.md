# AES-GCM vector width and scheduling

At 1 MiB, the C interleaved kernel increased from 4.14 GB/s with XMM AES-NI and
PCLMULQDQ to 7.29 GB/s with YMM VAES and VPCLMULQDQ. The materialized YMM
variant reached 6.11 GB/s and the separate YMM passes reached
6.25 GB/s. The published Swag path reached 3.9 GB/s and
OpenSSL 4.1.0 reached 10.2 GB/s in the same comparison.

| Bytes | C XMM interleaved | C YMM interleaved | C YMM materialized | C YMM separate | Swag | OpenSSL 4.1.0 |
| ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| 4096 | 3.98 | 6.69 | 5.78 | 5.85 | 3.08 | 5.8 |
| 65536 | 4.14 | 7.47 | 6.31 | 6.4 | 3.84 | 9.97 |
| 1048576 | 4.14 | 7.29 | 6.11 | 6.25 | 3.9 | 10.2 |

Rates are in GB/s. Nine interleaved samples used process CPU time on CPU 2 of an AMD EPYC
9V74, with a 16 ms target per implementation and input. Each C operation expands the key,
authenticates the fixed associated data, encrypts the message and writes the full tag. All C
models use the same fixture and include equivalent input copying outside the timer. The
materialized model forces the active AES states, previous ciphertext and GHASH powers through
memory at each batch boundary. The published Swag column uses the single-worker path from
`b5067b220e`.

The four C models matched the OpenSSL ciphertext and tags on 64 size-and-offset combinations.
The YMM interleave also passed all 64 combinations under QEMU with VAES and VPCLMULQDQ
masked, which selects its XMM branch.

## Reproduce

Build the common Swag executable and an OpenSSL 4.1.0 reference as described in the workload
README. Set `WORK` to the absolute scratch directory containing those executables and set
`CPU` to a CPU in the local affinity mask. [Workload and build instructions](../../../workloads/crypto/README.md)

```sh
cc -O3 -Wall -Wextra -Werror -march=x86-64-v3 -maes -mpclmul \
  -DGCM_MODEL=2 bench/workloads/crypto/aes-gcm-width.c -o "$WORK/gcm-width-2"
for model in 3 4 5; do
  cc -O3 -Wall -Wextra -Werror -march=x86-64-v3 -maes -mpclmul -mvaes -mvpclmulqdq \
    -DGCM_MODEL="$model" bench/workloads/crypto/aes-gcm-width.c -o "$WORK/gcm-width-$model"
done
python3 -B bench/workloads/crypto/run.py \
  --swag "xmm=$WORK/gcm-width-2" --swag "ymm=$WORK/gcm-width-3" \
  --swag "ymm-boundary=$WORK/gcm-width-4" --swag "ymm-separate=$WORK/gcm-width-5" \
  --swag "swag=$WORK/swag-crypto" --reference "$WORK/reference" --cpu "$CPU" \
  --algorithm aes-256-gcm --size 4096 --size 65536 --size 1048576 \
  --rounds 9 --target-ms 16 --scratch "$WORK" --output "$WORK/gcm-width.json"
```

For hardware-masked verification, add a runner that invokes `gcm-width-3` through
`qemu-x86_64 -cpu max,-vaes,-vpclmulqdq`. Select `--verify-only` with sizes 0, 1, 15, 16, 63,
64, 65, 127, 128, 129, 145, 191, 192, 193, 1025 and 65555 and offsets 0, 1, 7 and 15.

[Raw paired trials](aes-gcm-width.json) · [Exact verification](aes-gcm-width-verification.json)

## Swag 512-bit GHASH screen

A Swag Release prototype applied the published `vecCarrylessMul2XorQuad`
instruction to four GHASH input blocks with powers `H^4`, `H^3`, `H^2` and
`H`. Each batch staged three copies of those four lanes. Three instruction
calls computed the low, high and cross products before horizontal XOR
and the existing GHASH reduction. The prototype selected this path for
512 bytes or more when the runtime detected AVX-512 and VPCLMULQDQ.

At 1 MiB of associated data, the four-lane result was 3.00 GB/s versus
6.38 GB/s for the published XMM loop. The paired ratio was 0.470
[0.463, 0.472], and OpenSSL 4.1.0 reached 23.0 GB/s. Full-message
GCM controls reached 3.86 and 3.89 GB/s, with a paired interval including
parity. Eleven interleaved trials targeted 10 ms of process CPU time
per implementation on CPU 2 of the same AMD EPYC 9V74. The prototype
and its QEMU `max,-avx512f` fallback matched the full OpenSSL tags on all
48 size-and-offset inputs.

[Swag 512-bit screen trials](aes-ghash-quad-screen.json) · [Exact 512-bit screen verification](aes-ghash-quad-screen-verification.json)
