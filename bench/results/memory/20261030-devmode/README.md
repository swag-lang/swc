# Compiler memory work, 2026-10-30

The objective is to reduce compiler memory and the DevMode/Release gap while giving
compilation speed priority. Changes with a static storage or work reduction are grouped;
builds and comparative measurements are periodic checkpoints, not a per-edit requirement.

## Debugger-only metadata

`SWC_DEBUG_MODE=1` now owns the metadata maintained only for interactive C++ inspection.
It is disabled by default in `src/pch.h` and can be enabled manually before rebuilding.
There is no additional MSBuild configuration, property or executable. Normal DevMode keeps
assertions, race detection, compiler validators, allocator checks and unit tests.

Static x64 layout consequences:

| Stored value | Previous DevMode | Normal DevMode after this change |
| --- | ---: | ---: |
| `StrongRef<T>` | 16 bytes | 4 bytes |
| `SourceCodeRef` | 32 bytes | 8 bytes |
| `Token` | 56 bytes | 12 bytes |

The reference pointer, token text pointer, token source pointer, full token location and AST
visitor inspection context remain available in debug mode. Default DevMode no longer computes
line/column positions on every token or refreshes the inspection location on AST traversal.
No lookup, packing, allocation or replacement side table is added to recover these saved bytes.
Compile-time size assertions protect the compact representations.

The AST visitor inspection test is registered only when its inspection fields exist. All
semantic traversal tests and the ordinary compiler checks remain enabled in DevMode.

The DevMode build passed the representation assertions. These are local representation savings,
not an accepted process-peak or compilation-speed result. The preserved pre-change
3.6.0 executables and frozen workloads from the
[integration report](../20261030-mimalloc360/README.md) provide the comparison checkpoint.

## Empty members and record padding

- `SmallVector` no longer reserves an aligned word for its empty `std::allocator` member.
  Its inline capacity, growth policy, object lifetimes and allocation calls are unchanged.
- `FlatKeyMap` uses the same attribute for its empty occupied-slot tracker when tracking is
  disabled. Tracking-enabled maps retain their vector and behavior.
- `ConstantKind` fits in one byte. Placing the borrowed-payload flag next to it eliminates
  eight padding bytes per `ConstantValue`: 56 to 48 bytes without debugger metadata, 72 to
  64 with it. Copy/move initialization order follows declaration order; kind values and hashes
  are unchanged.
- `DataSegmentRelocation` places its boolean next to its byte-sized kind: 32 to 24 bytes on
  x64. The function-relocation initializer follows the new member order. Serialized cache keys
  already encode individual fields, not this in-memory record.

The empty-member attribute chooses `msvc::no_unique_address` when supported, as the installed
MSVC STL does. Microsoft's [ABI explanation](https://devblogs.microsoft.com/cppblog/msvc-cpp20-and-the-std-cpp20-switch/#msvc-extensions-and-abi)
documents why the standard spelling alone does not enable this optimization in the MSVC ABI.
Other compilers use the standard attribute. These changes add no side table, indirection,
allocation, hash lookup or compaction pass; the storage savings apply to Release too.

## Constant graph cache ownership

The allocation-walk cache used to own its tables and copied relocations in thread-local
storage. Segment identities are unique, so entries from destroyed constant managers could
never hit again, but remained allocated until the worker exited.

Each `ConstantManager` now owns one table per calling thread. A trivial TLS shortcut retains
only the current owner's unique identity and a non-owning table pointer. Repeated lookups
take no registration lock. Switching between live managers finds the thread's existing table
without evicting its useful entries; destroying a manager destroys all its tables and payloads.
The identity check also distinguishes a new manager constructed at a previous owner's address.
External threads use the same ownership path and do not share a worker-index slot.

Within an owner, the full shard/offset pair forms the table key. This removes the segment ID
and repeated query offset from every entry (168 to 152 bytes on x64 after the preceding layout
changes). It also preserves the low offset bit: the previous composite key forced that bit to
one, so neighboring byte offsets could replace each other's entries despite the stable-entry
contract. Flat probing, table growth, version invalidation and stable deque addresses remain.

Three focused C++ regressions cover complete cache deallocation at owner destruction, reuse
of the owner's address, interleaved owners and neighboring offsets, and independent concurrent
threads. Existing relocation-graph and table-growth tests continue to exercise refreshes.
All 1,687 C++ tests passed with this batch, including the three ownership regressions.
This ownership change removes proven retained storage; its process-memory and timing effects
remain pending a clean grouped comparison.

## Validation checkpoint and allocator investigation

