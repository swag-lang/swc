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
(before `bench/allocator` existed; every campaign now records the allocator — runtime.allocator.001):

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
- Updated: 2026-10-03 08:56 — Writes into the start of a freed block are reported when it is handed out again.
- Free-list heads are plain addresses in the page metadata and every stored link is keyed, the
  end of a list included, and a block handed out has its first word cleared. A free block
  therefore reads as one from its first word: `looksFree` tests it on every free, and only a
  match (a live block matches by coincidence about once in 2^40 frees) walks the lists. The
  owner checks its own and the remote list, another thread the remote list. The A, B, A
  sequence that used to create a cycle now panics with "memory block is freed twice"
  (`allocator_coverage.swg`); a panic hook that resumes leaves the lists intact. Corrupted
  links are still rejected at pop and collect time, and every check runs in both presets.
- A free block of sixteen bytes or more carries a canary derived from the page key in its second
  word, checked when the block is handed out again: a write through a stale pointer into the
  first sixteen bytes panics with "memory block was written after being freed" (2-3% on the
  micro-benchmarks). Writes further into the payload, and into 8-byte blocks, are not seen.
- Not covered: a block freed by its owner and freed again by another thread while it sits on the
  owner's list (only the remote list is safe to walk from another thread); a free of a block on an
  abandoned page.
- Electric placement rounds the starting address down for alignment. With alignment 16 and
  size 129, the payload ends 15 bytes before the guard; a one-byte overflow remains accessible.
  Electric blocks have no footer. Decide how alignment, exact-bound checking and guard placement
  compose, and test non-multiple sizes explicitly.
- `quarantine` never evicts in electric mode, so freed addresses are not reused before teardown,
  but their payload stays committed/readable/writable. Retention can grow without a byte limit.
  Stale-read interception is already owned by compiler.safety.004; retaining an address is not
  interception. Ordinary page allocations also reuse memory without stale-access instrumentation.
- `fillFree` writes a pattern, but `checkFree` checks only header/footer magic. It does not scan
  the freed payload for later writes. `fillMemory` alone does not enable diagnostic mode or
  quarantine.
- Elsewhere: mimalloc secure mode adds protections such as randomized allocation and encoded
  lists; Scudo checks allocation state/header integrity; hardened_malloc offers isolated metadata,
  canaries, randomization and quarantine according to configuration.
- Next: aligned guard slack and write-after-free inside the payload; choose the supported
  guarantees, then make comments and public documentation distinguish detection, mitigation,
  optional diagnostics and unsupported cases.
- Complete when: every claimed guarantee has a focused regression and accurate documentation,
  with explicit limits for reuse, alignment slack, quarantine lifetime and payload checking.
- Related: compiler.safety.004, runtime.allocator.001.

### runtime.allocator.005 — Scale the large-block cache with threads

- Recorded: 2026-08-05 10:27
- Updated: 2026-10-03 08:56 — Alignments up to 64 bytes are now served from pages; the large-block cache's single lock remains.
- Header-path blocks are reserved at one of eight sizes per power of two and commit only what the
  request reaches; freed ones go to a best-fit cache (up to twice the request) indexed in the
  allocator, a cached block that committed less gets the missing pages, and a reallocation inside
  the reservation commits in place. `bench/allocator` large (32 live 64 KiB-1 MiB blocks):
  137 µs -> 2.0 µs per operation (mimalloc 1.5 µs) at 44 MB peak working set against 71 MB;
  four threads 73.5 µs -> 1.1-1.4 µs (mimalloc 0.67 µs at 250 MB); realloc growth to 4 MiB
  17.1 -> 11.9 µs per step (mimalloc 10.4 µs).
- A request aligned on 32 or 64 bytes now moves to the smallest class whose size is a multiple of
  the alignment and comes from pages (200 000 pairs of 256 bytes aligned on 64: 0.77 s -> 0.06 s).
  Only alignments beyond 64 take the header path.
- Remaining: every header-path allocation and free takes the header-list mutex and the cache
  mutex. Four threads cycling large buffers still run half as fast as mimalloc, which keeps
  almost twice the memory.
- Next: measure a small per-thread front for the cache, and a header list that does not need the
  allocator-wide lock outside the diagnostic modes.
- Complete when: four threads cycling large buffers are within the parity gate of
  runtime.allocator.001 without more retained memory than mimalloc.
- Related: runtime.allocator.001, runtime.allocator.003, runtime.allocator.006

