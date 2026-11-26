# Packed AES-KW and AES-KWP rounds

Swag keeps the integrity value and each data word in the AES block registers during wrapping
and unwrapping. Unwrapping prepares the inverse round keys once. The public unwrap calls still
verify the integrity value and padding before copying key material to the destination.

At 64 bytes, AES-KW wrapping increased from 0.0326 to 0.0511 GB/s and unwrapping increased
from 0.0296 to 0.0470 GB/s. The paired speedup was 1.58× in both cases. AES-KWP improved
1.53× for wrapping and 1.58× for unwrapping. OpenSSL 4.1.0's EVP key-wrap provider uses
`AES_encrypt` and `AES_decrypt` through its generic wrap implementation. [OpenSSL provider source](https://github.com/openssl/openssl/blob/openssl-4.1.0/providers/implementations/ciphers/cipher_aes_wrp.c)

## Method

Both Swag executables use the same Release compiler, standard-library sources and harness, with
`aeskeywrap.swg` replaced in the candidate. The reference links OpenSSL 4.1.0 and was built with
`-Werror`. The timed comparison used one worker on CPU 2 of an AMD EPYC 9V74, with nine
interleaved samples targeting 15 ms of process CPU time per implementation and input. Rates use
the original key-data length. The harness wraps each unwrap fixture before timing and checks
the complete output of every sample. KWP adapters zero the unused output capacity for comparison.
[Workload and build instructions](../../../workloads/crypto/README.md)

| Algorithm | Bytes | Offset | Swag build | Comparator | Unit | Swag rate | Comparator rate | Paired speed ratio (95% CI) |
| --- | ---: | ---: | --- | --- | --- | ---: | ---: | ---: |
| aes-256-kw | 16 | 0 | current | OpenSSL | GB/s | 0.028 | 0.0103 | 2.73 [2.72, 2.76] |
| aes-256-kw | 16 | 0 | packed | OpenSSL | GB/s | 0.0399 | 0.0103 | 3.9 [3.88, 4] |
| aes-256-kw | 16 | 0 | packed | current | GB/s | 0.0399 | 0.028 | 1.43 [1.42, 1.47] |
| aes-256-kw | 64 | 0 | current | OpenSSL | GB/s | 0.0326 | 0.0105 | 3.14 [2.42, 3.23] |
| aes-256-kw | 64 | 0 | packed | OpenSSL | GB/s | 0.0511 | 0.0105 | 4.88 [4.81, 5.1] |
| aes-256-kw | 64 | 0 | packed | current | GB/s | 0.0511 | 0.0326 | 1.58 [1.52, 1.99] |
| aes-256-kw | 256 | 0 | current | OpenSSL | GB/s | 0.0348 | 0.0107 | 3.23 [3.2, 3.28] |
| aes-256-kw | 256 | 0 | packed | OpenSSL | GB/s | 0.0558 | 0.0107 | 5.21 [5.15, 5.35] |
| aes-256-kw | 256 | 0 | packed | current | GB/s | 0.0558 | 0.0348 | 1.6 [1.57, 1.67] |
| aes-256-kw | 4096 | 0 | current | OpenSSL | GB/s | 0.0353 | 0.0107 | 3.3 [3.27, 3.34] |
| aes-256-kw | 4096 | 0 | packed | OpenSSL | GB/s | 0.0574 | 0.0107 | 5.36 [5.3, 5.42] |
| aes-256-kw | 4096 | 0 | packed | current | GB/s | 0.0574 | 0.0353 | 1.62 [1.61, 1.64] |
| aes-256-kw-unwrap | 16 | 0 | current | OpenSSL | GB/s | 0.0242 | 0.00686 | 3.52 [3.47, 3.64] |
| aes-256-kw-unwrap | 16 | 0 | packed | OpenSSL | GB/s | 0.034 | 0.00686 | 5.02 [4.66, 5.11] |
| aes-256-kw-unwrap | 16 | 0 | packed | current | GB/s | 0.034 | 0.0242 | 1.39 [1.32, 1.44] |
| aes-256-kw-unwrap | 64 | 0 | current | OpenSSL | GB/s | 0.0296 | 0.00723 | 4.07 [3.88, 4.13] |
| aes-256-kw-unwrap | 64 | 0 | packed | OpenSSL | GB/s | 0.047 | 0.00723 | 6.45 [6.28, 6.61] |
| aes-256-kw-unwrap | 64 | 0 | packed | current | GB/s | 0.047 | 0.0296 | 1.58 [1.53, 1.66] |
| aes-256-kw-unwrap | 256 | 0 | current | OpenSSL | GB/s | 0.0316 | 0.00747 | 4.25 [3.65, 4.3] |
| aes-256-kw-unwrap | 256 | 0 | packed | OpenSSL | GB/s | 0.0525 | 0.00747 | 7.08 [6.91, 7.18] |
| aes-256-kw-unwrap | 256 | 0 | packed | current | GB/s | 0.0525 | 0.0316 | 1.68 [1.65, 1.96] |
| aes-256-kw-unwrap | 4096 | 0 | current | OpenSSL | GB/s | 0.0325 | 0.0075 | 4.33 [4.29, 4.38] |
| aes-256-kw-unwrap | 4096 | 0 | packed | OpenSSL | GB/s | 0.0542 | 0.0075 | 7.22 [7.15, 7.33] |
| aes-256-kw-unwrap | 4096 | 0 | packed | current | GB/s | 0.0542 | 0.0325 | 1.67 [1.64, 1.7] |
| aes-256-kwp | 16 | 0 | current | OpenSSL | GB/s | 0.0246 | 0.0102 | 2.4 [2.33, 2.46] |
| aes-256-kwp | 16 | 0 | packed | OpenSSL | GB/s | 0.0341 | 0.0102 | 3.33 [3.14, 3.41] |
| aes-256-kwp | 16 | 0 | packed | current | GB/s | 0.0341 | 0.0246 | 1.38 [1.27, 1.45] |
| aes-256-kwp | 64 | 0 | current | OpenSSL | GB/s | 0.0313 | 0.0106 | 2.96 [2.89, 3.05] |
| aes-256-kwp | 64 | 0 | packed | OpenSSL | GB/s | 0.0484 | 0.0106 | 4.58 [4.53, 4.63] |
| aes-256-kwp | 64 | 0 | packed | current | GB/s | 0.0484 | 0.0313 | 1.53 [1.49, 1.59] |
| aes-256-kwp | 256 | 0 | current | OpenSSL | GB/s | 0.0338 | 0.0105 | 3.23 [3.09, 3.34] |
| aes-256-kwp | 256 | 0 | packed | OpenSSL | GB/s | 0.053 | 0.0105 | 5.03 [4.96, 5.18] |
| aes-256-kwp | 256 | 0 | packed | current | GB/s | 0.053 | 0.0338 | 1.58 [1.55, 1.66] |
| aes-256-kwp | 4096 | 0 | current | OpenSSL | GB/s | 0.0352 | 0.0106 | 3.32 [3.18, 3.35] |
| aes-256-kwp | 4096 | 0 | packed | OpenSSL | GB/s | 0.056 | 0.0106 | 5.27 [5.2, 5.35] |
| aes-256-kwp | 4096 | 0 | packed | current | GB/s | 0.056 | 0.0352 | 1.6 [1.59, 1.64] |
| aes-256-kwp-unwrap | 16 | 0 | current | OpenSSL | GB/s | 0.0242 | 0.00684 | 3.54 [3.5, 3.58] |
| aes-256-kwp-unwrap | 16 | 0 | packed | OpenSSL | GB/s | 0.0343 | 0.00684 | 5.02 [4.91, 5.14] |
| aes-256-kwp-unwrap | 16 | 0 | packed | current | GB/s | 0.0343 | 0.0242 | 1.43 [1.39, 1.44] |
| aes-256-kwp-unwrap | 64 | 0 | current | OpenSSL | GB/s | 0.0299 | 0.00728 | 4.1 [3.99, 4.15] |
| aes-256-kwp-unwrap | 64 | 0 | packed | OpenSSL | GB/s | 0.0471 | 0.00728 | 6.48 [6.15, 6.51] |
| aes-256-kwp-unwrap | 64 | 0 | packed | current | GB/s | 0.0471 | 0.0299 | 1.58 [1.5, 1.63] |
| aes-256-kwp-unwrap | 256 | 0 | current | OpenSSL | GB/s | 0.0315 | 0.0074 | 4.2 [4.18, 4.31] |
| aes-256-kwp-unwrap | 256 | 0 | packed | OpenSSL | GB/s | 0.0521 | 0.0074 | 7.05 [6.86, 7.09] |
| aes-256-kwp-unwrap | 256 | 0 | packed | current | GB/s | 0.0521 | 0.0315 | 1.67 [1.59, 1.69] |
| aes-256-kwp-unwrap | 4096 | 0 | current | OpenSSL | GB/s | 0.0323 | 0.00744 | 4.32 [4.25, 4.36] |
| aes-256-kwp-unwrap | 4096 | 0 | packed | OpenSSL | GB/s | 0.0537 | 0.00744 | 7.3 [7.15, 7.33] |
| aes-256-kwp-unwrap | 4096 | 0 | packed | current | GB/s | 0.0537 | 0.0323 | 1.67 [1.65, 1.7] |

## Verification

The external comparison matched full outputs for 40 unaligned AES-KW inputs in each direction
and 56 unaligned AES-KWP inputs in each direction, including the one-block padding boundary.
Six existing workloads passed four inputs each after integration. All three focused Core cases
passed in Release and Release-safe, on the host and under QEMU with AES and PCLMUL disabled.

[Raw paired trials](aes-key-wrap.json) · [AES-KW verification](aes-key-wrap-verification.json) · [AES-KWP verification](aes-key-wrap-padded-verification.json) · [Integration checks](aes-key-wrap-regression.json)
