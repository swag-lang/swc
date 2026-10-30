# Compiler memory work, 2026-10-30

The current objective is to reduce memory common to both compiler configurations while giving
compilation speed priority. Changes with a static storage or work reduction are grouped;
builds and comparative measurements are periodic checkpoints, not a per-edit requirement.

The latest uninstrumented DevMode application observation is **1,443.543 MiB peak working set**
at compiler checkpoint `f484c97a40`, compared with **1,472.266 MiB** for its immediately
preceding compact-liveness control. This pair shows 28.723 MiB less resident memory; host-load
differences prevent speed acceptance. See [effects-cache.json](effects-cache.json). Release
validation of this latest batch remains pending; its last validated checkpoint is `8bcdc4259b`.

## Current occupation map and priorities

The AST alone does not explain the process footprint. The strongest measured waste so far is
constant-storage page rounding (fixed), followed by partially occupied allocator pages (an
external candidate saves 178.516 MiB). The live heap still needs a complete owner census.

| Measured storage | MiB | What this establishes |
| --- | ---: | --- |
| Live allocator blocks at the latest highest captured RSS point | 909.603 | Rounded block occupancy, including allocator padding |
| Free slots in those same allocator pages | 369.187 | Retention/fragmentation; not necessarily immediately reclaimable |
| AST backing, independent maximum | 85.672 | Identified pages only; excludes ordinary containers and ambiguous stacks |
| Sema node-payload backing, independent maximum | 50.078 | Node records only; not all semantic analysis |
| Mixed object/string arenas, independent maximum | 171.205 | Symbols, codegen payloads and strings still share this category |
| Register-allocation buffers, sum of independent instance maxima | 161.969 | Includes 115.062 MiB of virtual liveness matrices; not a simultaneous peak |

The last four rows come from separate diagnostic runs. They overlap the first row and must not
be summed with it, or subtracted from it to manufacture an unexplained remainder. The highest
captured RSS point in the latest run is 1,448.344 MiB; the actual process peak between snapshots
is 1,515.418 MiB.
Page capacity and OS residency measure different things.

In the preceding heap-only census, at its highest captured RSS point, the disjoint live-block
size ranges are 166.000 MiB up to 1 KiB,
110.961 MiB from 1 to 16 KiB, 355.219 MiB from 16 to 64 KiB, 99.266 MiB from 64 to 512 KiB,
and 290.500 MiB above 512 KiB. Thus 744.985 MiB lies above 16 KiB. These are allocator size
classes, not ownership: for example, the 20 KiB class alone holds 177.910 MiB, but its size does
not prove that every block is a PagedStore page.

The new [large-allocation census](large-allocation-census.json) follows every C++ allocation
whose usable size is at least 16 KiB. At the latest highest captured RSS point, the disjoint
requested-byte attribution is:

| Allocation owner or entry point | MiB |
| --- | ---: |
| Backend register allocation | 157.679 |
| Mixed object/string arenas | 149.927 |
| AST and parsing, including AST cloning | 94.676 |
| Other microcode analyses and optimization | 78.343 |
| Sema analysis and node payloads | 44.952 |
| Linker and object/archive I/O | 34.575 |
| Compiler artifact caches | 26.128 |
| Native emission | 25.281 |
| Source text and tokens | 17.643 |
| Sema AST handlers with inlined storage | 9.641 |
| Constants | 9.108 |
| Symbols and identifiers | 6.861 |
| Types | 5.141 |
| Orchestration | 2.385 |
| Codegen | 0.137 |
| Unattributed traced allocation | 0.071 |
| **Simultaneous traced requested bytes** | **662.548** |

The 827,939 allocation/free/snapshot events have consecutive sequence numbers, no duplicate live
pointer, no missing free, stable usable sizes and no remaining tracked allocation at exit. The
trace matches the exact binary and linker map, resolving the incremental-link address thunk.
There are 29 synchronized heap snapshots. The backend excluding linker owns 261.440 MiB of
these large allocations at this point; sema categories own 75.703 MiB. These are lower bounds on
their storage, not complete component totals. In particular, arena contents remain mixed and
small heap allocations are outside the trace. The 909.603 minus 662.548 MiB difference combines
untraced allocations and allocator rounding; it is not a clean small-allocation total.

The largest simultaneous traced requested total is 753.346 MiB at a different observation: the
linker then owns 111.198 MiB, native emission 35.639 MiB and register allocation 157.679 MiB.
This is a trace peak, not the RSS peak. The register-allocation total confirms the earlier
container census without adding independent worker maxima. Two uint64 vector allocation stacks
in `analyzeLiveness` account for 115.072 MiB at the synchronized RSS observation.
Among the other microcode analyses, `computePhysicalLiveness` owns 20.741 MiB. The exact
allocation stacks and aggregation by owning function are retained in the census artifact.

The next work follows the measured owners:

1. Complete controlled timing validation of compact acyclic liveness storage and the effects/cache
   batch. Compact rows observed 36.781–64.969 MiB less working set than two dense-baseline runs;
   the latest effects/cache pair observes another 28.723 MiB reduction. These are not additive
   controlled guarantees. Cyclic matrices
   remain dense; discarding all reusable worker buffers is not an established speed-preserving solution.
2. Inspect the other retained microcode analyses (78.343 MiB), then linker peak buffers. Use the
   captured owning stacks to choose concrete containers and preserve useful reuse.
3. Use the typed-arena census below to prioritize attribute lists, function/variable symbols and
   inline payloads, then count small sema containers. Preserve direct
   allocator calls, OS mappings and ambiguous inlined storage as explicit measurement limits.
4. Finish the large-page candidate's timing and output-equivalence checks, then group Release
   validation. Its 11.94% observed memory saving is not yet an accepted default change.

The diagnostic build and frozen application rebuild pass. All instrumentation and normal
compiler outputs were restored; diagnostic files and preserved binaries stay outside the
checkout. No compiler timing claim comes from this instrumented run.

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

## Common compiler layout batch

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
the normal x64 layouts; they passed the grouped DevMode build described below.

## Retained page-range indexes

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
address case. It passed with the grouped DevMode validation described below.

For a store that grows to N pages, the retained range arrays contain N(N+1)/2 entries. The
static saving is therefore 4N(N+1) bytes per store, excluding allocator rounding: 4.00 MiB
at 1,024 pages. This is a representation calculation, not a measured whole-compiler gain.
The address-sorted range snapshots still retain a quadratic number of entries; the direct
page-number index is addressed separately below.

## Geometric direct page tables

The direct page-number index previously retained a full vector copy for every new page too.
It now publishes fixed-capacity arrays of atomic page pointers, doubling capacity when needed.
A new page fills one previously unused slot and then publishes the count. Existing slots are
never rewritten, and old tables stay owned by the store so concurrent readers keep valid data.
The address-sorted range index and its binary search are unchanged by this step.

The direct pointer arrays now retain fewer than four slots per page, instead of N(N+1)/2
slots for N pages. At 1,024 pages the pointer arrays use 16,376 bytes instead of 4,198,400 bytes,
excluding table objects and allocator rounding. Growing within capacity also eliminates a
table allocation, an array allocation and the copy of all existing page pointers.

