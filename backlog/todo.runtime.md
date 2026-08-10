# Runtime Allocator Roadmap

This file is the roadmap for `bin/runtime`, and tracks the work still required for the Swag runtime
allocator to demonstrate performance and memory behavior comparable to the vendored
[mimalloc](../src/Support/Memory/mimalloc/readme.md). Defects and investigation leads belong in the
`findings.*` files, which hold evidence; this file holds intent. [README.md](README.md) has the
whole layout. Completed work disappears from this file because its history lives in git.

The allocator now has two paths, and which one produced a block is recoverable from its address, so
the two never have to be told apart by a flag. The page path serves every request up to 64 KiB:
blocks are carved from segment pages, carry **no header at all**, and are recovered on free by
masking the address down to its page. The header path serves larger blocks, over-aligned blocks, and
every allocation made while a diagnostic mode is on.

Measured against the previous design on the same machine, alternating both binaries
(`bench/` has no allocator workload yet — T-019):

| workload | before | after |
| --- | --- | --- |
| allocate+free one 32-byte block | 4 297 ops/ms | 13 053 ops/ms |
| allocate+free one 256-byte block | 3 785 ops/ms | 12 629 ops/ms |
| 40 000 live 32-byte blocks, allocate | 4 896 us | 1 383 us |
| 40 000 live 200-byte blocks, allocate | 8 991 us | 1 448 us |
| random sizes and lifetimes, 2 M operations | 6 140 ops/ms | 18 317 ops/ms |
| four threads, 400 000 operations | 102 381 us | 14 666 us |
| producer/consumer remote free, 200 000 blocks | 122 110 us | 43 578 us |
| working set per live 32-byte block | 144 bytes | 7 bytes |
| peak working set over the whole probe | 24 088 KB | 6 384 KB |
| address-space reservations over the whole probe | 442 | 1 |

The remaining work below is what turns that into a measured allocator contract.

## Tier A - Prove and close the main gaps

### T-019 — Add a reproducible allocator benchmark suite

- The numbers above come from a throwaway probe. Nothing in the repository measures the allocator,
  so a regression in it is invisible until something else gets slower.
- Compare the runtime allocator directly with the repository's vendored mimalloc build, using the
  same allocation traces and a release x64 executable.
- Cover warm and cold single-thread allocation, mixed size classes, random lifetimes, realloc,
  aligned and large blocks, producer/consumer remote frees, thread churn, and sustained
  multi-thread contention.
- Record throughput, p50/p99 latency, OS calls, committed bytes, peak working set, and retained
  memory after idle and after `trim()`. Keep machine noise out of the result with warm-up, repeated
  samples, and median reporting: the probe above varied by a factor of three between runs on an
  otherwise idle machine, and only alternating the two binaries made the comparison readable.
- Define the parity gate before tuning: a geometric-mean throughput within 10% of mimalloc, no
  representative workload more than 25% slower, and no unbounded retained-memory case.

### T-020 — Close the remaining distance to mimalloc on the hot path

- An allocate/free pair on a cached block costs about 77 ns. mimalloc is in the 10-20 ns range,
  so the structural work is done and what is left is the constant factor.
- What the path still pays, in the order worth attacking: one `FlsGetValue` per operation to find
  the thread heap (measured at 4 ns per call, against 2 ns for `TlsGetValue` and 1 ns for a plain
  global read); the `IAllocator` interface dispatch and the `AllocatorRequest` the caller fills;
  the block-address validation on free; the diagnostic-mode test at every entry point.
