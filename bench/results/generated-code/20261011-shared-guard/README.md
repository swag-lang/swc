# Keep a shared guarded call's spills on its slow path

Accepted on static evidence against `0c8186b83`; timing is not measured.
This extends the allocator's existing guarded-call preference to a labeled
slow block entered only by forward conditional guards and ending with a
call-result copy. It preserves caller-saved values around the call itself.
Back edges, indirect/address-taken entries, unconditional entries, interior
labels and void report blocks do not qualify for the new preference.

The motivating native TLS lookup has two entries into one helper: a slot
outside Windows' low TLS array, or a missing context in a low slot. The
shared entry label previously made the helper look like a hot call, keeping
the slot number in a callee-saved register on every fast lookup. No context
installation, lookup, mutation or error-handling contract changes.

## Native executed paths

Final PE functions were decoded from their actual entry addresses with LLVM
objdump. Counts below include each node's function but exclude recursive
children and the unchanged allocator implementation. They assume successful
allocation, non-null nodes and an already initialized low TLS context.

| Path per node | Instructions before to after | Register pushes/pops before to after |
| --- | --- | --- |
| Allocate internal node | 53 to 51 | 6 to 4 |
| Allocate leaf | 47 to 45 | 6 to 4 |
| Release internal node | 48 to 46 | 4 to 2 |
| Release leaf | 39 to 37 | 4 to 2 |

Four instructions and four stack memory operations disappear per node,
independent of leaf/internal weighting: 2,697,912 of each over 674,478 nodes.
Explicit memory operands and calls are unchanged on these fast paths.
The combined reserved frame plus saved-register area is unchanged: one
additional eight-byte spill slot replaces one saved register.

On the TLS slow path each eliminated push/pop pair becomes an explicit
spill/reload pair around the helper, leaving the executed instruction and
memory-operation counts of bottomUp/release unchanged. The standalone
benchAlloc still needs its saved register for another use: its fast path
stays at 39 instructions, while its slow lookup grows from 42 to 44 and
adds two memory operations. The ordinary initialized low-slot benchmark
lookup never takes that path. benchFree's fast path falls 35 to 33; its slow
path keeps 38 instructions. This trade is explicit rather than hidden in
the whole-function totals. Other wrappers using getContext may similarly
reserve cold spill space while retaining another use of a saved register.

The earlier Java/HotSpot C2 inspection remains applicable: the winning
Temurin 25.0.4.1+1 runtime uses bump allocation and GC. This change addresses
Swag's per-node wrapper overhead without changing allocation or reclamation.

## Scope and validation

All twelve benchmark checksums pass. Whole-body comparison normalizes only
relocation identities, generated IDs and duplicate dump suffixes. Every
application hot body except binarytrees bottomUp/release is unchanged.
Shared changes are the two benchmark wrappers and six context/startup
wrappers; allocator allocation/free/check fast paths stay unchanged.
[microdiff.json](microdiff.json) includes all function and loop counts;
[native-path-counts.json](native-path-counts.json) records both fast and slow
node/wrapper paths. A broader trial also changed Allocator.assertIsAllocated,
adding a frame without removing its saved registers. Requiring a returned
value excludes that void-report shape and restores its entire previous body.

DevMode compiler validation used fresh machine-load admission and six workers:

- `MSBuild swc.sln /t:Build /p:Configuration=DevMode /p:Platform=x64 /m:6
  /p:SwcCompileJobs=6`.
- `bin/swc.dm.exe --num-cores 6 tools/unittests.swgs dm cpp --num-cores 6`:
  all 1,430 existing C++ tests passed after narrowing the rule. After adding
  the boundary regression, `bin/swc.dm.exe unittest --num-cores 6` passed
  1,376 non-filesystem tests; the 55 filesystem cases already passed.
  The new test checks register class under C, Windows x64 and Swag conventions,
  including void and unconditional-entry counterexamples.
- `bin/swc.dm.exe --num-cores 6 tools/unittests.swgs dm native
  --file-filter guarded_call_result.swg --num-cores 6 --rebuild --print-micro '*'`:
  21 inputs; one test passed in JIT and native execution, including both
  reasons to take the slow lookup. Formatting is stable.
- `bin/swc.dm.exe build --workspace bin/unittests/workspace
  --workspace-module runtime_context_dynamic_dll --build-cfg devmode
  --num-cores 6 --rebuild`, followed by `test` on
  `runtime_context_dynamic_consumer` with the same options, `--no-test-jit`
  and `--run-arg --dynamic-runtime-library=<absolute DLL path>`:
  both tests passed. They cover fresh foreign threads, expanded TLS slots,
  context replacement and dynamic-module lifecycle/context sharing.
- All twelve unchanged Release benchmark sources rebuilt with
  `--num-cores 6 --rebuild --validate-micro`; checksums agree with the baseline.

The existing region scan is unchanged in asymptotic cost. The additional
checks use O(1) auxiliary storage and inspect leading-label predecessors
and address-taken labels: O(E + G*A) extra work for E inspected predecessor
edges, G candidate leading labels and A address-taken labels. The usual
case has no address-taken labels. A single binarytrees compile with Micro
printing used 352.7 to 274.4 ms wall time and 254.0 to 253.4 MiB peak job
commit; these diagnostic samples are not a compiler-performance claim.
