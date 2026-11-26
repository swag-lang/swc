# Integrated Core crypto validation at 15:22 CET

The Linux x86-64 Core snapshot was `3fcb964128`. The Release compiler
and adjacent runtime use the compiler source published at `44e09064f1`.
The executable SHA-256 was
`de29e0db7f3b5fc0a28efd580ca03b6ab4c82153dfa740985844aa7bb54508dd`.

| Program configuration | JIT passed | Native passed | Failures |
| --- | ---: | ---: | ---: |
| Release | 159 | 159 | 0 |
| Release-safe | 159 | 159 | 0 |

The focused `/crypto/` selection includes the CRC-64, AES-CCM and
scrypt stress tests. The same native compiler handled both program
configurations and kept the benchmark workspace and caches external.
The preceding report documents the command. [Reproduction](integrated-validation-1426.md).