Lookups still index one contiguous array without locking. Pointer slots use acquire loads;
the generated x64 path uses no locked operation or fence. Each lookup retains its loaded
page pointer locally. Iteration captures the published count once rather than following a
count that may grow concurrently. Move construction, move assignment and clear retain the
existing storage and reference contracts.

A new C++ regression runs two readers while a writer publishes 256 full pages, checking old
and new references, values and reverse lookup. It also moves the grown store and reuses the
moved-from store. The grouped DevMode build succeeded, including this change, the range-boundary
regression and the preceding common layout batch. All 1,617 fast C++ tests passed with no allocator
error, including both new page-store regressions. The compiler code is `ecb64e0f2e`; the preserved
DevMode executable has SHA-256 `f085648aeea0f185c7212ae1cb4d226874e2617ed59ede6f137b8d4b4ecd33ed`.
The Release build also succeeded. A subsequent link-only invocation emitted a map for later
heap-profile symbolization; it did not recompile sources or introduce a build configuration.
The preserved Release executable has SHA-256
`0ecd72a7b7f813e02c7e8ceb8237ff94239a8b7ad3c602ecd8ef184fad768ffb`.

[The before/after x64 assembly](paged-store-get.asm) of `ConstantManager::get` shows the
direct-page path falling from 31 to 26 non-NOP instructions, including prologue and return.
Keeping the page pointer locally removes two redundant memory reads. The large-block fallback
is unchanged. This verifies that representative hot access, not whole-compilation speed.
Whole-compilation timing comparisons for this checkpoint remain pending.

## First common-memory Release application observation

The new Release compiler completed the frozen application with no allocator error. Tracked
runtime, standard-library and application sources were checked byte for byte again before the
run. Both Release observations report 592,047 application tokens, 5,143 tuned functions and
2,411 forged functions, with six workers, `--rebuild`, isolated temporary roots and the
default program `devmode` preset without `--debug`.

| Release compiler | Peak working set | Peak private bytes | Wall time | Process CPU time |
| --- | ---: | ---: | ---: | ---: |
| Previous control checkpoint | 1,787.84 MiB | 1,815.08 MiB | 64.06 s | 265.36 s |
| Common layout and page-index batch | 1,658.96 MiB | 1,684.70 MiB | 217.48 s | 412.00 s |

This is an observed reduction of **128.88 MiB (7.21%)** in peak working set and **7.18%**
in peak private bytes. It is one application observation, not an established statistical gain:
the earlier run used default CPU affinity, while the new run used six performance cores.
Repeat the baseline with the same affinity before accepting the controlled comparison.

The new run started after a 9% CPU admission sample, but host utilization averaged 82.76%
over the compilation. Other processes used an estimated 3,532.58 CPU-seconds during its
217.48 seconds, against 412.03 CPU-seconds for the compiler job. Exclude this run from
compilation-speed conclusions. The new DevMode application's peak has not yet been measured;
do not combine the older DevMode result with this Release result to claim a new configuration gap.

## Omit unused reverse indexes

Static call-site inspection found that only AST storage and `DataSegment` use
`PagedStore::findRef` in production. Type records, identifier records, identifier strings,
node payload records and encoder bytes are accessed through stored references or direct
pointers. Their five store declarations now disable reverse lookup at construction.
The default remains enabled for existing consumers; AST and `DataSegment` are unchanged.

Disabled stores publish the same direct page table but skip all sorted range snapshots.
This eliminates N(N+1)/2 retained 24-byte range records for N pages, or 12N(N+1) bytes:
12.01 MiB at 1,024 pages, before vector objects and allocator overhead. It also removes
the repeated allocation, population and sort. The policy occupies existing x64 padding;
direct reference access and ordinary allocation within a page gain no branch or indirection.
The policy check runs only when publishing a new page table. Both compiler configurations
use the same change.

Move construction carries the policy; move assignment swaps it with the storage. A focused
C++ regression covers reference and pointer stability over growth, both move operations,
reuse and clear, including reverse lookup on the enabled store exchanged by assignment.
The new regression passed the grouped validation of revision `cc9549202b` described below.
Neither the measurements above nor the frozen `swc.pages` binaries include this batch.

## Sampled allocation profile

The frozen Release checkpoint `ecb64e0f2e` completed an opt-in mimalloc heap-profile run
without allocator errors. It used the normal repository admission threshold (65%, sampled
23% before launch); the stricter 20% threshold is reserved for timing comparisons. The
tracked frozen inputs still matched the worktree byte for byte after the run.

Profiling sampled every 512 KiB on average and wrote snapshots at 128 MiB in-use intervals.
The largest captured raw sampled heap was 513.12 MiB. This is neither the total process
peak nor necessarily the exact heap peak: non-mimalloc mappings are outside this profile,
and threshold snapshots are discrete. The run's process working set peaked at 1,722.76 MiB,
including profiler overhead. Its 72.39-second wall time is excluded from speed comparisons.

Inclusive raw allocation-stack samples in that snapshot include 114.90 MiB under register
liveness analysis and 86.63 MiB under archive-file reads. These totals overlap their callers
and must not be added to them. Symbolization uses the matching linker map and loaded image
base; folded-function aliases are preserved. [heap-profile.json](heap-profile.json) records
the hashes, snapshot sizes, leading allocation stacks and raw process measurement. These
observations guide the next investigations; they do not quantify a gain from subsequent edits.

## Release sparse worker maps when requested

`FlatKeyMap::clear` already selected large, sparsely reused tables for release, but used
`slots_ = {}`. The installed MSVC vector implementation resolves this to initializer-list
assignment, which destroys elements while retaining capacity. An empty-vector swap now
actually releases the allocation in this existing branch, matching the occupied-slot tracker's
existing release path. The ordinary retained-capacity path is unchanged.

Previously, the next insertion saw an empty vector and allocated a new initial table anyway;
rehashing then destroyed the retained old buffer. The change brings that same deallocation
forward to clear, without adding a reallocation on reuse. Existing tracked and untracked
large/small-fill tests cover the lookup/refill behavior and passed the grouped validation below.

## Compact register-allocation records

Inspection of the profiled register-allocation path found padding between fields of its
per-register state. Grouping the wide fields and the small tags reduces normal x64
`VRegState` from 136 to 112 bytes. Moving `PendingInsert::hasRelocation` into header padding
reduces that queued record from 192 to 184 bytes. All fields, default values, capacities and
algorithms remain; no packing, decoding or additional lookup is introduced.

Compile-time size assertions guard these layouts and passed both grouped compiler builds.
Application measurements for this batch are separate from those of the preceding checkpoint.

## Map linker archives instead of copying entire files

The archive-loading stacks in the profile led to `loadArchiveItem`, which read every candidate
library into a separate heap buffer before decoding its symbol directory. `Archive::loadFile`
now uses the existing `Os::ReadOnlyFileMapping` owner and `ByteView` reader. Only directory and
selected object bytes need to become resident; no whole-file heap copy is allocated on the
mapped path. If mapping is unavailable, the existing file-read path remains available.
Archives generated in memory keep their owned `ByteArray` path.

