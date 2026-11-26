# Integrated Core crypto validation at 16:19 CET

This snapshot uses library source `bd4cfab5c1` and the combined
Release compiler and runtime through `c7629c28dd`. Its SHA-256 is
`1afdeb7aa6fac4b9f81ddc738305d6436bf25ba25223ccaa95deda35fa6e9fd2`.
The run covers the original parallel CRC and Poly1305 paths, and the initial
register-pair IFMA kernel.

| Program configuration | JIT passed | Native passed | Failures |
| --- | ---: | ---: | ---: |
| Release | 164 | 164 | 0 |
| Release-safe | 164 | 164 | 0 |

[19-operation replay](integrated-replay-1619.md) · [Reproduction](integrated-validation-1426.md)