### runtime.allocator.003 — Return idle memory without being asked

- Recorded: 2026-08-05 10:27
- Updated: 2026-10-03 08:56 — trim() now decommits idle pages in every segment, not only in emptied ones.
- An emptied page now returns to its segment still committed while the process-wide idle budget
  allows (a quarter of the committed bytes, at least 8 MiB), and any class reuses it without a
  system call; past the budget it is decommitted. `trim()` decommits the idle pages of every
  segment, teardown those of the segments it releases, and `trim()` also gives the large-block
  cache back. The cache's budget follows the bytes held
  live through the header path (at least 16 MiB, at most 256 MiB, 64 entries).
- Measured on `bench/allocator` medium (256 live 4-64 KiB blocks): 213 -> 51 ns per operation,
  peak working set 11.8 -> 19.8 MB (mimalloc 36.5 ns, 19.2 MB). A 2 MiB / one-eighth budget
  brings the working set back to 13.4 MB and the time back to 242 ns: the budget is the trade.
- Still open: nothing purges without a call. A program that bursts and then idles keeps up to the
  idle budget plus the cache budget until it trims or exits; an inactive live owner keeps its
  remotely returned blocks uncollected.
- Next: decide whether a time-based purge on the slow paths is worth its cost, or document that
  bound as the contract; measure burst/idle with an owner kept alive.
- Complete when: the current pages, remote returns, abandoned pages and header cache have tested
  idle/trim behavior and documented bounds.
- Related: runtime.allocator.001, runtime.allocator.004, runtime.allocator.005.

### runtime.allocator.002 — Close the remaining distance on the allocation hot path

- Recorded: 2026-08-06 06:22
- Updated: 2026-10-03 08:24 — Lean inline alloc/free paths, measured against mimalloc; a direct TEB read is not the lever.
- October 3, `bench/allocator` (median of five rotating rounds, through `Memory.alloc`): pair
  28.4 -> 26.5 ns, trees 34.4 -> 26.6 ns, churn 53.7 -> 49.2 ns, against 4.3 / 7.3 / 17.9 ns for
  mimalloc and 29.9 / 44.3 / 68.3 ns for the C heap. Native binarytrees paired median 0.87.
- `impl alloc` and `impl free` now try an inline path first (alignment up to 16, a page of the
  calling thread, no diagnostic mode, `slowPath` caches the mode test) and leave everything else
  to a non-inlined general path; panics moved out of line; page metadata is two cache lines.
- What is left per pair is code generation, not allocator work: two `getContext` calls, two
  interface calls, two `TlsGetValue` calls, and the prologues those calls force (five saved
  registers in each entry point). A C probe prices `TlsGetValue` at 0.85 ns against 0.60 ns for
  a direct `gs:[0x30]` TEB read, so a thread-block intrinsic would save about 1 ns per pair and
  is not worth new language surface; a leaf entry point without any call is what would pay.
- Next: once the backend can keep a call-free fast path a leaf (no callee-saved spills on the
  common path), re-measure pair/trees; otherwise look at `Memory.alloc`'s request setup.
- Complete when: generated-code attribution and comparable application/allocator measurements
  establish the remaining policy, preserving lifetime and error behavior.
- Related: runtime.allocator.001.

### runtime.allocator.004 — Make remote frees batched rather than one atomic each

- Recorded: 2026-08-05 10:27
- Updated: 2026-10-03 08:24 — Remote frees are now one compare-exchange from the inline path; batching not attempted.
- `pushRemote` links the block and publishes it with one compare-exchange; the owner takes the
  whole list with one exchange, so no ABA case exists (nothing is ever popped singly). The
  per-block `remoteCount` atomic is gone: `stats()` counts the list on demand under the page's
  `remoteLock`, which now only orders the owner's detach against that walk. A free of another
  thread's page block pushes from the inline path.
- `bench/allocator` xfer (producer/consumer pairs): 2 pairs 139 -> 111 ns, 4 pairs
  112.9 -> 94.8 ns per block, against 82.8 / 71.3 ns for mimalloc and 127.9 / 97.9 ns for the
  C heap.
- Next: measure whether a per-thread batch of remote blocks (one publication per batch) closes
  the remaining distance to mimalloc, and bound the owner's drain.
- Complete when: the selected synchronization policy has contention and p99 evidence plus
  concurrent retirement/adoption regression coverage.
- Related: runtime.allocator.001, runtime.allocator.003.

### runtime.allocator.001 — Add a reproducible allocator benchmark suite