The archive owns its mapping until the borrowed symbol names and member spans are no longer
needed. Move operations carry that owner and view together without allocating a replacement
symbol table, and clear the moved-from byte view. Library and incremental-cache publication
use the existing mapped-file replacement policy so another linker can retain the old generation
without forcing a two-second scanner retry.

A filesystem regression checks that returned member bytes are actually mapped, survive archive
moves and file replacement, and decode the correct old/new imports. It also covers reloading
between mapped and owned storage, missing files, malformed archives and the empty-file fallback.
Both compiler builds succeeded at revision `cc9549202b`. All 1,692 DevMode C++ tests passed
with `unittest --dev-full --num-cores 6`, including the filesystem regression and the preceding
page-store and map tests, with no mimalloc error. The executable hashes are:

- DevMode: `3c25a7753e6c9dbfcb87527f339f617464ce33ee857f247ca65942d4d833f7de`
- Release: `adfef54e3b0f715075e9fab72f65e10c1ddd818dcf81dda55d50086d542f9acf`

The real linked application also completed without allocator errors on the same frozen inputs.
Its peak working set was 1,684.43 MiB and peak private bytes 1,705.49 MiB: **25.48 MiB more**
resident memory than the preceding `pages-release-app` observation. This does not establish an
additional whole-process gain. Application counts remained 592,047 tokens, 5,143 tuned functions
and 2,411 forged functions. Despite an 8% CPU admission sample, host utilization averaged 76.00%;
the 186.51-second wall time is excluded from speed conclusions. Timing remains a separate controlled
comparison; avoiding file copies is not by itself a measured speed result. The measurement
harness now checks the effective process affinity before starting execution and records its own
source hash. Earlier pinned observations recorded the requested mask without that readback.

## Prepared linker follow-up, not yet validated

The source tree also contains a subsequent batch, excluded from all binaries and measurements
above. It is set aside while component-level memory accounting takes priority.

- `CoffInputReloc` groups its offset/type before the string: 48 to 40 bytes on normal x64.
- `LinkReloc` groups offset/kind and keeps its write-only section index behind the existing
  manual `SWC_DEBUG_MODE` switch: 56 to 48 bytes normally. Production access already carries
  the containing section; inspection builds still populate the index.
- COFF merging transfers the first section buffer into an empty image section and releases
  consumed source bytes and relocation arrays after subsequent appends. Definition names remain
  alive for the merge's borrowed-name index. A regression covers buffer ownership, append alignment,
  rebased relocations, BSS and first-definition-wins semantics.

Only static call-site/lifetime review, formatting and diff checks have been performed for this
follow-up. No new build or timing result is attributed to it.

## Component occupation: initial sampled evidence

The user requested a component-level occupation plan before further optimization. Every live
allocation stack in the four existing snapshots is now attributed once, to the nearest recognized
compiler owner beyond generic containers. This avoids adding overlapping inclusive stack totals.
Anonymous archive-loading jobs belong to the linker; their job-scheduler callers are not owners.
Folded code with conflicting owners remains unattributed. The detailed data is in
[component-occupation.json](component-occupation.json).

| Component | Snapshot 1 | Snapshot 2 | Snapshot 3 | Snapshot 4 |
| --- | ---: | ---: | ---: | ---: |
| Backend | 133.21 MiB | 205.05 MiB | 297.57 MiB | 236.29 MiB |
| Linker and archive/object I/O | 0 MiB | 0 MiB | 2.50 MiB | 192.42 MiB |
| Sema, symbols, types and constants | 14.10 MiB | 29.82 MiB | 51.36 MiB | 41.42 MiB |
| Compiler artifact caches | 8.82 MiB | 11.09 MiB | 22.80 MiB | 34.64 MiB |
| AST and parsing | 4.56 MiB | 7.08 MiB | 9.74 MiB | 4.44 MiB |
| Source text and tokens | 1.77 MiB | 3.70 MiB | 5.16 MiB | 2.95 MiB |
| Orchestration and unattributed | 0.99 MiB | 0.96 MiB | 1.25 MiB | 0.97 MiB |
| Total sampled live heap | 163.45 MiB | 257.69 MiB | 390.38 MiB | 513.12 MiB |

These are raw sampled allocation bytes for `ecb64e0f2e`, not estimates of each component's total,
whole-process totals or exact phase peaks. Mimalloc's text profile records requested bytes of
sampled allocations without inverse-probability weighting (`profile/pprof.c`, `on_alloc` and
`mi_pprof_snapshot_text`). Small allocations are especially underrepresented; the component
ratios must not be interpreted as a complete occupation plan.
The snapshots were triggered by heap growth, so a short parsing peak could fall between them.
At snapshot 4, register allocation accounts for 145.15 MiB, including about 114.75 MiB attributed
directly to liveness analysis; other micro passes account for 78.56 MiB. Backend and linker
therefore dominate the captured live allocations, while AST size is not established as a primary
target by this evidence.

## Process accounting and occupation plan

A second diagnostic run of the same frozen `ecb64e0f2e` Release binary collected 40 heap snapshots
and 36 successful Windows memory snapshots. The compiler completed the application with no allocator
error. Its process peak working set was 1,711.21 MiB; the largest captured resident-page set was
1,647.00 MiB, or 96.25% of that high-water mark. This is a near-peak observation, not an exact
atomic peak census. The external observer does not suspend or inject code into the compiler.
One read raced process exit and failed; it is retained separately. The wrapper also encountered
a console-encoding error while displaying the already-saved successful result, after the compiler
had exited. Neither error is reported as a compiler failure.

