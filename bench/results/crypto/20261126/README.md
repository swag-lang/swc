# Crypto performance campaigns, November 26, 2026

Baseline Swag revision `d9bfeae85f` was built natively with the Linux Release compiler
and the Release program configuration. The machine exposed an AMD EPYC 9V74 under KVM.
The workload used one pinned CPU, process CPU time, 11 paired trials and four message
sizes per operation. It retained elapsed wall times for inspection.

References were OpenSSL 3.5.7, libdeflate 1.26, zlib 1.3.1, ISA-L 2.32.1, liblzma 5.8.1
and the official BLAKE3 C 1.8.7 implementation with x86-64 dispatch. Each operation's
full output matched in every timed trial. A separate correctness sweep matched 228
algorithm/input cases, including empty, short, unaligned and partial-block inputs.

The table shows 1 MiB messages and the fastest applicable measured reference per
operation. Rows describe the starting point. Component reports below show which
optimizations moved each result.

| Algorithm | Bytes | Offset | Swag build | Comparator | Swag GB/s | Comparator GB/s | Paired speed ratio (95% CI) |
| --- | ---: | ---: | --- | --- | ---: | ---: | ---: |
| adler32 | 1048576 | 0 | d9bfeae85f | libdeflate | 10.3 | 85.5 | 0.119 [0.0827, 0.123] |
| crc32 | 1048576 | 0 | d9bfeae85f | libdeflate | 14.1 | 55 | 0.256 [0.252, 0.267] |
| crc64-ecma | 1048576 | 0 | d9bfeae85f | ISA-L | 0.0413 | 52 | 0.000791 [0.000788, 0.000794] |
| crc64-iso | 1048576 | 0 | d9bfeae85f | ISA-L | 0.0349 | 56.8 | 0.000613 [0.000598, 0.000698] |
| crc64-xz | 1048576 | 0 | d9bfeae85f | ISA-L | 0.0367 | 56.9 | 0.000643 [0.000611, 0.000654] |
| md5 | 1048576 | 0 | d9bfeae85f | OpenSSL | 0.447 | 0.791 | 0.565 [0.555, 0.575] |
| sha1 | 1048576 | 0 | d9bfeae85f | OpenSSL | 0.236 | 1.88 | 0.126 [0.125, 0.129] |
| sha224 | 1048576 | 0 | d9bfeae85f | OpenSSL | 0.216 | 1.77 | 0.122 [0.12, 0.124] |
| sha256 | 1048576 | 0 | d9bfeae85f | OpenSSL | 0.217 | 1.78 | 0.122 [0.12, 0.123] |
| sha384 | 1048576 | 0 | d9bfeae85f | OpenSSL | 0.301 | 0.852 | 0.355 [0.35, 0.36] |
| sha512 | 1048576 | 0 | d9bfeae85f | OpenSSL | 0.295 | 0.831 | 0.36 [0.346, 0.376] |
| sha3-256 | 1048576 | 0 | d9bfeae85f | OpenSSL | 0.109 | 0.489 | 0.218 [0.2, 0.24] |
| blake2b-512 | 1048576 | 0 | d9bfeae85f | OpenSSL | 0.485 | 0.948 | 0.52 [0.499, 0.619] |
| blake2s-256 | 1048576 | 0 | d9bfeae85f | OpenSSL | 0.309 | 0.551 | 0.562 [0.524, 0.581] |
| blake3 | 1048576 | 0 | d9bfeae85f | BLAKE3 C | 0.414 | 6.51 | 0.0634 [0.0612, 0.064] |
| poly1305 | 1048576 | 0 | d9bfeae85f | OpenSSL | 0.224 | 12.4 | 0.0181 [0.0172, 0.02] |
| chacha20 | 1048576 | 0 | d9bfeae85f | OpenSSL | 0.796 | 5.06 | 0.16 [0.0453, 0.17] |
| chacha20-poly1305 | 1048576 | 0 | d9bfeae85f | OpenSSL | 0.175 | 3.67 | 0.0477 [0.0449, 0.0503] |
| aes-256-gcm | 1048576 | 0 | d9bfeae85f | OpenSSL | 0.000547 | 10.1 | 5.41e-05 [5.29e-05, 5.5e-05] |

[Full table for all four sizes](baseline.md) · [Raw timings and output fingerprints](baseline.json) ·
[Reproduction commands and methodology](../../../workloads/crypto/README.md).

## Optimization campaigns

- [CRC-64 portable slicing-by-eight](crc64-portable.md)
- [Poly1305 whole-block processing](poly1305.md)
- [GHASH carry-less reduction](ghash.md)
- [Portable SHA block processing](sha-portable.md)
- [Argon2id scalar compression and memory traversal](argon2.md)
- [Packed Adler-32 byte sums](adler32.md)
- [BLAKE3 register-resident compression](blake3.md)
- [Packed ChaCha20 block output](chacha20.md)
- [CRC-32 on short byte slices](crc32-short.md)
- [Keccak rounds with fixed lane positions](sha3-round.md)
- [MD5 wide loads and direct blocks](md5-wide.md)
- [BLAKE3 four-chunk batches](blake3-four-chunks.md)
- [Poly1305 keyed-state cleanup](poly1305-cleanup.md)
- [Packed SHA-512 message schedule](sha512-schedule.md)
- [Direct SHA-3 and SHAKE sponge input](sha3-direct.md)
- [Baseline public-key comparison](asymmetric-baseline.md)
- [BLAKE2b and BLAKE2s direct input blocks](blake2-direct.md)
- [Scrypt Salsa20/8 and BlockMix](scrypt.md)
- [P-256 ladder arithmetic](p256-ladder.md)
- [SHA-512 round-state rotation](sha512-rounds.md)
- [Curve25519 field inversion and squaring](curve25519-inverse.md)
- [P-256 four-bit scalar multiplication](p256-window.md)
- [CPU feature discovery and AES instructions](hardware-instructions.md)
- [AES-NI dispatch for AES and GCM](aesni.md)
- [CPU-gated carry-less CRC folding](crc64-fold.md)
- [Argon2id packed BlaMka permutation](argon2-packed.md)
- [Five-limb Curve25519 field arithmetic](curve25519-limbs.md)
- [P-256 fixed-base generator comb](p256-comb.md)
- [AES-GCM four-counter encryption](aes-batched.md)
- [Four-product reciprocal GHASH](aes-reciprocal.md)
- [CityHash32 word loads and state rotation](cityhash32.md)
- [P-256 field inversion addition chain](p256-inverse.md)
- [PBKDF2-HMAC prefix reuse](pbkdf2.md)
- [Four-word P-256 Montgomery products](p256-wide.md)
- [Ed25519 masked four-bit scalar windows](ed25519-window.md)
- [Parallel CRC-64 on large buffers](crc64-parallel.md)
