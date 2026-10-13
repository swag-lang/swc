# Runtime Allocator Backlog

This backlog tracks the performance, memory, and safety contracts still required for the Swag
runtime allocator to demonstrate behavior comparable to the vendored
[mimalloc](../src/Support/Memory/mimalloc/readme.md). The C++ compiler already uses mimalloc
through `src/Support/Memory/Allocator.cpp`. [README.md](README.md) defines the backlog format;
completed implementation history lives in Git.

The page path serves requests up to 64 KiB with alignment at most 64 bytes. Blocks carry no
header and recover their page from their address. Larger or over-aligned requests and diagnostic
modes use the header path. There are 45 size classes from 8 bytes through 64 KiB, using 64 KiB
or 512 KiB pages inside 4 MiB segments. Each thread heap has a current page per class, and local
allocation/free lists avoid locks and atomics.

Preserve allocation, failure, ownership, and diagnostic behavior while tuning. Measurements must
touch payloads and distinguish working set, committed bytes, and reserved address space. Use
runtime.allocator.001's comparable workloads and parity gate before deciding whether to retain or
replace the allocator; a similar architecture alone does not establish comparable behavior.

### runtime.allocator.018 — Diagnostic allocation does not intercept a stale heap read

- Area: runtime/allocator, `bin/runtime`
- Evidence: lifecycle guards poison moved or dropped storage. The runtime allocator also supports
  allocation tracking, freed-byte fill, a bounded diagnostic quarantine, double-free diagnostics
  and electric allocations next to a guard page, with alignment slack for non-multiple sizes.
  Electric mode retains freed addresses, but `freeHeaderBlock` leaves their payload readable
  and writable. `checkFree` checks only header/footer magic; it does not verify the freed payload
  pattern. `allocator_debug_modes.swg` explicitly reads the freed pattern.
  Ordinary page allocations reuse storage and provide no stale-read instrumentation.
- Next: evaluate a diagnostic mode that makes a freed payload inaccessible while retaining enough
  metadata to diagnose release errors, or instrument reads. Measure its cost on an application
  workload and specify how it composes with the existing electric/quarantine modes.
- Done when: a stale read through an alias is detected at the read in the selected diagnostic
  mode, with its limits and measured cost documented; Release defaults remain unchanged.
- Related: runtime.allocator.010.

### runtime.allocator.002 — Close the remaining distance on the allocation hot path

- Evidence: repeated release allocator measurements still leave `pair`, `trees`, mixed small
  allocations, and concurrent large blocks materially slower than mimalloc. The ordinary Core
  allocation path is scalar and inline, while `Memory.free` constructs an `AllocatorRequest`
  and dispatches through `IAllocator.free`. Allocation and free each read the context; the page
  path also reads its own thread-local heap slot.
- Next: reduce the remaining request, dispatch, and thread-local lookup work, using the emitted
  common path to attribute the gain. A scalar `Memory.free` kept out of line improved `pair`
  but did not improve mixed live-set workloads; do not select that shape from `pair` alone.
  Outlining allocation fallback and moving OS operations outside cache/segment locks likewise
  need evidence beyond an initial favourable window before being reconsidered.
  Assess any direct small-size page index separately: its standalone mixed-size and application
  checks did not establish the gain seen when combined with other allocator layout changes.
  Compare the TLS lookup in `freeFast` with the vendored mimalloc's page-local thread token
  check (`mi_free_ex` and `_mi_prim_thread_id`). A token experiment must store its identity in
  the page and preserve retirement publication; a remote free must not dereference an owner
  heap that another thread can destroy.
  Outlined 32/64-byte fast allocation improved aligned batches but regressed the ordinary
  allocation/free pair by about 11%. Before retrying it, inspect the default-alignment caller's
  generated code and layout, and require repeated ordinary-workload controls. Keep class
  rounding outside inline callers until compiler.optimization.129 is fixed.
- Preserve the release contract before inlining a scalar free. The interface call supplies
  `SanityRelease` for `request.address`; merely calling `freeFast` loses that boundary. A private
  freeing helper inside an inline public wrapper must also retain the caller's diagnostic
  location. Use `inline_allocator_free.swg`, `use_after_free_parameter_location.swg`, and the
  imported `lifecycle_summary.test.swg` boundary, together with custom allocator and diagnostic
  mode tests. Related compiler work: compiler.optimization.113 and compiler.optimization.114.
- Measurement limits: use rotating before/after runs and identical-binary controls, inspect
  within-window variation, and repeat concurrent workloads. Admission alone cannot detect work
  that starts during a measurement. Also compare independently rebuilt controls when application
  timings move without changed application micro-instructions: code/data placement needs its own
  attribution. The short `spread` workloads still include thread lifecycle
  costs (runtime.allocator.001). Large-block peak working set remains substantially below
  mimalloc's; preserve that distinction from the idle-retention question.