- Recorded: 2026-08-05 10:27
- Updated: 2026-10-03 08:24 — `bench/allocator` exists and every campaign records it against mimalloc and the C heap.
- `bench/allocator/src/allocbench.swg` and `allocbench.c` run thirteen identical workloads (pair,
  trees, mixed churn, 4-64 KiB and 64 KiB-1 MiB live sets, realloc growth, a spread of live sizes,
  multi-thread churns, producer/consumer remote frees). The campaign's execution phase builds the
  C program over the vendored mimalloc and over the C heap, runs each workload in fresh pinned
  processes in rotating order, and records medians, peak working set and peak commit;
  `history.py` keeps the geometric means of Swag's ratios, and `bench.html` draws them.
  `bench/allocator/run.py` does the same without recording, with `--against` for an earlier build.
- Still missing from the original scope: p50/p99 latency per operation, OS-call counts and
  retained memory after idle and after `trim()`, aligned (32/64-byte) workloads, live-set growth
  without frees, and application traces. The parity gate below is not met yet.
- Define the parity gate before tuning: a geometric-mean throughput within 10% of mimalloc, no
  representative workload more than 25% slower, and no unbounded retained-memory case.
- Next: add latency percentiles and the missing workloads to `allocbench`, keeping the same
  output contract so the history stays continuous.
- Complete when: repeated comparable results cover the listed workloads and the existing parity
  gate, with application time, latency tails, retention, build settings and measurement limits
  recorded.

### runtime.allocator.017 — Medium pages commit all eight units for their first block

- Recorded: 2026-09-29 16:26
- Updated: 2026-09-29 21:24 — Loop headers are now 16-byte aligned; csvagg no longer depends on placement

**Evidence.** `acquirePage` commits a whole page before carving it: 64 KiB for a small class, 512 KiB for a medium one. A program holding two 48 KB blocks therefore pays for 512 KiB. On the bench, Swag leven commits 2.5 MB against 2.1 MB for C++ and wordfreq 26.2 MB against 25.7 MB. A candidate that commits a medium page one 64 KiB unit at a time — a carving limit set to the committed part, raised by the allocation slow path when the page looks exhausted, so the inlined fast path stays unchanged — brought leven to 2.1 MB and wordfreq to 25.5 MB. It was not landed: pinned, order-alternated runs showed csvagg 12-28% slower, although csvagg's timed section only makes eight small allocations. A control that only added dead code to `acquireBlockSlow` slowed csvagg by 12% too, and an A/A run gives 1.000, so csvagg's hot loop is sensitive to where the runtime code places it rather than to the allocator.

**Next.** The optimizing backend now starts every loop header on a 16-byte boundary, as LLVM does, so csvagg's scan loops no longer straddle a cache line when the code before them grows: its time is the same for every function order the compiler produces. Re-measure the medium-page design described above against that compiler.

**Complete when.** Every bench task commits no more than its C++ port, with pinned execution-time ratios within noise.

**Related:** compiler.core.005.

### runtime.allocator.008 — Add allocator OS-failure injection

- Recorded: 2026-08-06 06:22
- Updated: 2026-09-27 17:52 — define failure-injection acceptance at OS transitions.
- `bin/unittests/native/runtime/` covers size classes, page recovery from an address, free-list
  obfuscation, interior-pointer rejection, abandoned-page adoption, foreign-thread retirement
  through the FLS destructor, and a 32-thread abandon/remote-free/trim stress. What it does not
  cover is failure injection.
- Inject reserve and commit failures at every transition and verify that page masks, segment lists,
  and the abandoned list stay consistent and that the allocation returns null rather than a
  half-built page.
- Related: platform.portability.089, platform.portability.004

- Complete when: Focused native tests force each reserve and commit failure path, verify page masks, segment and abandoned lists stay valid, and confirm allocation returns null without leaked or partially published pages.

### runtime.allocator.006 — Huge allocations have no separately measured policy

- Recorded: 2026-08-09 11:30
- Updated: 2026-09-27 17:52 — define a measurable huge-allocation contract.

Define the threshold and reserve/commit/release behavior for genuinely huge allocations after the
medium tier is separated. Benchmark large growth and release independently of size-class caching.

- Related: runtime.allocator.001, runtime.allocator.005

- Complete when: The huge-allocation threshold and reserve/commit/release policy are documented and tested, and isolated large-growth and release benchmarks report latency and memory retention separately from size-class caching.

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
