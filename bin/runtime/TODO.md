# Runtime Allocator Roadmap

This file tracks the work still required for the Swag runtime allocator to demonstrate performance
and memory behavior comparable to the vendored
[mimalloc](../../src/Support/Memory/mimalloc/readme.md). Defects and investigation leads belong in
[FINDINGS.md](../../FINDINGS.md); completed work disappears from this file because its history lives
in git.

The first allocator pass removes the original pathological behavior: small blocks are carved from
64 KiB pages, Windows thread heaps use FLS and retire automatically, cross-thread frees retain an
owner, cache budgets count internal bytes, and diagnostic metadata is kept off the normal fast
path. A release probe holding 40,000 live 32-byte blocks moved from 40,001 raw allocations and
160,320 KiB of additional working set to 85 raw allocations and 5,644 KiB.

Do not call the allocator "as fast as mimalloc" from that probe alone. The remaining work below is
what turns the improvement into a measured allocator contract.

## Tier A - Prove and close the main gaps

### 1. Add a reproducible allocator benchmark suite

- Compare the runtime allocator directly with the repository's vendored mimalloc build, using the
  same allocation traces and a release x64 executable.
- Cover warm and cold single-thread allocation, mixed size classes, random lifetimes, realloc,
  aligned and large blocks, producer/consumer remote frees, thread churn, and sustained
  multi-thread contention.
- Record throughput, p50/p99 latency, raw OS calls, committed bytes, peak working set, and retained
  memory after idle and explicit release. Keep machine noise out of the result with warm-up,
  repeated samples, and median reporting.
- Define the parity gate before tuning: a geometric-mean throughput within 10% of mimalloc, no
  representative workload more than 25% slower, and no unbounded retained-memory case.

### 2. Put 64 KiB pages inside larger reserved segments

- The new page layer still performs one `VirtualAlloc` reservation per 64 KiB allocator page.
  Reserve multi-megabyte, allocation-granularity-aligned segments and commit pages on demand.
- Track page ownership separately from segment ownership so partially used pages, live blocks, and
  abandoned thread heaps cannot keep unrelated pages committed.
- Decommit empty pages with a bounded purge delay and release completely empty segments. Validate
  counters against committed bytes rather than reserved address space.
- Preserve the current failure contract: if segment reservation or page commit fails, allocation
  returns null without corrupting page or heap state.

### 3. Shrink the normal per-block metadata

- The normal header still carries list links and state used only by diagnostics or by free blocks.
  Move diagnostic allocation/free links into `AllocatorTracking`, and put free-list links in memory
  that does not increase the live-block stride.
- Move size-class and page ownership information to page metadata where it can be recovered safely
  from an address. Keep only information required to validate and free a live block.
- Maintain exact requested-size bounds for fill and corruption checks, and preserve arbitrary
  alignment and realloc behavior while changing the layout.

### 4. Remove unconditional global statistics atomics from the hot path

- Allocation and free currently update several allocator-wide atomic counters even when nobody is
  reading diagnostics.
- Accumulate ordinary counters in the owning thread heap and publish them in batches; keep only the
  synchronization required for lifetime safety and remote frees.
- Specify whether public statistics are exact snapshots or eventually consistent. Diagnostic mode
  may pay for exact accounting; the release fast path should not.

## Tier B - Match mature concurrent allocators

### 5. Make remote frees page-local and batched

- Replace the single CAS per remotely freed block with a page-local delayed-free list and transfer
  batches to the owner heap.
- Bound remote-list draining so one allocation cannot inherit an arbitrarily long pause, while
  guaranteeing that retired heaps and pages still become reclaimable.
- Benchmark one producer/one consumer, many producers/one owner, and owner-thread exit during
  remote frees.

### 6. Track full, partial, and empty pages explicitly

- Keep per-size-class queues of usable pages instead of only one bump page plus individual cached
  blocks. Prefer a partially used page before committing a new one.
- Reclaim an empty page as a unit and avoid walking every cached block merely to return its OS
  memory.
- Add an abandoned-page path so a terminating thread does not strand pages that another thread can
  reuse economically.

### 7. Tune size classes and special allocation paths from traces

- Measure fragmentation for real compiler, standard-library, GUI, and sCrypt traces before
  changing the class table.
- Add dedicated paths for naturally aligned blocks, medium allocations, and direct large OS
  allocations. Large freed regions should be released or decommitted instead of entering a small
  block cache.
- Consider cache-line placement and false sharing in heap/page metadata as part of the benchmark,
  not as a layout guess.

## Tier C - Harden the implementation

### 8. Expand lifecycle, race, and failure testing

- Stress thread creation/destruction, allocator replacement, remote frees racing retirement, mode
  changes, and repeated release under randomized schedules.
- Inject reserve and commit failures at every transition and verify counter, list, and reference
  invariants.
- Run long stress jobs under Windows Application Verifier and page heap, then add equivalent real
  TLS and OS memory primitives before enabling the page fast path on another target.
- Document allocator lifetime requirements for FLS callbacks and custom allocators; no callback may
  dereference an allocator that has already gone out of scope.
