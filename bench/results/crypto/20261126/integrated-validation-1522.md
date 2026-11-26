# Integrated Core crypto validation at 15:22 CET

The Linux x86-64 Core snapshot was . The Release compiler
and adjacent runtime use the compiler source published at .
The executable SHA-256 was .

| Program configuration | JIT passed | Native passed | Failures |
| --- | ---: | ---: | ---: |
| Release | 159 | 159 | 0 |
| Release-safe | 159 | 159 | 0 |

The focused  selection includes the CRC-64, AES-CCM and
scrypt stress tests. The same native compiler handled both program
configurations and kept the benchmark workspace and caches external.
The preceding report documents the command. [Reproduction](integrated-validation-1426.md).