[occupation-accounting.json](occupation-accounting.json) contains the measurement, allocation
regions at the largest captured resident set, timestamped series, heap-owner breakdowns and
module output events. The Windows classification uses
[VirtualQueryEx](https://learn.microsoft.com/en-us/windows/win32/api/memoryapi/nf-memoryapi-virtualqueryex)
and [QueryWorkingSet](https://learn.microsoft.com/en-us/windows/win32/api/psapi/nf-psapi-queryworkingset).
Mimalloc arena addresses are read from the matching binary's mapped `mi_process_subproc_main`,
with owner/index and statistics-version checks. The allocation stack maps and binary hashes
are preserved. Profiling and observer costs exclude this run from compilation-speed comparisons.

| Resident memory at largest captured snapshot | MiB |
| --- | ---: |
| Mimalloc arenas | 1,205.28 |
| Compiler JIT/proximity arena | 417.82 |
| Executable and DLL images | 18.56 |
| Other private regions, including stacks | 4.57 |
| Mapped files and other mapped sections | 0.75 |
| Total | 1,647.00 |

Every queried resident page in this snapshot was assigned to one region. Region queries and
working-set queries are sequential rather than atomic; this capture took 6.85 seconds on the busy
host. Reserved-but-uncommitted address space is excluded from the resident total.

The proximity reservation was independently verified against the live compiler's actual
`g_proximityArena.base`, using the matching linker map and the verified process executable.
It held **418.06 MiB committed: 9.23 MiB executable/read-only and 408.83 MiB read/write**.
This owner serves JIT allocations, mutable global data, **and ConstantManager shard storage**.
Constant payloads and canonical constant records are therefore absent from the mimalloc heap
breakdown below. Protection alone cannot assign all read/write bytes to one component:
unfinished code allocations and unused block tails must also be distinguished.
The generated DLLs have only tens of KiB of `.data`/`.bss`, which does
not explain that amount of compile-time storage; native dead-data selection and compile-time
allocation lifetime differ, so this is a lead rather than proof of waste.

The nearest heap snapshot was written 0.63 seconds before the start of that Windows capture:

| Sampled live allocation owner near the captured process peak | MiB |
| --- | ---: |
| Backend | 305.47 |
| Sema, symbols, types and constant metadata (mimalloc only) | 53.77 |
| Compiler artifact caches | 24.38 |
| AST and parsing | 11.06 |
| Sources and tokens | 5.84 |
| Orchestration | 1.21 |
| Linker | 1.18 |
| Total sampled live heap | about 403 |

These allocations are **inside**, not additional to, mimalloc's arenas. The roughly 800 MiB
difference is **not a fragmentation estimate**: the text profile omits unsampled live allocations
and does not extrapolate them. Full live-object accounting is needed before separating retained
free pages, partially occupied pages, size rounding and profiler metadata. The observations are
also non-atomic. Subprocess `allocated` counters alone are not a
live-allocation total: active heap/thread statistics have not been aggregated into them.

Across all 40 snapshots, independent sampled component maxima were 311.85 MiB for the backend,
183.48 MiB for the linker, 53.77 MiB for sema and its records, 36.28 MiB for artifact caches,
and 11.06 MiB for AST/parsing. These occur at different times and must not be added. One profile
header differed from its summed stack rows by 1,031 bytes; the report retains that discrepancy
and uses summed rows for its disjoint owner totals.

The occupation plan now prioritizes the measured dominant owners:

1. **Reconcile mimalloc occupancy:** distinguish live objects, partially occupied pages and
   retained free capacity, then attribute retained capacity to the phases that grew it. Do not
   add blanket collection or decommit policies that could repeatedly fault hot memory back in.
2. **Explain the 408.83 MiB read/write proximity region:** attribute committed bytes and useful
    bytes to constant shards, JIT blocks, global-zero and global-initialized storage, with their
    owning module and lifetime. DataSegment permanently switches to individual allocations after
    its first allocation larger than 16 KiB; each subsequent proximity allocation rounds to at
    least 4 KiB. Quantify that padding before changing allocation policy.
3. **Backend retained analyses:** prioritize register liveness (about 113 MiB in the nearest
   snapshot), SSA, physical-liveness and native-section buffers. Separate useful size from
   retained capacity before changing algorithms; preserve direct accesses and scratch reuse
   where they save compilation time.
4. **Linker peaks:** investigate overlapping archive/object/image ownership, using the existing
   mapped-archive checkpoint and the set-aside consumption patch. Treat its peak separately from
   earlier sema/backend peaks.
5. **AST and heap-only sema layouts:** lower priority than the unaccounted constant storage and
   allocator occupancy. The small raw sema sample is not its total memory footprint.

No further micro-optimization build is scheduled until this occupation analysis identifies the
largest practical reduction. Any retained implementation still needs a grouped speed comparison
on stable host load; no whole-compilation speed acceptance has been claimed.

## Constant storage: identified page-rounding waste

A shutdown-only diagnostic reconstructed DataSegment storage from its allocation records on the
same frozen application sources. The Release diagnostic built successfully, and the application
completed without allocator errors. Its binary SHA-256 is
`0caa6f5a70e95d7477cf69ca88cb423a1be9437b89916616f6028fd708fda978`.
It includes `7a00a18050` but precedes the packing fix described below. Its time is excluded from
speed comparisons. [segment-storage.json](segment-storage.json) retains the command, output,
counts and grouping; [segment-profile-before.patch](segment-profile-before.patch) preserves the
probe against `7829b67d16`. The probe was enabled with a source-local `SWC_MEMORY_PROFILE=1`
after the PCH include, copied outside the checkout, then removed. No build configuration changed.

| Constant segments at destruction of the main module instance | Useful payload MiB | Rounded storage MiB | Difference MiB |
| --- | ---: | ---: | ---: |
| Gui | 16.223 | 339.746 | 323.523 |
| Swagcapture | 3.707 | 125.344 | 121.636 |

These are separate instance-end observations, **not additive process peaks**. The module-wide
totals including setup instances are 340.074 MiB and 125.672 MiB respectively. Gui made 83,716
individual blocks smaller than 4 KiB after large allocations; Swagcapture made 31,475. Mutable
global segments are small (tens of KiB each). Rounded storage follows the actual pre-fix policy,
assuming successful proximity allocations and Windows 4 KiB OS pages; it is not a resident-page
measurement and does not include segment metadata.

The root cause is `DataSegment::allocateStorageLocked`: one allocation above the 16 KiB page
size permanently ends paged allocation, and every subsequent value gets an individual block.
For proximity storage this commits at least 4 KiB even for a small constant record. This explains
a major part of the previously unattributed read/write proximity storage.

The fix in `28b98a8f8e` packs subsequent small values into 16 KiB blocks. It keeps existing pointers,
monotonic logical offsets, separate allocation records and the existing locking protocol.
Alignment gaps are zeroed for offset-preserving copies. Normal paged-only segments keep their
existing allocation and lookup paths. Packing also removes OS allocation calls and block-index
entries; it does not introduce collection, compaction or repeated page faults.

Validation selected for this substantive change: DevMode C++ tests for packed allocation,
pointer stability, reverse lookup, alignment, zeroing, copy/restore and block rollover, followed
by the same linked application with the rebuilt DevMode compiler. A Release rebuild/comparison
is deferred to the next grouped campaign rather than immediately repeating the long common-header
rebuild. Full mimalloc live-object accounting remains necessary;
the raw sampled component table above cannot replace it.

The DevMode build completed successfully. `unittest --num-cores 6` passed **1,620 tests**,
including the new packed-storage regression and the previously unbuilt COFF-consumption tests.
This is the ordinary C++ campaign, not `--dev-full`. The linked application also completed with
no allocator error. [packed-checkpoint.json](packed-checkpoint.json) preserves both results and
the frozen compiler SHA-256 `70acd323b7d3e0f116ac5c59c824362f9e98ca5c43b3e5eff4424cb6c1beaf46`.

The new application peak is **1,517.97 MiB resident** and **1,522.97 MiB private**. Historical
DevMode observations were 1,934.20 MiB at `3965e1b51` and 2,494.84 MiB at the original mimalloc
3.6.0 checkpoint: observed differences of **416.23 MiB (21.52%)** and **976.87 MiB (39.16%)**.
These are cumulative historical comparisons, not an isolated A/B result for the packing fix.
The new run is pinned and verifies its mask; the historical runs used default affinity. It
reports 592,047 tokens and 5,143 tuned functions versus 592,024/5,142 in those older DevMode
outputs, so repeat a preserved baseline on the current frozen input before a controlled claim.
All runs report 2,411 forged functions.

The run took 206.44 seconds wall and 787.66 seconds process CPU while the host averaged 77.14%
busy. Both are materially above the historical control (83.51 seconds wall, 369.44 seconds CPU).
Host contention and differing affinity prevent attributing the difference, but do not prove it
harmless: **compilation-speed acceptance remains open**. Next compare the preserved immediate
pre-packing DevMode checkpoint and this binary under the same verified affinity and stable host
load; investigate any surviving regression before accepting the optimization as complete.

### Complete census still required

The next diagnostic must count owned storage directly, without interpreting raw sample ratios as
component ratios. Record useful bytes, retained capacity and allocator/OS-rounded storage
separately, with module, phase and worker identity. Deduplicate shared backing allocations.

| Owner | Storage to count | Useful observation points |
| --- | --- | --- |
| AST/parser | All Ast shard pages, spans, page tables and reverse indexes | End of parse, sema and module API export |
| Sema | NodePayload, types and identifiers; symbol/thread arenas; nested vector/map capacities; constant segments | End of sema and before module destruction |
| Backend | Per-worker register-liveness matrices, SSA and other retained pass buffers; emitted code and relocation buffers | Scratch growth and function completion, retaining each worker's high-water owner |
| Linker/caches | Archive mappings, extracted members, parsed objects, merged sections, final image and cached copies | Archive load, merge and image publication |
| Allocator/OS | Aggregated heap/thread stats, page occupancy, committed and resident regions | Alongside component snapshots and near the process high-water mark |

`MicroBuilder::runPasses` keeps a thread-local pipeline, so backend scratch capacity survives
individual functions and module instances. A large buffer can therefore be retained reuse rather
than currently needed liveness. Preserve that distinction before proposing release policies.
Mimalloc statistics are periodically merged; include active thread heaps and account for pending
page statistics instead of treating an exclusive subprocess counter as the live total.

### Repeated immediate baseline with verified affinity

The preserved `cc9549202b` DevMode binary completed a fresh rebuild of the same frozen application
with the same six-worker command, verified affinity mask and measurement-harness hash as the
packed binary. [packed-pair-observations.json](packed-pair-observations.json) retains both runs.
The earlier checkpoint reached **1,873.27 MiB resident**, versus **1,517.97 MiB** for the packed
checkpoint: **355.30 MiB (18.97%) lower**. Private memory was 18.45% lower. This pair also includes
the intervening COFF-consumption change, so it does not isolate DataSegment alone.

The immediate baseline took 267.13 seconds wall and 909.53 seconds CPU, versus 206.44/787.66 for
the packed binary. Both hosts averaged about 77% busy, with large differences in where module
time accumulated. The lower observed times do not establish a controlled speedup or dismiss the
earlier historical slowdown. Further timed repetitions require stable low external load.

The immediate baseline reproduced 592,024 tokens and 5,142 tuned application functions; the
packed binary produced 592,047/5,143. The tracked inputs match. The subsequent diagnostic run's
published generated `.swg` API files are byte-for-byte identical to the baseline. Ten worker
`.swgsrc` dumps differ; after grouping complete generated blocks by module and ignoring worker
order, three removed and two added blocks remain. They concern generated hash calls and array
division. These dumps are not proven exhaustive generated-program captures, and the counter
difference is still unexplained; it is not dismissed as mere worker redistribution.

### Exhaustive backing-storage trace after packing

[storage-census.json](storage-census.json) records 777,580 consecutive allocation/free events with
no missing free, duplicate live pointer or unfreed block. The temporary diagnostic instrumented
PagedStore page backing, DataSegment large blocks and Arena blocks in three translation units.
It built and ran successfully; all probe source/project changes and normal binaries were restored.
There is no new build configuration or executable in the checkout. Diagnostic timing is excluded.

| Owner | At maximum traced capacity (MiB) | Independent maximum (MiB) |
| --- | ---: | ---: |
| Mixed compiler object/string arenas | 171.205 | 171.205 |
| AST pages identified by stack/owner | 84.203 | 85.672 |
| Sema node-payload pages | 24.297 | 50.078 |
| Paged storage without decisive owner evidence | 20.078 | 48.141 |
| Constant pages and large blocks | 16.728 | 17.009 |
| Identifier pages | 3.250 | 3.250 |
| Type pages | 2.406 | 2.422 |
| **Simultaneous traced total** | **322.167** | **Do not sum independent peaks** |

These are requested backing capacities, not useful bytes or resident memory. The maximum traced
capacity is not necessarily the process peak. Inlined AST allocation paths can remain in the
unattributed page row, so the identified AST row is a lower bound on AST backing. Arena blocks
are deliberately not assigned to the object that happened to trigger block growth: each can
contain symbols, codegen payloads, strings and finalizers from several call sites. Ordinary
vectors/maps, page metadata, allocator overhead, stacks and mappings are outside this census.

At the traced maximum, heap backing accounts for 305.392 MiB and proximity backing for 16.774 MiB.
The latter records actual allocation origin, unlike the earlier reconstructed pre-packing page
rounding. It supports the diagnosis of the constant-allocation policy, but is not a simultaneous
before/after resident-memory comparison. Next count retained backend containers directly,
especially register-allocation liveness matrices and nested per-instruction vectors, then
reconcile ordinary heap allocations and allocator occupancy with process memory.

The arena blocks alive at the traced peak eventually used 167.324 MiB out of 171.205 MiB
requested. This is their end-of-lifetime occupancy, not simultaneous useful bytes at the peak;
it includes alignment and finalizers. It argues against simply shrinking arena blocks as the
next large reduction. The AST blocks similarly eventually used 77.127 MiB of 84.203 MiB.

### Register-allocation container census

[backend-census.json](backend-census.json) records a second successful diagnostic application
build, with 24,056 retained-capacity-change observations and seven pass/thread identities.
One temporary translation-unit patch reads 58 member containers, two public dense-register
lists and nested vector/SmallVector storage. Inline payload is counted once through its parent
object; it is not counted again as external storage. The diagnostic compiler was copied outside
the checkout, and the source and normal binary restored. Its timing is not a benchmark.

| Register-allocation buffers | Sum at independent pass maxima (MiB) |
| --- | ---: |
| Virtual-register live-in bit matrices | 115.062 |
| Instruction use/def descriptors | 12.713 |
| Four per-instruction dense-index lists | 20.043 |
| Virtual-register states | 4.206 |
| Other traced containers | 9.945 |
| **Total** | **161.969** |

Individual pass maxima range from 0.085 to 63.151 MiB. **The sum is not a simultaneous process
peak**: these are independent observations; pass destruction and address reuse are not traced.
Private dense-index tables, FlatKeyMap storage, temporary locals, other optimizer passes, emitted
code, linker buffers and allocator rounding are excluded. Do not add this table to the earlier
backing census or subtract the sum from a process peak: they come from separate runs and times.

One late observed function has 27 instructions and three virtual registers, while its worker
still owns 24.929 MiB of traced capacity, including 17.763 MiB for virtual liveness. The current
matrix representation stores `instructionCount * ceil(virtualRegisters / 64)` 64-bit words;
capacities survive functions in the thread-local pipeline. A compact representation is the next
backend design target. Releasing all capacity after every function would discard deliberate
reuse and is not accepted as a speed-preserving solution.

### Next occupation work, in order

1. Reconcile allocated heap blocks, allocator-retained pages and OS commitment at the same
   observation points. Existing raw heap samples cannot establish this gap. Any mimalloc block
   traversal must honor its no-concurrent-heap-access contract; waiting on one module's jobs is
   insufficient while deferred links or other clients can allocate.
2. Count the remaining sema containers and backend/linker storage at those points, without
   double-counting arena payloads or nested buffers. Preserve an explicit unattributed remainder.
3. Design the liveness reduction around measured retained matrices and their hot readers. Direct
   bit tests, row unions, global-register spans and interval allocation all use the current rows;
   a compressed replacement must account for each access before implementation.
4. Group correctness and Release validation with the next optimization batch. Repeat unprofiled
   before/after timings under stable host load before accepting the compilation-speed result.

### Live allocator blocks versus retained free slots

[heap-census.json](heap-census.json) records 30 naturally global-idle snapshots from another
successful DevMode application build. The diagnostic runs on the scheduler's setup/main thread
with its mutex held, zero active workers, zero ready jobs and progress animation disabled. It
visits every registered mimalloc heap using fixed stack counters. It does not force a global
barrier or collect/purge memory. This is an occupancy diagnostic, never a timing result.

The normal public visitor triggered an ownership assertion while collecting a page's free list;
the diagnostic therefore uses a temporary read-only visitor branch that subtracts pending
cross-thread frees from the area count. Both the scheduler and vendor patches were restored;
the unresolved normal visitor defect is tracked in `compiler.core.096`.

| Same observation point | MiB |
| --- | ---: |
| Highest captured process working set | 1,461.313 |
| Live mimalloc blocks, including size-class rounding and padding | 1,021.945 |
| Free block slots in the visited pages | 317.099 |
| Total initialized block-slot capacity | 1,339.045 |

The process's recorded peak was 1,505.375 MiB, 44.062 MiB above the highest captured idle point.
Live plus free slots equals capacity. Capacity is `page.capacity * full_block_size`; it excludes
page metadata/tails, unused arena slices, proximity storage, stacks and mappings. It is not an
OS residency total. In particular, neither the 317 MiB nor the difference from RSS is an amount
that can necessarily be returned immediately. A page may mix live and free blocks.

At the final snapshot, live blocks occupy 823.967 MiB and free slots 405.427 MiB, while RSS is
1,446.855 MiB. This confirms substantial retention in addition to the compiler's live structures.
The live allocations still need owner attribution beyond the existing page/arena/backend counts.

The strongest allocator lead is the 64–512 KiB range: at the highest-RSS snapshot, 572 live blocks
occupy **99.266 MiB** in 102 areas with **181.641 MiB of free slots**. Mimalloc's own
`MI_ENABLE_LARGE_PAGES` comment identifies partially used 4 MiB pages as a risk for this workload
shape. Defining it as zero routes larger blocks through singleton allocation and keeps 64 KiB
blocks in medium pages. This supported compile-time choice is the next isolated experiment;
there is no default change yet. The free-slot count is not a promised saving: singleton rounding,
metadata and allocation cost must be measured. Preserve the ordinary packed binary as control,
check the same frozen app and C++ allocator boundary, and accept only with the speed tradeoff
established under the user's priority on compilation time.

### Isolated experiment: disable regular large allocator pages

[no-large-pages-experiment.json](no-large-pages-experiment.json) preserves an external DevMode
candidate built with only `MI_ENABLE_LARGE_PAGES=0` in the wrapper before the vendor include.
The vendor source is unchanged and no census instrumentation is enabled. Normal sources and
`bin/swc.dm.exe` were restored; the default is **not changed**. The candidate passes all 1,620
ordinary C++ tests and a complete rebuild of the same frozen Swag Capture workspace, with six
workers, verified affinity and isolated caches/TEMP.

| Measurement | Packed control | Candidate |
| --- | ---: | ---: |
| Peak resident MiB | 1,495.594 | 1,317.078 |
| Peak private MiB | 1,494.434 | 1,321.312 |
| Wall seconds | 174.700 | 82.001 |
| Process CPU seconds | 449.891 | 310.562 |
| Host busy percent | 67.047 | 49.402 |

The observed resident reduction is **178.516 MiB
(11.94%)**; private memory is
11.58% lower. Both runs report 592,047 tokens,
5,143 tuned functions and 2,411 forged functions. Both passed strict start admission, but external
work resumed during the builds. The lower observed wall/CPU times therefore do not establish a
controlled speedup or complete the speed acceptance requirement.

Generated API comparison finds one differing line: `Lens.View.create` publishes a return-borrow
mask of zero in this control and one in the candidate. The value one already appears in the
earlier archive and backing-census captures without this option, so the variation is not unique
to the allocator experiment. It remains unexplained semantic metadata, not dismissed as harmless
ordering. The exact diff is retained in the experiment record and the reproducibility work is
tracked in `compiler.core.085`. Promotion still needs a stable timing comparison, this output
variation understood, and grouped Release validation.

### Backend batch after the allocation census

The allocation census led to four focused source edits:

- When an acyclic register-liveness matrix exceeds its retained capacity, use `assign(count, 0)`
  instead of `resize(count)`. Its previous rows are dead. The installed MSVC 14.50 vector
  implementation uses the same geometric growth calculation in both paths, but `assign` releases
  the old allocation before buying the new one; `resize` allocates first and moves the old words.
  This removes the transient overlap and stale-word copy on this path. In-capacity acyclic reuse
  and cyclic initialization are unchanged. Retained matrix capacity is unchanged: this is not a
  claim to recover the 115 MiB of retained matrices.
- The branch-target RIP-load rewrite, private-frame reload rewrite and scan-loop rotation now
  request the existing `LiveOutOnly` physical-liveness mode. They read live-in/out masks and never
  consume the per-instruction use/def vectors. This mode still computes both masks. The measured
  branch-target rewrite alone retained 2.882 MiB of unnecessary use/def vector backing at the
  synchronized point. This is eliminated storage, not a measured process-peak saving.

The source diff passes formatting and whitespace checks. Existing
`RegAlloc_ReusedPassBorrowsCurrentCfgAcrossDifferentControlFlow` exercises reused pass storage
while instruction counts/register-word counts grow and shrink across cyclic and acyclic cases.
The existing physical-liveness and affected peephole/rotation tests are the other relevant C++
boundaries. The grouped DevMode build, all 1,620 ordinary C++ tests and the frozen application's
complete rebuild pass. The tests and application used the density-instrumented binary; the normal
compiler was then rebuilt without the probe and completed a further frozen application rebuild.
No new test duplicates the implementation.

The larger matrix redesign remains open. An external diagnostic patch is prepared to count
nonzero words, the first-to-last nonzero word span per row, empty rows and adjacent duplicate
rows for matrices of at least 1 MiB, distinguishing cyclic from acyclic functions. The resulting
measurements below estimate compact-storage candidates before adding an indirection or changing
the hot bit-test/row-union paths. No diagnostic code is enabled in normal sources.

### Populated liveness-matrix density

[liveness-density.json](liveness-density.json) records 52 observations after the virtual liveness
fixed point: four acyclic and 48 cyclic matrices of at least 1 MiB. Repeated analysis of one
function appears repeatedly, so totals across observations describe scanned work, not retained
memory. The instrumentation reads the matrix and is excluded from timing comparisons.

| Matrix shape | Dense words (MiB) | Packed per-row spans plus 16-byte row metadata (MiB) |
| --- | ---: | ---: |
| 40,177 instructions, 162 words per row, acyclic | 49.657 | 0.910 |
| 22,683 instructions, 127 words per row, cyclic | 21.978 | 5.458 |
| 20,604 instructions, 113 words per row, cyclic | 17.763 | 4.561 |
| 20,580 instructions, 77 words per row, cyclic | 12.090 | 2.339 |

The largest matrix has at most **one nonzero uint64 word per row**: its nonzero words total
311,040 bytes, and 1,297 rows are empty. The 0.910 MiB estimate adds 642,832 bytes for one
16-byte descriptor per instruction. It excludes vector growth slack and temporary workspaces;
it is a representation estimate, not a measured process saving. Adjacent-row sharing alone
would still need about 20.978 MiB, so storing each useful word span is the stronger lead.

The first implementation target is large acyclic matrices. A reverse sweep reads already final
successor rows, merges their useful spans into temporary storage, applies use/def masks, then
stores one trimmed row. Cyclic functions retain the dense mutable fixed point initially. Readers
must preserve zero words outside each stored span, global register indices and stable row offsets
across backing-vector growth. Span iteration can avoid scanning known-zero words; random bit
queries add range/offset work whose compilation-time effect still needs measurement.

The uninstrumented source checkpoint is `0d8010eb98`; its normal DevMode binary SHA-256 is
`c61d7801bf42336c8937885f393e18500ea8c9e8befdc168c4601b70e6975627` and is also preserved
externally as `swc.liveness-baseline.dm.exe`. Its first frozen rebuild uses 1,532.301 MiB peak
working set, 63.924 s wall and 245.391 s process CPU. Strict start admission passed, but host load
averaged 38.62% during execution. This is a baseline observation, not a speed-acceptance result.
Its application counts are 592,024 tokens / 5,142 tuned functions / 2,411 forged functions, versus
592,047 / 5,143 / 2,411 in the diagnostic run; the known frozen-input publication variation
remains tracked in `compiler.core.085` and must not be silently treated as identical output.

### Compact acyclic liveness implementation

Large acyclic virtual-register matrices now store only the first-to-last nonzero word span of
each row. Global register numbering is unchanged, and missing prefix/suffix words read as zero.
Rows use offsets into one reusable word vector, so growth cannot invalidate their descriptors.
The reverse sweep merges only successor spans and current uses before applying definitions.
Several downstream set-bit walks also skip the omitted zero words. Cyclic fixed points and
matrices below 1 MiB retain dense storage. Existing backing capacity remains reusable.

The DevMode build and all **1,622 C++ tests pass**. New tests cover reconstruction and bit
queries across storage growth/reuse, and execute large branch-bearing listings through both
register allocators. The same pass alternates compact acyclic listings and a dense cyclic
listing, with results checked against a scalar oracle. The frozen application also rebuilds
successfully with no allocator error. Tracked frozen input sources match byte for byte.

[compact-liveness.json](compact-liveness.json) preserves the binary hashes and observations:

| Frozen application rebuild | Dense baseline | Compact candidate |
| --- | ---: | ---: |
| Peak working set (MiB) | 1,532.301 | 1,467.332 |
| Wall time (seconds) | 63.924 | 52.368 |
| Process CPU (seconds) | 245.391 | 211.234 |
| Average host CPU use (%) | 38.62 | 26.28 |

The observed working-set reduction is **64.969 MiB (4.24%)**. The lower wall/CPU observations
are not an accepted speedup: concurrent host load differs. Both application runs report 592,024
tokens / 5,142 tuned functions / 2,411 forged functions; these counts alone do not establish
generated-code equality. The first repeated baseline completed at 1,504.113 MiB peak working
set, 172.207 s wall and 578.031 s process CPU, with 66.78% average host CPU use. Its timing is
excluded, and the known publication variation returned (592,047 tokens / 5,143 tuned functions).
Compared with this second observation, the candidate is 36.781 MiB lower; the first 64.969 MiB
reduction must not be presented as a repeatable constant. Controlled timing remains pending.

All twelve benchmark tasks were rebuilt once per compiler in program configuration `devmode`,
with isolated caches and the same published Win32 interface. Every executed checksum matches.
The comparator now normalizes process-local addresses for named direct calls while retaining
callee names and calling conventions; unnamed calls remain distinguishable. Its 15 focused
Python tests pass. The preserved captures were reanalyzed without another build.

After this normalization, some `Swag.AtomicValue` instantiations appear in a different print
order. Comparing the complete normalized bodies as multisets under their printed names,
preserving multiplicity, finds identical runtime and task bodies. This avoids interpreting an
exchanged 32/64-bit specialization as a loop regression; it does not invent missing overload
identity in the printer. The only remaining body difference in every task is one immediate in
`__run_expr_76b3847dcadfc02c`, the compile-time expression at `runtime/core.swg:565`. It passes
the compilation-local `TypeRef` to `persistCompilerRunValue`, emitted explicitly by
`CodeGenFunctionHelpers.cpp:1574`. Instruction widths, registers, accesses, branches and call
counts are otherwise identical. Integer constants are not globally normalized. The exact
residual immediates, capture hashes and reviewed counts are preserved in the result JSON.

The candidate's DevMode SHA-256 is
`624ad4435443ed67ac33543e009fff3bc749a0da3880efe8c9c1a1b6a97761b8`.
The matrix density figures above remain representation estimates: the process observation does
not isolate each buffer's saving. Wide fully populated acyclic rows can add descriptor/copy
cost, and retained capacity depends on earlier functions; controlled speed acceptance is still
required before treating this representation as a finished optimization.

The grouped Release compiler build and frozen application rebuild pass as well. This includes
the constant-page packing and preceding backend changes that had only been exercised with the
DevMode compiler at earlier checkpoints. The Release binary SHA-256 is
`6c68aef843c9ec3d6f9abc6996ef3d691e94e6bfa745abed9c91bd43f2ea53cf`, built from compiler
source checkpoint `8bcdc4259b` and preserved outside the checkout. Its working-set peak is
**1,290.176 MiB**, versus 1,467.332 MiB in the DevMode candidate observation: an observed gap
of 177.156 MiB. This is not a controlled difference or an exact output-equivalence assertion.
Host CPU use averaged 72.62%; wall time was 162.520 s, process CPU 589.656 s, and timing is
excluded. The application reports 592,026 tokens / 5,143 tuned / 2,411 forged functions.
Its 77 generated source/API files were preserved for the publication-variation investigation;
tracked frozen sources still match byte for byte. No allocator error was reported.

### Physical-liveness record compaction

The next source batch replaces `MicroPhysLiveness::useDefs`' generic instruction records with
two physical-register masks and one call flag. On x64 the record changes from 88 to 24 bytes,
with a compile-time assertion on the new layout. Calls previously retained heap-backed
register vectors per instruction. A single generic collector now lives in the existing
worker-local graph scratch, retaining its capacity between requests; its masks are published
into the compact records. Ordinary instructions use the existing direct operand-mode path.

The loop-hoist readers now query bits, combine masks, and intersect call definitions with
live-out instead of scanning those vectors. Frame-base masks are computed outside the body
walk. Only physical registers represented by the existing liveness word are in these sets;
unknown-register live-out queries retain their conservative behavior. The existing reuse test
also compares every physical use/definition bit with the generic collector, including call
effects. No generated-code policy or convergence rule changes.

The grouped DevMode build, physical-liveness/loop-hoist C++ tests and generated-code comparison
pass, as detailed below. Its process saving is not included in any measurement above. The
preserved compact-liveness binaries remain the baseline for this batch.

### Virtual operand lists and newly published cache backing

The same batch removes two further retained allocations:

- Register allocation's virtual-use and virtual-definition lists now store up to three indices
  directly, in 16 bytes rather than 40 bytes per list. The bound is derived from
  `MicroInstrDef::regModes`; `collectUseDef` adds virtual registers only from these explicit
  operands, while ABI and x64 encoder effects add physical registers. Encounter order,
  duplicate elimination and direct iteration are unchanged. There is no new indirection or
  per-instruction heap allocation. Physical-index lists keep their variable-length storage.
  The earlier census recorded 5,091,080 bytes of independent instance maxima for each of the
  two virtual-index vectors. At those element capacities, the new layout removes 60% of their
  backing (about 5.827 MiB across those maxima), not a proven simultaneous process-peak saving.
  A new executed-code test covers an indexed store with three virtual uses and another whose
  index is also its source, through both allocation algorithms.
- Cache publication now reopens its immutable output with the existing read-only mapping
  owner, releasing the private serialization buffer after publication. The census attributed
  24,814,564 requested bytes to retained `CompilerCacheStore::publish` buffers. A mapping
  failure falls back to the valid in-memory publication, including when another process has
  already removed the segment. A filesystem regression holds a published record across
  writer destruction, newer publication and invalidation. This removes a duplicate private
  backing, not all resident file pages. Mapping syscalls and subsequent page faults still need
  the grouped timing/memory observation.

The grouped DevMode build succeeds at source checkpoint `f484c97a40`; the preserved binary's
SHA-256 is `470134d0f8007aa6b4d322d8b48aa293a94c73b4d39d9c70cc8b61ca45bd8bad`.
The `--dev-full` run reports **1,697 passed and one failed**. That failure is the external
installation's missing `unittests/sanity/expected_error_native_roots.swg`, required by
`Linker_NativeTestsDiscardRejectedCallees`. After copying the byte-identical tracked fixture,
the exact child command passes its one native test. The full C++ suite was not repeated;
the original failure and focused recovery are retained in [effects-cache.json](effects-cache.json).
The cache filesystem cases and new register-allocation case passed in the original run.

All twelve benchmark tasks rebuild and execute with matching checksums. Complete normalized
runtime/task body multisets match, preserving multiplicity. Ten tasks differ only in the
compilation-local `TypeRef` immediate of the previously identified runtime `#run`; two have no
remaining body difference. Reordered duplicate generic names explain the apparent atomic-loop
changes. No extra instruction, memory access, call or branch was found in the compared bodies.
This comparison does not recover overload call-target identity absent from the listing.

The frozen application rebuilds successfully with both preserved binaries and no allocator
error. Tracked source bytes match. The candidate peaks at **1,443.543 MiB working set**, versus
**1,472.266 MiB** for the immediately following compact-liveness control: an observed reduction
of **28.723 MiB (1.95%)**. Peak private memory is 32.098 MiB lower. Both runs report 592,047
tokens / 5,143 tuned / 2,411 forged functions. Their 46 published `.swg` API files are
byte-identical, including the previously varying Lens borrow summary; eleven worker-partitioned
`.swgsrc` files differ. This is not a whole-generated-output equivalence claim.

Strict start admission passed for both runs, but average host CPU use rose to 50.84% for the
candidate and 63.37% for the control. Candidate wall/process CPU times are 69.177/307.094 s,
versus 147.401/443.953 s for the control; these differences are excluded from speed acceptance.
Controlled timing and grouped Release validation remain pending. The memory figures are
observations of this pair, not a constant guaranteed saving.

### Remaining attribution work

The 149.927 MiB mixed-arena category in the earlier large-allocation census is backing storage,
not an AST or semantic payload total. The external typed-arena diagnostic now counts inline
`sizeof(T) * count` storage allocated through `Arena::make` and `makeArray` at the same
setup-thread/global-idle boundary. Its build and frozen application pass without an allocator
error. Normal sources and the uninstrumented compiler were restored; all diagnostic working
files remain outside the checkout. [arena-types.json](arena-types.json) preserves the evidence.

At the highest captured RSS point (1,368.176 MiB, snapshot 25 of 29), the disjoint arena
partition is 143.896 MiB typed payload, 4.663 MiB finalizer records, 0.716 MiB raw/untyped
allocations, 0.079 MiB block headers, 0.038 MiB alignment padding and 1.295 MiB unused tails:
**150.688 MiB total arena backing**. Every owner and snapshot reconciles exactly. This run's
actual process peak between observations is 1,412.238 MiB; the snapshot is not that exact peak.

| Largest inline arena object | Objects | Bytes per object | MiB |
| --- | ---: | ---: | ---: |
| `AttributeList` | 76,326 | 624 | 45.421 |
| `SymbolFunction` | 31,719 | 1,496 | 45.253 |
| `SymbolVariable` | 161,607 | 136 | 20.960 |
| `SemaInlinePayload` | 22,078 | 736 | 15.497 |
| `CodeGenLoweringPayload` | 77,504 | 80 | 5.913 |
| `SymbolStruct` | 2,045 | 1,112 | 2.169 |
| `LoopSemaPayload` | 3,172 | 536 | 1.621 |

These are object bodies, including inline storage and container descriptors; separately owned
vector/map/string buffers remain outside these type totals. Function symbols span semantic and
backend responsibilities, so their full body is not assigned blindly to one compiler phase.
Diagnostic maps and the extra arena field affect instrumented RSS. This probe does not validate
speed, establish another memory saving, or permit adding its totals to a different run's owner
census. Arena tails are now a low-priority target compared with attributes, symbols and payloads.

The next backend design target remains large cyclic liveness matrices. The density census
shows sparse row bands there too, but the current in-place fixed point needs mutable rows.
One candidate is to solve exact transfer sets at basic-block boundaries and reconstruct compact
instruction rows once after convergence. Before adopting it, bound temporary block-matrix
storage, handle disconnected components and self-loops, preserve use-before-definition order,
and compare every reconstructed row with the existing instruction-level solver. Dense storage
must remain available where the block count or row density defeats the memory/speed trade.

Remaining investigations are maintained in `compiler.core.097`; controlled speed acceptance is
in `compiler.core.098`, allocator visitor correctness in `compiler.core.096`, publication
variation in `compiler.core.085`, and workload budgets/child-process retention in
`compiler.core.005`. The external no-large-pages experiment remains disabled by default.
