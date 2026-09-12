# Runtime Allocator Backlog

This backlog tracks the work still required for the Swag runtime
allocator to demonstrate performance and memory behavior comparable to the vendored
[mimalloc](../src/Support/Memory/mimalloc/readme.md). Evidence, investigations, and intended
outcomes stay together here. [README.md](README.md) has the whole layout. Completed work
disappears from this file because its history lives in git.

The allocator now has two paths, and which one produced a block is recoverable from its address, so
the two never have to be told apart by a flag. The page path serves requests up to 64 KiB with
alignment at most 16 bytes: blocks are carved from segment pages, carry **no header at all**,
and are recovered on free by
masking the address down to its page. The header path serves larger blocks, over-aligned blocks, and
every allocation made while a diagnostic mode is on.

The static review recorded on 2026-09-11 finds a modern small-allocation design, but no
current evidence of parity with leading general-purpose allocators in performance consistency or
hardening. This is the application runtime allocator; the C++ compiler already uses mimalloc
through `src/Support/Memory/Allocator.cpp`. The subsequent health reset reproduced and fixed four allocation-contract defects;
`native/runtime/allocator_contract.swg` covers those boundaries, and the 109 allocator cases
pass in JIT and native execution under both program configurations. No new performance benchmark
was run. Remaining code-derived leads require focused reproduction before implementation.

There are 45 size classes from 8 bytes through 64 KiB. Classes use 64 KiB or 512 KiB pages inside
4 MiB segments. Each thread heap has a current page per class, and cached local allocation/free
manipulate blocks without locks or atomics. These are useful locality and metadata properties;
preserve them while resolving the open contracts below.

Historical measurements against the previous design on the same machine, alternating both binaries
(`bench/` has no allocator workload yet — runtime.allocator.001):

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

The remaining work below is what turns that into a measured allocator contract. The 77 ns pair
and 10-20 ns mimalloc comparison in runtime.allocator.002 are historical, not evidence that the
current allocator is four to eight times slower. The working-set figure below the requested
payload size is not a physical cost per resident live object; the shared benchmark must touch
payloads and separate working set, committed bytes, and reserved address space.

Correctness and explicit safety contracts come before tuning. Use runtime.allocator.001 to decide
whether to retain or replace the allocator from application results, rather than from architecture
alone. Comparative reference points for that investigation:

