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

- Evidence: release measurements leave `pair`, `trees`, mixed small allocations, and
  concurrent large blocks materially slower than mimalloc. Under `spreadrep:8`, threads still
  contend on the segment mutex for pages a class acquires beyond its retained spare. Inline
  `Memory.free` builds an `AllocatorRequest` and dispatches through `IAllocator.free`.
  Allocation and free each read the context, and the page path also reads its thread-local
  heap slot.
- Next: reduce the request, dispatch, and thread-local lookup work, attributing each gain from
  the emitted common path. A cold `Memory.alloc` request helper, dense current-page pointers,
  and a page-local Windows owner token with a direct native thread-id load did not improve
  mixed-size and concurrent workloads consistently. Attribute `Memory.free`'s request stores,
  dispatch, and code/data placement before retrying those shapes. Any owner token must live in
  the page, preserve retirement publication, and never let a remote free dereference an owner
  heap that another thread can destroy.
- Rejected shapes, not to be retried without new evidence: an out-of-line scalar
  `Memory.free`, which helped only `pair`; an outlined 32/64-byte fast allocation, which made
  the ordinary pair about 11% slower (inspect the default-alignment caller's code and layout
  first); a standalone direct small-size page index; and outlined allocation fallback or OS
  calls moved outside cache/segment locks. Class rounding inside the inline fast path may be
  retried, because frame compaction now drops folded-away branch storage.
- Constraint: an inlined scalar free keeps the `SanityRelease` boundary on `request.address`
  and the caller's diagnostic location. Guard it with
  `bin/unittests/sanity/inline_allocator_free.swg`,
  `bin/unittests/sanity/use_after_free_parameter_location.swg`, `lifecycle_summary.test.swg`,
  and the custom-allocator and diagnostic-mode tests.
- Measurement: use rotating before/after runs, identical-binary controls, and repeated
  concurrent workloads. Attribute code/data placement separately when application timings
  move without changed micro-instructions.
- Done when: generated-code attribution and repeated application/allocator measurements meet
  runtime.allocator.001's throughput and retention gate without losing allocator contracts.
- Related: runtime.allocator.001, compiler.optimization.113, compiler.optimization.114

### runtime.allocator.001 — Complete comparable allocator workload and retention measurements

- Evidence: `bench/allocator` (`allocbench.swg`, `allocbench.c`, `run.py`; protocol in its
  README) measures the synthetic, gated (`spreadrep`), latency, system-call, and retention
  (`retain`) figures in fresh pinned processes with rotated order. No quiet-machine record of
  those figures exists, and no representative application trace is measured.
- Next: run and record the campaign with the gated, latency, and system-call figures on a quiet
  machine, then add representative application traces.
- Parity gate: geometric-mean throughput within 10% of mimalloc, no representative workload
  more than 25% slower, and no unbounded retained-memory case.
- Done when: repeated comparable results cover the listed workloads and parity gate, with
  application time, latency tails, retention, build settings, and measurement limits recorded.

### runtime.allocator.005 — Scale the large-block cache with threads

- Evidence: header-path blocks are freed into a best-fit cache (up to twice the request, 256
  entries inside the byte budget), behind a lock-free per-thread front of the last sixteen
  blocks under 2 MiB, with live headers sharded eight ways. On a front miss, each operation
  still pays the live-byte atomic, the shard lock, the clock read on free, the global cache
  lock with its linear best-fit scan, and page faults on blocks fresh from the system.
  `large:4` reaches the throughput gate in the
  [controlled comparison](../bench/results/allocator/20261018/README.md), but the machine is
  shared and mixed-workload retention after `trim()` remains above mimalloc.
- Next: separate retained current-page bytes from header-cache bytes, then repeat `large:4`
  and representative application traces on a quiet machine before changing the front policy.
- Done when: four threads cycling large buffers are within the parity gate of
  runtime.allocator.001 without more retained memory than mimalloc.
- Related: runtime.allocator.001

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
