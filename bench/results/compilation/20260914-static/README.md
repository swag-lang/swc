# Static compilation work reductions, 2026-09-14

Work is isolated in `swc-perf-sept14` on `perf/compile-static-sept14`. Each completed
campaign is validated and merged into `master` before the next campaign starts.
Timing measurements are deferred at the owner's request. The work reductions below
are derived from the algorithms; they are not measured compilation-speed claims.

## Campaign 1: control-flow reconstruction and nested JIT metadata

### Static reductions

- Reuse successor and predecessor lists for surviving instruction positions across
  control-flow graph rebuilds. This avoids destroying and constructing every small
  vector and retains overflow capacity for large branches and joins.
- Retain the label-index vector across rebuilds. Reset its entries to the invalid
  sentinel so removed labels never retain an old instruction index.
- Deduplicate indirect-jump destinations from the target's last predecessor. Sources
  are visited monotonically and all edges from one source are appended together.
  Membership therefore takes constant time instead of searching the growing target list.

For the regression fixture's 32 distinct destinations followed by those destinations
in reverse, the old searches perform 496 + 528 = 1,024 target comparisons. The new path
performs 64 constant-time membership checks, with no additional index. Edge discovery
order and duplicate handling are preserved. Reused buffers belong to one MicroBuilder
and are released with its compiled-function state.

`MicroControlFlowGraph_RebuildsLargeBranchesAndRemovedLabels` covers an empty graph,
repeated reconstructions, large incoming and outgoing lists, duplicate destinations,
a removed label, shifted instruction indices, and return to an empty graph.

### Defect found during validation

The native `optimize_constexpr.swg` test failed in `devmode` on the original JIT
preparation path: `#isconstexpr(pureAdd(20, 22))` was false despite optimization being
enabled. The same file failed in isolation. A temporary trace identified unpublished
function relocations reached through `__runtimeAllocator`, a dependency of overflow
reporting. All probe instrumentation was removed.

The stability check follows the entire allocation-relocation graph, but JIT preparation
only followed direct function relocations and one struct-method table. Preparation now
follows every data relocation with an iterative worklist and shared allocation membership.
This includes nested reflection and interface tables, terminates on cycles, and retains
the existing exclusion of ignored functions and generic bodies still being analyzed.
The existing deferred-method reflection tests protect that exclusion.

The original regression passes with the correction. Its optimizer stage still reports
210 functions. Additional proposed reductions passed without the correction and were
removed; the existing native fixture is the demonstrated regression boundary.

### Validation

Candidate build 592, based on `4710bdd4c`, passed:

| Compiler | Program configuration | Boundary | Result |
| --- | --- | --- | --- |
| DevMode | n/a | C++ fast tests | 797 passed |
| DevMode | devmode | Complete JIT suite | 1,410 passed |
| DevMode | devmode | Complete native suite and recovery probes | 3,166 passed |
| DevMode | release | Complete native suite and recovery probes | 3,166 passed |
| Release | devmode | Complete JIT suite | 1,410 passed |
| Release | devmode | Native `optimize_constexpr.swg` | 1 passed |

Both compiler executables built successfully. All compiler commands used six workers;
MSBuild used `/m:6 /p:SwcCompileJobs=6`. Each build or test received a fresh machine-load
admission check. The C++ fast selection excludes filesystem tests. No full repository
campaign or performance benchmark was run.

The final integration incorporates `a0e214fd1` and increments the compiler to build 593.
Both integrated compilers built successfully. The integrated DevMode compiler passed the complete JIT suite (1,410 tests) and native devmode suite (3,166 tests plus recovery probes). The integrated Release compiler passed the native optimize_constexpr.swg regression (one test). Earlier independent C++ and native release evidence remains applicable.

## Campaign 2: constant-call metadata and argument preparation

The stability query now accepts all allocation roots of one argument or function-constant
check. It shares allocation membership and traversal buffers across those roots, scanning
their union once. Roots retain their original order, and the worklist holds only the current
graph frontier. Empty queries return before constructing traversal containers. No query state
persists across semantic pauses, JIT preparation, metadata publication, or compiler instances.

