# MD5 direct block batches

The MD5 update keeps its four state words across complete input blocks.
Message words load directly in little-endian order, and the constant
addition can proceed independently of the Boolean round function.

The native Release workload used 13 paired process CPU-time trials
on AMD EPYC 9V74 CPU 1 with input offset by one byte. At 4 MiB throughput
rose from 0.502 to 0.708 GB/s, a paired 1.41× [1.38, 1.44].
OpenSSL 3.5.7 reached 0.791 GB/s.

| Algorithm | Bytes | Offset | Swag build | Comparator | Unit | Swag rate | Comparator rate | Paired speed ratio (95% CI) |
| --- | ---: | ---: | --- | --- | --- | ---: | ---: | ---: |
| md5 | 1 | 1 | baseline | OpenSSL | GB/s | 0.00704 | 0.00857 | 0.821 [0.801, 0.832] |
| md5 | 55 | 1 | baseline | OpenSSL | GB/s | 0.421 | 0.503 | 0.841 [0.824, 0.85] |
| md5 | 56 | 1 | baseline | OpenSSL | GB/s | 0.205 | 0.287 | 0.711 [0.693, 0.727] |
| md5 | 63 | 1 | baseline | OpenSSL | GB/s | 0.23 | 0.321 | 0.706 [0.683, 0.735] |
| md5 | 64 | 1 | baseline | OpenSSL | GB/s | 0.243 | 0.333 | 0.73 [0.71, 0.737] |
| md5 | 65 | 1 | baseline | OpenSSL | GB/s | 0.237 | 0.332 | 0.708 [0.696, 0.726] |
| md5 | 127 | 1 | baseline | OpenSSL | GB/s | 0.311 | 0.46 | 0.679 [0.663, 0.718] |
| md5 | 128 | 1 | baseline | OpenSSL | GB/s | 0.324 | 0.459 | 0.697 [0.675, 0.715] |
| md5 | 129 | 1 | baseline | OpenSSL | GB/s | 0.321 | 0.456 | 0.684 [0.674, 0.743] |
| md5 | 4097 | 1 | baseline | OpenSSL | GB/s | 0.492 | 0.774 | 0.641 [0.623, 0.659] |
| md5 | 16384 | 1 | baseline | OpenSSL | GB/s | 0.501 | 0.794 | 0.639 [0.617, 0.654] |
| md5 | 4194304 | 1 | baseline | OpenSSL | GB/s | 0.502 | 0.791 | 0.636 [0.622, 0.645] |
| md5 | 16777216 | 1 | baseline | OpenSSL | GB/s | 0.501 | 0.773 | 0.64 [0.617, 0.649] |

The three focused cases passed in both native Release configurations.
The new fixture streams an unaligned 4097-byte input. Thirteen
external OpenSSL comparisons matched.

[Raw trials and output fingerprints](md5-block-batches.json).
