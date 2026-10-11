# Select the rounding bias for signed remainders

Baseline: `26acca176`. The preserved DevMode compiler SHA-256 is
`838e6d3915110682924a916eef388057868cfbdc877afdc66bbfcbb6c6fc5bcf`.
All captures use Release programs, six workers, isolated outputs, and
`--validate-micro`. No benchmark source or workload changed.

| Task / competitor | Bottleneck | Mechanism | Executed path | Other tasks | Timing | Checks | Decision |
| --- | --- | --- | --- | --- | --- | --- | --- |
| nbody / Zig | Shared scalar masses and distance factors prevent velocity SLP | Inspected the value graph and insertion point | Unchanged | No edit retained | Not measured | Diagnostic capture; checksum 169096566666 | Deferred: simply allowing repeated loads duplicates distance arithmetic |
| lz77 / D-LDC | Signed remainder constructs a rounding bias with two dependent shifts | Select the rounded dividend, mask the multiple, subtract from the original | 7 to 6 instructions per signed remainder | All eleven other tasks and runtime functions retain instruction/memory/call and loop counts | Not measured | 1,374 C++ tests; signed_modulo_pow2.swg through JIT and native; twelve checksums | Landed, unconfirmed |

For a positive power-of-two divisor C, the new expansion is
`n - ((n < 0 ? n + C - 1 : n) & -C)`. It applies when C is at least four
and C - 1 fits the signed 32-bit displacement of LEA. The temporary addition
may wrap for positive n, but the original n is then selected. Negative n
cannot overflow when adding this positive bias. All operations retain the
original 32- or 64-bit width. Division by two and wider biases retain the
existing shift construction. Signed division shares the existing rounding
selection helper and emits the same instructions as before.

The final native sequence for each of lz77's two changed sites is:

```asm
mov    r8, rax
lea    r9, [rax + 32767]
test   rax, rax
cmovge r9, rax
and    r9, -32768
sub    r8, r9
```

It replaces seven instructions (`mov`, `mov`, `sar`, `shr`, `add`, `and`,
`sub`). The first site runs once per outer compression iteration; the second
runs once per inserted match position that passes the end-of-input guard.
The inner insertion loop falls from 27 to 26 instructions, with three memory
operands and no calls. The outer matched path's textual loop envelope falls
from 126 to 124 instructions (17 memory operands), and the literal path's
larger envelope from 133 to 131 (20 memory operands). Those envelopes include
nested/alternative paths; they are not summed as independent runtime savings.
The enclosing function is 461 to 459 instructions, with 78 memory operands,
19 calls, and unchanged frame traffic.

D-LDC 1.43.0 (DMD 2.113.0, LLVM 22.1.8) was built with the benchmark's
`-O3 -release -boundscheck=off` recipe. Its emitted signed remainders likewise
select the rounded dividend before masking and subtracting. Both programs
produce `622942003053`. The ports retain truncating signed remainder semantics;
no nonnegative induction-variable assumption was introduced.

The full comparison is in [microdiff.json](microdiff.json). It pairs overloaded
function bodies independently of their nondeterministic printed suffixes and
normalizes generated lambda/run-expression IDs. Only lz77's main has changed
counts. Allocator and wrapper functions retain their work in every task.

The new C++ case checks the encodable-bias boundary at both widths. Existing
nonnegative and low-bit-use tests still verify that a proved mask avoids sign
correction. The native regression file compares constant and dynamic divisors
for negative values, zero, both signed extrema, large divisors and a reused
dividend; it passes once through JIT and once natively in DevMode. This batch
adds constant work at each already-selected constant-division expansion and no
new analysis. A session campaign will decide whether runtime moves beyond noise.