- Done when: generated-code attribution and repeated application/allocator measurements meet
  runtime.allocator.001's throughput and retention gate without losing allocator contracts.

### runtime.allocator.001 — Complete comparable allocator workload and retention measurements

- `bench/allocator/src/allocbench.swg` and `allocbench.c` provide fourteen single-thread and
  concurrent workloads, including live-set growth without frees, plus opt-in `aligned` and
  `aligned:4` batches with alternating 32/64-byte alignment. The harness records medians,
  peak working set, and peak commit in fresh pinned processes and rotates implementation order.
  The remaining scope is operation-level p50/p99 latency, OS-call counts, retained memory after
  idle and `trim()`, and representative application traces.
- Timing boundary: both programs start the clock before thread creation. Swag uses suspended
  creation, resume, inherited context setup, and per-thread wait/handle close; C starts threads
  immediately and stops after a combined wait without closing their handles inside the interval.
  `spread` performs only 120 allocations per worker. Its end-to-end result is therefore a cold
  allocator plus thread-lifecycle measurement, not steady-state allocation throughput.
- October 5 probe: thirty-one rotating rounds at one/eight threads, including the same Swag
  executable twice. Each worker also times its workload body; the empty variant immediately
  returns the same nominal operation count. Medians in microseconds:

| Threads | Probe | Wall time | Maximum worker body |
| ---: | --- | ---: | ---: |
| 1 | swag_full | 260.0 | 80.0 |
| 1 | swag_control | 281.0 | 85.0 |
| 1 | swag_empty | 182.0 | 0.0 |
| 1 | mimalloc_full | 278.5 | 156.0 |
| 1 | mimalloc_empty | 135.3 | 0.3 |
| 8 | swag_full | 946.0 | 271.0 |
| 8 | swag_control | 834.0 | 260.0 |
| 8 | swag_empty | 649.0 | 4.0 |
| 8 | mimalloc_full | 907.3 | 481.7 |
| 8 | mimalloc_empty | 463.2 | 0.4 |

- A second scratch probe repeats the same spread body 10,000 times per worker, amortizing
  startup over 1.2 million allocation/free pairs. Fifteen rotating rounds, medians in ns/pair:

| Repeated workload | Swag | A/A control | mimalloc |
| --- | ---: | ---: | ---: |
| spread | 19.3 | 19.1 | 25.4 |
| spread:8 | 26.0 | 21.1 | 9.1 |

- This repeated variant changes page/cache reuse and has no synchronized worker start, so it
  complements the original cold workload rather than replacing its result. Raw accepted samples
  and matching C/Swag sources are in `warm-spread/` under the evidence directory.
- The empty variant changes the executed allocator work and generated layout; its result is a
  lifecycle control, not an exact subtractable allocator cost. Worker intervals overlap, and
  timing their maximum does not measure a synchronized steady-state phase. Sources, build logs,
  samples, and the probe script live under `%TEMP%/swc-runtime-allocator-20261005/thread-cost/`
  and `probe_thread_cost.py` in the parent directory.
- Next: preserve the existing end-to-end metric and add separately reported worker timing plus
  a synchronized, repeated allocation phase that amortizes thread startup. Match lifecycle and
  cleanup boundaries in the Swag and C harnesses before using a short workload to select an
  allocator change. Then add latency percentiles and the missing retention workloads.
- Parity gate: geometric-mean throughput within 10% of mimalloc, no representative workload
  more than 25% slower, and no unbounded retained-memory case.
- Done when: repeated comparable results cover the listed workloads and parity gate, with
  application time, latency tails, retention, build settings, and measurement limits recorded.

### runtime.allocator.010 — Decide what the security properties are, and write them down

- Free-list heads are plain addresses in the page metadata and every stored link is keyed, the
  end of a list included, and a block handed out has its first word cleared. A free block
  therefore reads as one from its first word: `looksFree` tests it on every free, and only a
  match (a live block matches by coincidence about once in 2^40 frees) walks the lists. The
  owner checks its own and the remote list, another thread the remote list. The A, B, A
  sequence that used to create a cycle now panics with "memory block is freed twice"
  (`allocator_coverage.swg`); a panic hook that resumes leaves the lists intact. Corrupted
  links are still rejected at pop and collect time.
- Since October 3 every check above, the canary, the corrupted-link and block-address tests, the
  double-free walk and the header and footer checks of large blocks, runs only when
  `Swag.SafetyWhat.Memory` is in `safetyGuards` (`#static if #safety(...)` in the allocator
  sources): devmode has it, release does not, and a release build that wants them adds the bit
  to its build configuration. Free-list links stay keyed in both. `assertIsAllocated`, which a
  caller asks for explicitly, and the diagnostic modes keep their checks.
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
  Stale-read interception is already owned by runtime.allocator.018; retaining an address is not
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
- Done when: every claimed guarantee has a focused regression and accurate documentation,
  with explicit limits for reuse, alignment slack, quarantine lifetime and payload checking.