- Real thread-local storage would remove most of the first item. `#[Swag.Tls]` now lowers to a
  per-thread copy, so the mechanism is there; what it still cannot hold is a value with a drop
  ([F-019](findings.compiler.md#f-019--a-thread-local-global-cannot-hold-a-droppable-type)).
  Sequence that decision before micro-tuning anything else here.
- Measure with T-019 before and after, not with a probe written for the occasion.

### T-021 — Return idle memory without being asked

- `trim()` decommits every page with no live block and returns the segments left without one, but
  nothing calls it on its own. A program that allocates in bursts keeps the high-water mark of
  committed pages until it exits or trims by hand.
- Decide the policy: a bounded amount of idle committed memory per heap, a purge delay after which
  an untouched page is decommitted, or an explicit contract that trimming is the caller's job.
  Whichever it is, write it down — "give memory back eventually" with no rule is how an allocator
  ends up with an unbounded case that only shows on someone else's machine.
- An abandoned page whose class nobody allocates again is only collected by `trim()`. Bound that
  too, or state that a thread exiting mid-workload can retain its pages until the next trim.

## Tier B - Concurrent paths and allocation classes

### T-022 — Make remote frees batched rather than one atomic each

- A block freed by a thread that does not own its page costs one compare-exchange, and the owner
  drains the list only when the page runs dry. That is already far better than the previous design,
  but a producer/consumer pair still pays one atomic per block in each direction.
- Measure whether a per-page batch handoff pays for itself against the current single push, using
  the producer/consumer workload from T-019. Bound the drain so one allocation cannot inherit an
  arbitrarily long pause.

### T-023 — Add a medium-allocation tier above 64 KiB

- Requests above 64 KiB take the header path: one `VirtualAlloc` reservation each, released on
  free. That is correct and wastes almost nothing, but a buffer that doubles across the boundary
  pays a kernel round trip per growth.
- Measure the real distribution first, on compiler, standard-library, GUI, and sCrypt traces. If
  the boundary is hot, the answer is a size-class tier above 64 KiB carved from whole segments, not
  a cache of arbitrary blocks.

- Related: T-163

### T-163 — Huge allocations have no separately measured policy

Define the threshold and reserve/commit/release behavior for genuinely huge allocations after the
medium tier is separated. Benchmark large growth and release independently of size-class caching.

- Related: T-019, T-023

### T-024 — Tune size classes from traces rather than from the table

- Classes split each power of two into four above 128 bytes, which bounds the step at a fifth of
  the class it lands in. Eight-way splitting would halve that at the cost of doubling the class
  count and the per-heap page queues.
- Decide it from measured fragmentation on real traces, and consider cache-line placement and false
  sharing in the page table as part of the same measurement.

## Tier C - Failure, platform, and security hardening

### T-025 — Add allocator OS-failure injection

- `bin/unittests/native/runtime/` covers size classes, page recovery from an address, free-list
  obfuscation, interior-pointer rejection, abandoned-page adoption, foreign-thread retirement
  through the FLS destructor, and a 32-thread abandon/remote-free/trim stress. What it does not
  cover is failure injection.
- Inject reserve and commit failures at every transition and verify that page masks, segment lists,
  and the abandoned list stay consistent and that the allocation returns null rather than a
  half-built page.
- Related: T-164, T-165

### T-164 — Allocator stress is not run under Windows heap instrumentation

Run the allocator stress suite under Windows Application Verifier and page heap, and make the
invocation reproducible without folding it into failure injection.

- Related: T-019, T-025

### T-165 — The page allocator has no real second-platform OS primitives

Implement equivalents of `allocatorOsCommit`, `allocatorOsDecommit`, page protection, release, and
thread-exit cleanup before enabling the page path on another target. The compiled fallbacks are
placeholders, not an implementation.

- Related: T-025, T-269, T-270

### T-026 — Decide what the security properties are, and write them down

- Shipped: free-list links are obfuscated with a per-page key and validated on pop; a free rejects
  any address that does not start a block of its page; an immediate double free of the most recently
  freed block is caught; electric mode places every block flush against a reserved guard page and
  never reuses an address.
- Not decided: whether those checks are a guarantee or a best effort. A full double-free check
  costs a free-list walk and is diagnostic-only today; the pop-time validation catches a corrupted
  link but not a link that was swapped for another valid block of the same page.
- Name the subset that is a contract, state it in the module documentation, and test each item of
  it explicitly rather than leaving the properties to be inferred from the implementation.