The first complete DevMode build succeeded. On the frozen `swagcapture` inputs, the original
3.6.0 DevMode compiler peaked at 2,494.84 MiB working set. The compact compiler's run emitted
a mimalloc error while destroying a CodeGen payload arena, despite exiting with code zero.
That run is invalid as performance evidence. The measurement harness now treats allocator
errors as failures independently of the exit code. A subsequent diagnostic executable with
guarded allocations completed without an allocator error; it is not a timing comparison.

Symbolization located the reported 544-byte block at `CodeGen`'s 512-byte payload arena plus
its block header. Static inspection found two relevant defects:

- A metadata lookup could allocate only `CodeGenNodePayload`, then specialized lowering
  reused it as a larger conditional, logical, optional-chain or assertion payload. Branch
  labels and stages are now separate small records in the existing auxiliary table, keyed
  by the original node; values remain keyed by the resolved substitute. Trivial auxiliary
  records use the job arena. Invalidation only touches already allocated value payloads.
  A C++ regression covers early metadata, substitution and independent branch state for all
  five types; compile-time checks forbid downcasting a value payload to a larger subtype.
- Mimalloc 3.6.0 could read an uninitialized `is_double_free` flag after detecting an overwritten
  padding byte with an intact canary. Its local diagnostic fix initializes that flag; overflow
  detection remains enabled. The vendor provenance document records the patch.

An intermediate attempt selected the full allocation from the resolved AST kind. Its normal
DevMode build and 1,615 fast C++ tests passed, but `swagcapture` failed an assertion placing a
branch label in `Core.Hash.hash32` at `value orelse ""`. The existing 27 null-coalescing native
tests passed with that binary. A standalone generic function passing `value orelse ""` to a
nullable byte-slice parameter reproduced the same assertion; it is now the
`null_coalescing_slice_argument.swg` native regression. This exposed the need to separate
control-flow identity from shared value identity. The revised separation and the layout batch
below now compile in DevMode, including both new size assertions. The reduced native regression
passes in JIT and native execution with the revised compiler after failing with the intermediate
allocation-by-node-kind compiler. All 1,615 fast C++ tests then passed, including the revised
state-isolation regression. A selection of seven native source files passed all 32 tests in
both JIT and native execution: slice-argument coalescing, conditional lifecycles, logical
operators, optional chains, inline optional guards and short-circuit cases.
No application gain or speed result is accepted from the failed runs.

## Subsequent layout batch

- `MicroRelocation::privateGlobal` fills the space beside its byte-sized kind and form,
  removing eight bytes from the normal x64 record (56 to 48). Its designated initializer
  follows declaration order; relocation values and encoding remain unchanged.
- `AttributeList::observesExternalBorrows` moves beside `backendOptimize`, occupying existing
  padding instead of interrupting the sequence of 64-bit masks. This saves eight bytes in
  each attribute list, including copies embedded in semantic frames.
- `SemaFrame` groups its five booleans into the access-header padding and places its 32-bit
  binding count beside the normal 32-bit inline-context reference. These fields keep their
  initializers; no packing pragma, bitfield, indirection or runtime decoding is introduced.
- `JobRecord` groups its priority, state and registration flags, reducing its x64 size from
  80 to 72 bytes in both compiler configurations. `CodeGenJob` places its three booleans beside
  the normal 32-bit root reference, removing another eight bytes per retained job. Scheduler
  counters and state transitions remain unchanged.
- `CodeGenLoweringPayload` groups its two array-fill references and moves the safety mask
  beside the wrapper token ID: 88 to 80 bytes on x64 without reference inspection metadata.
  Every value payload embeds these metadata too. A compile-time size check protects the layout.
- `NodePayload::SubstituteStorage` groups its two 16-bit fields: 20 to 16 bytes without
  reference inspection metadata. Its designated initializer follows the new order and a
  compile-time size check protects the compact record.

These storage-layout changes passed the grouped DevMode build. The early application runs and
the intermediate compiler's 1,615-test result do not describe this later batch.

## First clean DevMode application comparison

The corrected compiler rebuilt the frozen `swagcapture` workspace with no allocator error.
The runtime, standard-library and application snapshot was checked byte for byte again.
Both runs below report 592,024 tokens, 5,142 tuned functions and 2,411 forged functions for
the application. Both use six workers, `--rebuild`, isolated temporary/cache roots and the
default program `devmode` preset without `--debug`.

| Compiler | Peak working set | Wall time | Process CPU time |
| --- | ---: | ---: | ---: |
| Original 3.6.0 DevMode | 2,494.84 MiB | 123.24 s | 544.75 s |
| Memory changes and branch-state fix | 1,934.20 MiB | 83.51 s | 369.44 s |