| Allocator | Relevant comparison |
| --- | --- |
| [mimalloc](https://github.com/microsoft/mimalloc) | The closest design and first Windows comparator: page-local free-list sharding and separate remote publication, described as a CAS operation. Compare secure mode separately from its ordinary build. |
| [jemalloc](https://jemalloc.net/jemalloc.3.html) | Similar four-per-doubling size classes, with thread caches, configurable decay/purge and richer introspection. Compare retention and fragmentation as well as throughput. |
| [TCMalloc](https://google.github.io/tcmalloc/design.html) | Per-CPU caches, batched transfers and a hugepage-aware backend are useful architectural reference points. Its [per-CPU restartable sequences](https://google.github.io/tcmalloc/rseq.html) use Linux facilities, so this is not a direct Windows backend comparison. |
| [Scudo](https://llvm.org/docs/ScudoHardenedAllocator.html) and [hardened_malloc](https://github.com/GrapheneOS/hardened_malloc) | Hardening reference points for state/integrity checks, metadata isolation, randomization and quarantine. Features differ by allocator and configuration; do not imply all protections are enabled by default or provide complete memory safety. |

### runtime.allocator.010 — Decide what the security properties are, and write them down

- Recorded: 2026-08-06 06:22
- Updated: 2026-09-11 21:18 — Remove corrected documentation claims; retain the unproved hardening contracts.
- Evidence: `allocator.pages.swg::encode/decode/acquireBlock/isBlockAddress` obfuscate links
  with a per-page key and validate decoded block boundaries before allocation. Small live blocks
  have no header/footer or exact requested-size record. These checks are useful corruption
  detection, not complete spatial or temporal memory safety.
- `allocator.swg::freeBlock` only compares a local free with the list head. With at least three
  blocks of a class allocated, releasing A, then B, then A can pass that check and create a
  free-list cycle while another block remains live. Remote publication has no equivalent
  duplicate check. Reproduce through a harness that reaches the allocator rather than relying on
  a statically obvious invalid source that the compiler may reject.
- `assertIsAllocated` explicitly walks free lists, but ordinary free does not. A block-boundary
  check alone does not prove current liveness; a stale address can name a reused slot, and a
  corrupted link can name another valid block on the same page.
- Electric placement rounds the starting address down for alignment. With alignment 16 and
  size 129, the payload ends 15 bytes before the guard; a one-byte overflow remains accessible.
  The allocator comments now describe this alignment slack accurately. Electric blocks have
  no footer. Decide how alignment, exact-bound checking and guard placement
  compose, and test non-multiple sizes explicitly.
- `quarantine` never evicts in electric mode, so freed addresses are not reused before teardown,
  but their payload stays committed/readable/writable. Retention can grow without a byte limit.
  Stale-read interception is already owned by compiler.safety.004; retaining an address is not
  interception. Ordinary page allocations also reuse memory without stale-access instrumentation.
- `fillFree` writes a pattern, but `checkFree` checks only header/footer magic. It does not scan
  the freed payload for later writes; the allocator comments now state that boundary. `fillMemory` alone does not enable diagnostic mode or quarantine.
- Elsewhere: mimalloc secure mode adds protections such as randomized allocation and encoded
  lists; Scudo checks allocation state/header integrity; hardened_malloc offers isolated metadata,
  canaries, randomization and quarantine according to configuration. Swag's current checks do not
  establish comparable hardening. See the primary sources in this file's introduction.
- Next: reproduce nonconsecutive local and remote double frees, aligned guard slack and
  write-after-free inside the payload; choose the supported guarantees and implement the
  necessary checks. Make comments and public documentation distinguish detection, mitigation,
  optional diagnostics and unsupported cases. Measure their cost separately from normal Release.
- Complete when: every claimed guarantee has a focused regression and accurate documentation,
  with explicit limits for reuse, alignment slack, quarantine lifetime and payload checking.
- Related: compiler.safety.004, runtime.allocator.001.

### runtime.allocator.016 — Avoid repeated scans of full pages during live-set growth

- Recorded: 2026-09-11 16:29
- Evidence: static review of `allocator.swg::acquireBlockSlow`. Once the current page is exhausted,
  allocation walks the class list from its beginning, revisiting full pages and collecting remote
  lists before acquiring a new page. If old pages remain full, filling P pages can accumulate
  O(P squared) page visits. Segment acquisition also scans segment lists under `segmentMutex`.
  This is a complexity finding; its application-time impact has not been measured.
- Next: add same-class monotonically growing live sets and partially freed variants to the common
  benchmark, count visits and measure p99. Evaluate separate full/available page queues or another
  bounded search policy while retaining remote-free discovery and abandoned-page adoption.
- Complete when: growth no longer repeatedly scans all full pages, with measured scaling and
  regressions for remote returns, page retirement and adoption.
- Related: runtime.allocator.001, runtime.allocator.002, runtime.allocator.004.

### runtime.allocator.003 — Return idle memory without being asked

- Recorded: 2026-08-05 10:27
- Updated: 2026-09-11 16:29 — Quantify current-page retention and include idle remote owners.
- `trim()` decommits empty pages of the calling heap except the current page of each size class,
  collects empty abandoned pages, and releases segments left without a page. Nothing calls it on
  its own. A program that allocates in bursts retains committed pages until it exits or trims by hand.
- Decide the policy: a bounded amount of idle committed memory per heap, a purge delay after which
  an untouched page is decommitted, or an explicit contract that trimming is the caller's job.
  Whichever it is, write it down — "give memory back eventually" with no rule is how an allocator
  ends up with an unbounded case that only shows on someone else's machine.
- An abandoned page whose class nobody allocates again is only collected by `trim()`. Bound that
  too, or state that a thread exiting mid-workload can retain its pages until the next trim.
- The newer header-block cache is separately bounded by 96 MiB/twelve entries and is drained by
  allocator teardown. `trim()` currently walks pages and segments, not this cache. Include its
  explicit-trim and idle-purge behavior in the same policy.
- Static evidence: retaining one current page in all 45 classes keeps up to roughly 8 MiB of
  pages per thread (33 small pages and 12 medium pages), before other retained pages/metadata.
  An owner that remains alive but stops allocating can leave remotely returned blocks uncollected;
  the retained live-owner case must be covered separately from abandoned pages.
- Exact-size header-cache reuse can retain committed memory without satisfying nearby sizes.
  Account for its global-per-allocator mutex and bounded budget when choosing a purge policy.
- Next: measure burst/idle, inactive live owners, abandoned pages and explicit trim with the
  benchmark in runtime.allocator.001, then define and implement the retention policy.
- Complete when: the current pages, remote returns, abandoned pages and header cache have tested
  idle/trim behavior and documented bounds.
- Related: runtime.allocator.001, runtime.allocator.004, runtime.allocator.005.

### runtime.allocator.002 — Close the remaining distance to mimalloc on the hot path

- Recorded: 2026-08-06 06:22
- Updated: 2026-09-11 16:29 — Separate code-visible hot-path costs from historical timing estimates.
- The historical probe above measured about 77 ns per allocate/free pair; its comparison put
  mimalloc in the 10-20 ns range. These are not current measurements. The shared benchmark in
  runtime.allocator.001 must establish the present gap before another optimization is selected.
- What the path still pays, in the order worth attacking: one `FlsGetValue` per operation to find
  the thread heap (measured at 4 ns per call, against 2 ns for `TlsGetValue` and 1 ns for a plain
  global read); the `IAllocator` interface dispatch and the `AllocatorRequest` the caller fills;
  the block-address validation on free; the diagnostic-mode test at every entry point.
- Real thread-local storage would remove most of the first item. `tls` now lowers to a
  per-thread copy, so the mechanism is there; what it cannot hold is a value with a drop, which
  the compiler now refuses at the declaration: the per-thread block is released by the
  thread-exit destructor, which frees the bytes without running `opDrop`. Whatever the heap
  keeps in thread-local storage has to be a plain value.
- Measure with runtime.allocator.001 before and after, not with a probe written for the occasion.
- Static evidence: `bin/runtime/os_windows.swg::__hostThreadStorageGet` calls `FlsGetValue`;
  `allocator.swg::threadHeap/freeBlock` reach it on local operations. Dispatch, request setup,
  validation and diagnostic predicates add work, but inlining and generated code determine the
  actual cost. The individual FLS/TLS/global timings above are also historical.
- Next: attribute these costs in the common benchmark and generated code, preserving foreign
  thread cleanup when evaluating a cheaper heap lookup.
- Complete when: current A/B evidence identifies a worthwhile change or establishes that the
  remaining costs meet the parity gate.
- Related: runtime.allocator.001, runtime.allocator.016.

### runtime.allocator.005 — Add a medium-allocation tier above 64 KiB

- Recorded: 2026-08-05 10:27
- Updated: 2026-09-11 16:29 — Record the 64 KiB gap and the cost of small over-aligned requests.
- Requests above 64 KiB still use the header path. That path now reuses exact-size freed OS
  blocks of at least 512 KiB, bounded by 96 MiB and twelve blocks. `popCachedBlock` takes a matching
  block; `cacheFreedBlock` evicts the oldest retained blocks when either budget would be exceeded.
  Smaller header allocations and cache misses still take the OS allocation path.
- Measure the size/lifetime distribution on compiler, standard-library, GUI and Swag Vault
  traces against this implementation. Determine whether a segment-backed medium size-class tier
  improves allocation latency or retained memory beyond the existing bounded cache. Keep the
  cache's current behavior as the comparison baseline rather than assuming one OS call per request.

- Static evidence: `allocator.swg::allocateHeaderBlock/cacheFreedBlock` send ordinary 128 KiB
  and 256 KiB buffers through host reserve+commit and release on each allocation/free pair.
  The cache threshold is rounded OS allocation size, including header/alignment/footer overhead,
  rather than the requested payload size.
- Alignment above 16 bytes also bypasses pages: a 256-byte payload aligned to 64 currently takes
  its own OS allocation and is too small for the header cache. Include small SIMD/cacheline-aligned
  requests in the same tier investigation, not only payloads above 64 KiB.
- Exact-size matching is by rounded OS size; nearby requests sharing that rounded size can hit,
  while requests in different rounded sizes cannot reuse a larger cached block.
- Next: compare the existing cache with a segment-backed medium/aligned strategy on these
  boundaries and representative buffer/image traces.
- Complete when: measured evidence selects the medium/aligned policy and establishes its
  latency, alignment correctness, fragmentation and retention behavior.
- Related: runtime.allocator.001, runtime.allocator.003, runtime.allocator.006

### runtime.allocator.004 — Make remote frees batched rather than one atomic each

- Recorded: 2026-08-05 10:27
- Updated: 2026-09-11 16:29 — Record spin contention and full remote-list draining.
- A block freed by a thread that does not own its page increments `remoteCount` atomically and
  pushes through the page's `remoteLock`. The owner detaches the list under that lock and walks it
  afterward. A producer/consumer pair still pays synchronization for each returned block.
- Measure whether a per-page batch handoff pays for itself against the current single push, using
  the producer/consumer workload from runtime.allocator.001. Bound the drain so one allocation cannot inherit an
  arbitrarily long pause.
- Static evidence: `allocator.pages.swg::pushRemote` performs an atomic `remoteCount` increment,
  then acquires `remoteLock`; `lockRemote` retries CAS without a pause or backoff. This is a
  per-page spin lock, not a lock-free remote-free path. Multiple consumers of one producer's
  page contend on the same lock and counter.
- `collectRemote` detaches under that lock and walks the complete list outside it. Its work is
  proportional to the returned list, so a slow allocation inherits a potentially long drain.
  Compare against mimalloc's documented separate remote-list CAS publication, without assuming
  that copying its algorithm preserves Swag's retirement/adoption invariants.
- Next: benchmark many-to-one returns and drain latency, then evaluate bounded batch publication
  and collection while preserving concurrent page retirement and adoption.
- Complete when: the selected synchronization policy has contention and p99 evidence plus
  concurrent retirement/adoption regression coverage.
- Related: runtime.allocator.001, runtime.allocator.003.

### runtime.allocator.001 — Add a reproducible allocator benchmark suite

- Recorded: 2026-08-05 10:27
- Updated: 2026-09-11 16:29 — Record the comparative review and the workload and accounting requirements.
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
- Add boundary workloads immediately below/at/above 64 KiB and 512 KiB of rounded OS size,
  ordinary and 16/32/64-byte alignment, live-set growth without frees, realloc growth/shrink,
  many consumers returning one producer's pages, and burst/idle phases while owners stay alive.
  Distinguish header-cache hits from misses and record the exact allocator versions/options.
- Measure end-to-end application time as well as allocator-only throughput. Touch every allocated
  payload, retain observable results, and use identical traces, warm-up and order-alternated
  repeated samples. Cover image/buffer/SIMD workloads and representative GUI/application traces.
- Audit accounting before treating it as evidence: `stats().sizeCached` does not include the
  header-block cache, `countOsReserve` currently counts arena reservations rather than every
  header-path reservation, and concurrent `stats()` is not a synchronized exact snapshot of
  local allocation activity. Cross-check with host memory/call measurements; never substitute
  virtual reservations for committed or resident memory.
- Run normal Release allocation separately from diagnostic allocation: both presets leave
  tracking, stack capture, electric mode and fill disabled; DevMode enables leak reporting,
  whereas Release disables it. Diagnostic mode routes all allocations through OS-backed headers
  and serializes interface operations with the allocator mutex. A diagnostic run cannot establish
  ordinary allocation throughput.
- Next: implement the shared Swag/mimalloc trace driver and account for these boundaries before
  choosing a hot-path optimization or a replacement backend.
- Complete when: repeated comparable results cover the listed workloads and the existing parity
  gate, with application time, latency tails, retention, build settings and measurement limits
  recorded.

### runtime.allocator.007 — Tune size classes from traces rather than from the table

- Recorded: 2026-08-05 10:27
- Updated: 2026-09-11 16:29 — State the fragmentation denominator and the jemalloc comparison.
- Classes split each power of two into four above 128 bytes, which bounds the step at a fifth of
  the class it lands in. Eight-way splitting would halve that at the cost of doubling the class
  count and the per-heap page queues.
- Decide it from measured fragmentation on real traces, and consider cache-line placement and false
  sharing in the page table as part of the same measurement.
- The approximately 20% bound is unused bytes divided by obtained block size, not by requested
  bytes, and excludes the smallest classes and unused capacity in partially occupied pages.
  The four-per-doubling structure resembles jemalloc's documented classes; this alone says
  nothing about real application fragmentation.
- Next: record requested bytes, class-rounded bytes and resident/committed page occupancy on
  identical traces before changing the class table.
- Complete when: a trace-backed decision covers both internal fragmentation and per-thread
  page retention, including very small and aligned allocations.
- Related: runtime.allocator.001, runtime.allocator.003, runtime.allocator.005.

### runtime.allocator.011 — Audit error storage ownership and reclamation

- Recorded: 2026-09-06 21:01
- Evidence: while diagnosing Swag Vault rename collisions, `Core.Errors.mkString` and
  runtime `__setErrRaw` both call `ScratchAllocator.alloc(size)`. That overload allocates directly
  through the backing allocator; it does not advance `used` or link the allocation into
  `firstLeak`. The error stack rewinds `used`, and `ScratchAllocator.release` only releases its
  buffer and tracked spills, so these copies appear to escape error-storage reclamation.
- Related evidence: `Threading.Thread.init` copies the parent's complete context and resets only
  `tempAllocator`, leaving `errorAllocator` storage shared with the parent. A change to use the
  scratch buffer must first establish independent error storage for each thread.
- Next: add allocation-count and concurrent-error reproducers, then define the lifetime of caught
  error values and strings before routing allocations through the scratch interface. Include
  foreign-thread exit cleanup and nested catch/rethrow behavior.
- Complete when: repeated handled errors reclaim their storage and simultaneous threads cannot
  overwrite one another's errors, with native regression coverage.

### runtime.allocator.008 — Add allocator OS-failure injection

- Recorded: 2026-08-06 06:22
- Updated: 2026-09-06 07:51 — git: prompt 6
- `bin/unittests/native/runtime/` covers size classes, page recovery from an address, free-list
  obfuscation, interior-pointer rejection, abandoned-page adoption, foreign-thread retirement
  through the FLS destructor, and a 32-thread abandon/remote-free/trim stress. What it does not
  cover is failure injection.
- Inject reserve and commit failures at every transition and verify that page masks, segment lists,
  and the abandoned list stay consistent and that the allocation returns null rather than a
  half-built page.
- Related: platform.portability.089, platform.portability.004

### runtime.allocator.006 — Huge allocations have no separately measured policy

- Recorded: 2026-08-09 11:30
- Updated: 2026-08-30 12:44 — git: Refactor and update various components for improved functionality and clarity

Define the threshold and reserve/commit/release behavior for genuinely huge allocations after the
medium tier is separated. Benchmark large growth and release independently of size-class caching.

- Related: runtime.allocator.001, runtime.allocator.005
