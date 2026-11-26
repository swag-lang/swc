# Final integrated Core crypto validation

The frozen source revision was `10bf72c650` at 16:41 CET on November 26,
2026. The Linux x86-64 Release compiler and adjacent runtime match all
1,188 compiler, runtime and build inputs at `580d8cc4b7`. The compiler
SHA-256 is `e0e8fb233c045d296d4de002c583b17c276b7340e3a71d3f3a9d4ce714d2e5eb`.

The Core `/crypto/` selection includes the functional tests and the
checksum, cipher and key derivation stress fixtures. The native and
JIT suites ran in fresh external workspaces using the same compiler.

| Program configuration | JIT passed | Native passed | Failures |
| --- | ---: | ---: | ---: |
| Release | 169 | 169 | 0 |
| Release-safe | 169 | 169 | 0 |

The complete language reference passed 526 tests in each mode in
Release. The matching DevMode compiler passed 1,752 C++ tests. The
twelve paired Release Micro workload checksums matched before and
after the last lowering change. The compiler campaigns also emitted
and inspected Windows x64 COFF for the relevant intrinsics.

[Final performance comparison](integrated-final.md) · [Reproduction](integrated-validation-1426.md) · [Compiler carry-less validation](wide-carryless-instruction.md) · [Full-width carry validation](wide-multiply-addends.md)