- Related: runtime.allocator.018, runtime.allocator.001.

### runtime.allocator.003 — Return idle memory without being asked

- An emptied page now returns to its segment still committed while the process-wide idle budget
  allows (a quarter of the committed bytes, at least 8 MiB), and any class reuses it without a
  system call; past the budget it is decommitted. `trim()` decommits the idle pages of every
  segment, teardown those of the segments it releases, and `trim()` also gives the large-block
  cache back. The cache's budget follows the bytes held
  live through the header path (at least 16 MiB, at most 256 MiB, 64 entries).
- Measured on `bench/allocator` medium (256 live 4-64 KiB blocks): 213 -> 51 ns per operation,
  peak working set 11.8 -> 19.8 MB (mimalloc 36.5 ns, 19.2 MB). A 2 MiB / one-eighth budget
  brings the working set back to 13.4 MB and the time back to 242 ns: the budget is the trade.
- Purge: the first slow path that sees idle memory arms a 500 ms deadline; the first one past
  it decommits every idle page of the allocator and the cached blocks freed longer ago than the
  delay. Page refills read the clock one time in 64, large frees every time; the micro-benchmarks
  do not move. After a 24 MB burst followed by light activity, committed memory falls to under
  1 MB within the second instead of staying at 24 MB.
- Still open: nothing runs in the background, so a program that stops allocating altogether keeps
  its idle memory until it allocates again, trims, or exits (as mimalloc without its purge
  thread); an inactive live owner keeps its remotely returned blocks uncollected.
- Next: measure burst/idle with an owner kept alive, and decide whether the delay should follow
  the memory pressure the host reports.
- Done when: the current pages, remote returns, abandoned pages and header cache have tested
  idle/trim behavior and documented bounds.
- Related: runtime.allocator.001, runtime.allocator.004, runtime.allocator.005.

### runtime.allocator.005 — Scale the large-block cache with threads

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
- Next: resolve application timing sensitivity before selecting a lock-layout change. Moving
  counters under the existing list lock and separating lock cache lines improved concurrent large
  blocks, but did not consistently preserve `wordfreq` timing, whose measured body makes few
  allocations. Then measure a small per-thread front for the cache, and a header list that does
  not need the allocator-wide lock outside the diagnostic modes.
- Done when: four threads cycling large buffers are within the parity gate of
  runtime.allocator.001 without more retained memory than mimalloc.
- Related: runtime.allocator.001, runtime.allocator.003, runtime.allocator.006

### runtime.allocator.004 — Make remote frees batched rather than one atomic each

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
- Done when: the selected synchronization policy has contention and p99 evidence plus
  concurrent retirement/adoption regression coverage.
- Related: runtime.allocator.001, runtime.allocator.003.

### runtime.allocator.017 — Medium pages commit all eight units for their first block


**Evidence.** `acquirePage` commits a whole page before carving it: 64 KiB for a small class, 512 KiB for a medium one. A program holding two 48 KB blocks therefore pays for 512 KiB. On the bench, Swag leven commits 2.5 MB against 2.1 MB for C++ and wordfreq 26.2 MB against 25.7 MB. A candidate that commits a medium page one 64 KiB unit at a time — a carving limit set to the committed part, raised by the allocation slow path when the page looks exhausted, so the inlined fast path stays unchanged — brought leven to 2.1 MB and wordfreq to 25.5 MB. It was not landed: pinned, order-alternated runs showed csvagg 12-28% slower, although csvagg's timed section only makes eight small allocations. A control that only added dead code to `acquireBlockSlow` slowed csvagg by 12% too, and an A/A run gives 1.000, so csvagg's hot loop is sensitive to where the runtime code places it rather than to the allocator.

**Next.** The optimizing backend now starts every loop header on a 16-byte boundary, as LLVM does, so csvagg's scan loops no longer straddle a cache line when the code before them grows: its time is the same for every function order the compiler produces. Re-measure the medium-page design described above against that compiler.

**Done when.** Every bench task commits no more than its C++ port, with pinned execution-time ratios within noise.

**Related:** compiler.core.005.

### runtime.allocator.006 — Huge allocations have no separately measured policy


Define the threshold and reserve/commit/release behavior for genuinely huge allocations after the
medium tier is separated. Benchmark large growth and release independently of size-class caching.

- Related: runtime.allocator.001, runtime.allocator.005

- Done when: The huge-allocation threshold and reserve/commit/release policy are documented and tested, and isolated large-growth and release benchmarks report latency and memory retention separately from size-class caching.

### runtime.allocator.007 — Tune size classes from traces rather than from the table

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
- Done when: a trace-backed decision covers both internal fragmentation and per-thread
  page retention, including very small and aligned allocations.
- Related: runtime.allocator.001, runtime.allocator.003, runtime.allocator.005.