Known code relocations retain their shard/offset references instead of converting them to
pointers and rediscovering their storage through up to 16 shards. Unknown raw addresses still
use the existing resolver. Each caller collects a temporary root list; this replaces repeated
per-root traversal scratch and repeated visits to shared allocations.

`ConstantManager_ChecksSharedRelocationGraphsPerQuery` supplies 128 roots to a two-allocation
cycle spanning two shards, including an interior address. The old per-root traversal copies
256 relocation lists; the batched query copies two. The test then adds an unpublished function
relocation and checks that a new query finds it. A subsequent foreign-target update verifies
that the next query observes the changed eligibility. Empty roots and cycle termination are
covered as well.

Ordinary and receiver-setting constant-call preparation borrow immutable `ConstantValue`
objects from stable manager storage instead of copying them. No reference escapes argument
construction; JIT requests continue to own their materialized argument bytes. This removes
one object copy/destruction per inspected argument and a vector allocation/copy for each
non-empty aggregate argument. Ordinary call arity and unsupported-variadic checks also precede
payload allocation, avoiding that allocation for rejected shapes while retaining the same
checks on successful shapes.

### Validation

DevMode compiler build 594 succeeded. It passed the C++ fast tests (798 tests),
the complete JIT suite in devmode (1,410 tests), and native optimize_constexpr.swg
in devmode (one test, still 210 functions in the optimizer stage).
The implementation has no compiler-build-mode branch or new cross-phase state, so no new
Release compiler build is selected. No timing benchmark was run.

The build received the repository's full load admission. During validation, the owner explicitly
waived memory margins for the rest of this session. Later commands retain the same five-second
CPU sample, 65% CPU admission threshold, and six-worker limits. A temporary PowerShell launcher
initially treated native stderr output as a terminating script error; it was corrected to retain
that output and check the native exit status. The successful C++ run used the corrected launcher.

## Campaign 3: size register-index reserves by their actual role

`MicroDenseRegIndex::reserve` no longer reserves the sparse fallback map from the total
register hint. Ordinary registers use direct tables and never insert into that map. Its
exceptional path now grows with the sparse entries actually inserted. The standard library's
minimum empty-map storage remains; this change removes excess bucket reservations, not the
map's construction. Sparse inputs use the container's amortized growth instead of preallocating
for all registers, including those served by direct tables.

Register allocation also reserves its concrete-register list from the ABI's integer and float
pools plus stack/frame roles. The former hint was `2 * instructionCount + 8`. With the current
ABI and 10,000 instructions, the requested capacity drops from 20,008 `MicroReg` entries to 33
(80,032 versus 132 bytes of element storage). These are requested sizes from the source, not
measured allocations; a reused vector can retain a larger capacity.

`MicroDenseRegIndex_ReusesMixedDirectAndSparseRegisters` exercises overlapping indices across
integer/float and concrete/virtual kinds, reserved register roles, large sparse indices, duplicate
insertion, map growth, insertion-order lookup, bitset word counts, missing keys, and three
clear/reserve/reuse cycles. No per-index field, per-register branch, or lookup indirection is added.

### Validation

Candidate DevMode compiler build 595, based on dd4c85b05, succeeded. The C++ fast tests passed (799 tests), followed by
the complete native devmode suite (3,166 tests) and its expected recovery probes. Both
commands returned success. The new C++ fixture exercises the sparse path directly.
The memory-margin waiver remains in effect; each command retains fresh CPU admission and
six-worker limits. No timing benchmark or new Release compiler build is selected.

The first integration includes d2672787e and compiler build 596. The integrated DevMode
compiler built successfully and passed all 806 C++ fast tests plus the 20 native devmode
tests selected by --file-filter regalloc (regalloc_divmod.swg and regalloc_shift.swg).
The earlier complete native result remains applicable to the reserve changes.

A subsequent master integration includes e612280d7 and increments the compiler to build 600.
The integrated DevMode compiler built successfully and passed 817 C++ fast tests and the
same 20 native devmode register-allocation cases. The only merge conflict was the build number.