This is a clean observed reduction of **560.64 MiB (22.47%)** for this workload. It is a first
comparison, not a statistical performance campaign. The shared host varies significantly:
the earlier allocator-integration campaign already included an 83.31-second run with the
original 3.6.0 compiler. Do not interpret the wall-time pair above as an established speedup.
The updated Release compiler also built successfully and passed the same 32 focused JIT/native
tests. Its clean frozen-application run peaked at 1,787.84 MiB (64.06 s wall, 265.36 s process
CPU). The observed DevMode excess is now 146.37 MiB, or 8.19%, on these first clean runs.

A later DevMode pair confirmed lower memory but raised an unresolved timing concern:

| Compiler | Peak working set | Wall time | Process CPU time |
| --- | ---: | ---: | ---: |
| Original 3.6.0 DevMode, repeated | 2,541.51 MiB | 74.95 s | 348.64 s |
| Memory changes and branch-state fix, repeated | 1,898.01 MiB | 152.38 s | 611.44 s |

Both runs completed cleanly with identical application token/function counts. The shared host
can affect wall and CPU time, but that does not establish the cause of this reversal. The batch
has **not** met the no-compilation-slowdown acceptance condition. A controlled timing comparison
and investigation of the changed cache and payload paths remain necessary before acceptance.

A diagnostic repeat pinned the compiler to the six performance cores and recorded host CPU
counters around the run. Admission sampled 13% CPU, but the host averaged 79.20% during the
199.12-second compilation; an estimated 2,875.98 CPU-seconds belonged to other processes,
against 593.20 CPU-seconds for the compiler job. The application completed without allocator
errors. This run is excluded from controlled timing comparisons. It demonstrates interference
in that repeat, but does not establish the cause of the earlier timing reversal. No baseline
repeat was started while the stricter 20% timing-admission threshold reported `wait`.

Commands, binary hashes, counters, test output and excluded failed runs are retained in
[measurements.json](measurements.json). The current compiler's source matches code revision
`3965e1b51`; its SHA-256 is `43755fc41b9709c32234b29c04c18bea9fe215274839ae939a58224f56fb9d57`.

## Common compiler layout batch, awaiting a grouped build

The next batch targets both compiler executables. These are x64 representation deductions,
not additional measured process-memory savings; the binaries above do not include them.

- `AstVisit::Frame` stores its four three-state callback flags in byte-sized enums: 48 to
  32 bytes without reference inspection metadata, saving 1,024 bytes in each visitor's
  64-entry inline stack. State transitions and stack capacity are unchanged.
- `TaskState` places the auto-scope reference in existing padding: 96 to 88 bytes without
  reference inspection metadata. Wait targets, diagnostics and state updates are unchanged.
- `CodeGenDeferredAction` groups its small tags and references: 40 to 32 bytes. Each
  `CodeGen` reserves 32 scopes with four inline actions each, saving another 1,024 bytes.
- `CodeGenTemporaryDrop` groups its references: 24 to 16 bytes; its positional initializer
  follows the new declaration order.
- `CodeGenFrame::InlineContext` groups pointers and references: 40 to 32 bytes. Moving the
  boundary reference into the surrounding frame's header padding reduces that frame from
  88 to 72 bytes.

All records retain their fields, defaults and natural alignment. No packing, bitfields,
side tables or allocation-policy changes are introduced. Compile-time size assertions guard
the normal x64 layouts at the next grouped build.

## Retained page-range indexes, awaiting a grouped build

`PagedStore` publishes and retains immutable page indexes for concurrent readers whenever a
page is added. Its address-range record used to store both the start address and the end of
the full page, as well as a pointer to the page whose live byte count bounds every valid lookup.
The end address is redundant: `upper_bound` already selects a start no greater than the query,
and the full-width address difference can be compared directly against the live byte count.

Removing the end address shrinks the x64 record from 32 to 24 bytes and removes the separate
full-page bounds branch. The normal lookup still subtracts the start and loads the live count;
it gains no allocation, lock, indirection or pass. The subtraction stays pointer-sized until
after validation, so an address more than 4 GiB away cannot wrap to a valid 32-bit offset.
A focused C++ regression covers live boundaries, unused tails, cleared pages and that distant
address case. It will run with the next grouped validation.

For a store that grows to N pages, the retained range arrays contain N(N+1)/2 entries. The
static saving is therefore 4N(N+1) bytes per store, excluding allocator rounding: 4.00 MiB
at 1,024 pages. This is a representation calculation, not a measured whole-compiler gain.
The quadratic snapshot-retention policy itself is unchanged and remains a separate lead.
