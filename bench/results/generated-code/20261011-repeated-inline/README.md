# Repeated single-site wrapper inlining

Accepted on static evidence against `78ccdd423`; timing is not measured.
The previous full campaign was rejected for machine drift. This batch is
landed, unconfirmed until an accepted session campaign shows a target move.

The parser records postfix not-null assertions separately from fallible
error-management scopes and identifies calls inside loops or recursive
components. Only a unique module call and identifier use earns the repeated
last-call exception. Cold setup, address-taken helpers, recursive candidates,
fallible scopes and the existing unsupported body shapes retain their guards.
Sema permits nullable block-pointer parameters because their inline bindings
already preserve the declared type; nullable value pointers remain excluded.
Nullable returns qualify at the same repeated site. No benchmark source changed.

## Executed native paths

The actual PE instructions were decoded from each function's entry with LLVM
objdump; starting at the entry avoids decoding padding as part of a function.
The baseline includes the caller and its wrapper, without recursively counting
its children or the allocator implementation. Both versions use an initialized
low TLS slot, successful allocation, and a non-null released node.

| Path per node | Instructions before to after | Explicit memory before to after | Calls before to after |
| --- | --- | --- | --- |
| Allocate internal node | 61 to 53 | 20 to 20 | 4 to 3 |
| Allocate leaf | 55 to 47 | 19 to 19 | 2 to 1 |
| Release internal node | 53 to 48 | 20 to 20 | 4 to 3 |
| Release leaf | 44 to 39 | 15 to 15 | 2 to 1 |

This removes 13 instructions and two call edges per allocated/released node,
regardless of the internal/leaf weighting: 8,768,214 instructions and 1,348,956
calls over 674,478 nodes. The checksum is 674478. Explicit memory includes the
TLS read and excludes LEA, implicit call/return stack traffic and register
push/pop operations. Register pushes/pops remain six on allocation and four
on release. The allocator implementation and recursive child work are unchanged.

The recursive frames grow: bottomUp reserves 0xb0 bytes and saves three
registers instead of reserving eight and saving two; release reserves 0xc8
and saves two instead of reserving 0x38 with no saved registers. The old
out-of-line wrappers separately reserved 0xa0/0x98 bytes. Inlining retains
request space across recursion but adds no executed frame loads/stores.
The maximum depth is fourteen levels; the larger recursive working stack
is about 3 KiB in each traversal. This is a stack-capacity trade, not a
claim that a function's larger instruction total is itself a gain.

Java/HotSpot remains the fastest competing runtime in accepted campaign
20261011-163035. The actual Temurin 25.0.4.1+1 default-tiered C2 allocation
path inspected in [the preceding batch](../20261011-frame-escape/README.md)
uses a bump pointer and garbage collection; Swag retains explicit allocation
and reclamation. This batch removes wrapper overhead only.

## Scope and validation

All twelve Release benchmark checksums pass with `--validate-micro`. The full
body comparison, after normalizing relocation identities and duplicate dump
suffixes, changes only binarytrees' bottomUp/release and the shared cold
`__setupRuntime`/`__printPanicReport`. Every other benchmark hot function and
all allocator fast paths are unchanged. Counts and loop inventories are in
[microdiff.json](microdiff.json); [body-comparison.json](body-comparison.json)
checks whole bodies, and [native-path-counts.json](native-path-counts.json)
records native entry addresses and executed-path counts.

DevMode compiler validation, each command admitted by the machine-load check:

- Build: `MSBuild swc.sln /t:Build /p:Configuration=DevMode /p:Platform=x64
  /m:6 /p:SwcCompileJobs=6`.
- `bin/swc.dm.exe --num-cores 6 tools/unittests.swgs dm cpp --num-cores 6`:
  1,430 C++ tests passed, including the new parser eligibility regression.
- `bin/swc.dm.exe --num-cores 6 tools/unittests.swgs dm native
  --file-filter auto_repeated_call --num-cores 6 --rebuild`: 22 inputs,
  one test passed in JIT and native execution. The same command with
  `-bc release` also passed, covering the guard-free path.
- `bin/swc.dm.exe --num-cores 6 tools/unittests.swgs dm sema
  --file-filter inline_nullable_assert.swg --num-cores 6 --rebuild`:
  the positive fixture type-checked (21 inputs); the expected-error branch
  selected only its 20 runtime inputs. Zero executable tests is expected.
- The two new Swag files were formatted twice; the second pass was stable.

The graph analysis remains O(V + E) time and space per source graph, now
prepared for every graph so a recursive caller in another file can mark its
callee before declaration selection. The additional marking is O(V + E)
with an O(V) bit vector. Graphs remain separate; this does not claim to find
recursion whose cycle itself crosses files. Body cost remains immutable.
One diagnostic binarytrees compile, including all Micro printing, changed
350.3 to 352.7 ms wall time and 252.3 to 254.0 MiB peak job commit; these are
single samples, not a compiler-performance claim.
