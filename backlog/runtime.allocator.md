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
- The gated `spreadrep:8` workload runs at about three times mimalloc's per-worker time while
  `spreadrep` alone runs faster than mimalloc: a class whose ten blocks need a second page
  retires that page when it empties and claims it again under the segment mutex on every
  round, which eight threads contend for. Measure keeping one emptied page per class on the
  heap before retiring further ones.
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
  concurrent workloads, including live-set growth without frees, plus opt-in `aligned` batches,
  `huge` blocks, the gated repetition `spreadrep` and the retention run `retain`. Every run also
  reports the slowest worker's time per operation beside the end-to-end figure, and `--latency`
  reports per-operation 50th and 99th percentiles. The harness records medians, peak working
  set, and peak commit in fresh pinned processes and rotates implementation order. The remaining
  scope is OS-call counts and representative application traces.
- Timing boundary: both programs start the clock before thread creation and close the worker
  handles inside it; the Swag program also creates its threads suspended and resumes them with a
  context to inherit, which the worker timing excludes.
- Next: run the campaign with the gated and latency figures on a quiet machine and record
  them, then add OS-call counts to the Swag program's statistics output.
- Parity gate: geometric-mean throughput within 10% of mimalloc, no representative workload
  more than 25% slower, and no unbounded retained-memory case.
- Done when: repeated comparable results cover the listed workloads and parity gate, with
  application time, latency tails, retention, build settings, and measurement limits recorded.

### runtime.allocator.005 — Scale the large-block cache with threads

- Header-path blocks are reserved at one of eight sizes per power of two and commit only what the
  request reaches; freed ones go to a best-fit cache (up to twice the request) indexed in the
  allocator, behind a per-thread front of the last sixteen blocks a thread freed under 2 MiB,
  which its own requests take without a lock. The list of ordinary live headers is sharded eight
  ways by address, and only the live byte count moves on every operation.
- Remaining: `large:4` (four threads cycling 64 KiB-1 MiB buffers) runs at about 1.26 times
  mimalloc's time, against the 1.25 gate of runtime.allocator.001, at about half its peak working
  set. What is left per operation is the live-byte atomic, the shard lock when the front misses,
  the clock read on free, and the global cache lock on a front miss.
- Next: measure a front keyed by size class rather than best-fit, and the cache lock held only
  when the front has no candidate, on `large:4` with rotating runs and the application check.
- Done when: four threads cycling large buffers are within the parity gate of
  runtime.allocator.001 without more retained memory than mimalloc.
- Related: runtime.allocator.001

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
- Related: runtime.allocator.001.

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
- Related: runtime.allocator.001, runtime.allocator.005.
