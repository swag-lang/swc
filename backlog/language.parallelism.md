# Native Parallelism and Concurrency

This domain owns the native concurrency model: structured tasks, checked memory access, parallel
computation, suspension, cancellation, and the runtime contract that connects them. It covers
both simultaneous CPU execution and concurrent operations that mostly wait.

The first stage has shipped: `parallel for` is a language statement, and `bin/runtime` owns the
worker pool, tasks, groups, locks, conditions, and atomics that every module and application now
uses. What remains here is the part that is still design plus implementation. Shipped behavior is
documented in the language reference and in the runtime sources, not here.

All new Swag types of this concurrency system belong to `bin/runtime`. Library algorithms and
consumer migration stay in [std.core.md](std.core.md), general memory-safety prerequisites in
[compiler.safety.md](compiler.safety.md), and operating-system adapters in
[platform.portability.md](platform.portability.md).

## Vocabulary

| Term | Meaning in this domain |
| --- | --- |
| Task | A logical computation owned by a group or supervisor, with one eventual terminal outcome. |
| Group | An owner that limits child lifetime, propagates policy, and joins accepted work before releasing its resources. |
| Operation | An awaitable action, such as a receive or I/O request; it need not allocate another task. |
| Executor | The authority that schedules accepted continuations under a placement and affinity contract. |
| Region | Storage and aliases connected by ownership/access relationships that the compiler must track. |
| Isolation domain | An authority that controls access to mutable state; it is not necessarily a dedicated physical thread. |
| Cancellation | A request to stop, whose acknowledgement and cleanup occur before actual completion. |
| Data race | Conflicting unsynchronized accesses to the same memory, with at least one write. |
| Logical race | An incorrect result caused by operation ordering, even when all memory accesses are synchronized. |

## Entries

### language.parallelism.008 — A parallel loop cannot combine per-partition results

- Evidence: every partition of a `parallel for` receives the same captures. A loop that computes
  one value -- a sum, a maximum, a count, a first match, an accumulated bounding box -- cannot
  say that each partition needs its own accumulator and that the accumulators combine at the
  join. Consumers write one of two workarounds: an atomic on the shared destination, which
  serializes the loop's hot line and, with `AtomicValue.store` lowered to a locked exchange,
  pays a full barrier per iteration; or an array indexed by a partition number the language does
  not expose, which forces the body to know the partitioning it is explicitly told not to depend
  on.
- Evidence: the general escape, one accumulator per thread, is also expensive. Every access to a
  `tls` global calls the runtime's `__tlsVarPtr`
  (`CodeGenMemoryHelpers::emitGlobalVariableAddress`), which reads the global's slot identifier
  with an atomic compare-exchange before the host thread-storage lookup; the direct slot load of
  `2f353d606` serves only the runtime context. The per-thread block is released at thread exit
  without running `opDrop`, so it can only hold a plain value.
- Next: design the combining form as part of the statement, stating the identity, the
  per-partition storage and the combining operation together, and combining at the join rather
  than in the body. Settle whether the operation must be associative and commutative or only
  associative -- floating-point addition is not associative -- and say what result the program is entitled
  to when it is not. Decide whether the form is a clause of `parallel for` or a value the
  statement produces.
- Done when: a parallel sum, a parallel maximum and a parallel bounding box are written
  without an atomic on the hot line and without indexing a partition, and a single-worker run of
  the same source produces the same value the loop promises.
- Elsewhere: OpenMP has `reduction(+:x)` and user-declared reducers; Rayon, .NET PLINQ and Java
  streams reduce through the iterator; Chapel writes `+ reduce`. All of them treat reduction as
  the second data-parallel primitive after the map, not as a library afterthought.
- Related: language.parallelism.001, language.parallelism.004, std.core.025

### language.parallelism.005 — Captures do not prove task lifetime or race freedom

- Evidence: borrow analysis follows named and initialized captures, including addresses, field
  references, slices, aggregates and deferred call-result summaries. It rejects the tested local
  borrows returned in a closure or stored in a task from an outer lexical scope. Local destructor
  ordering also matters: a task declared before its captured source joins after that source is
  destroyed. Borrow merges retain the shortest local lifetime across captures, fields and flow
  alternatives. The unexecuted regression cases are in
  `bin/unittests/sanity/borrow_escape_drop_order.swg`. This does not
  establish race freedom: two partitions writing the same element and a captured pointer whose
  pointee is mutated elsewhere still compile.
- Linked-storage gap: the group no longer demonstrates it. `Swag.TaskGroup` holds its first
  children itself, so `reserveChild` can return a pointer into the group, `spawn` feeds a
  stores-into-group summary, and `groupBeforeCapture` in
  `bin/unittests/sanity/borrow_escape_drop_order.swg` is rejected with its expected diagnostic.
  The rule itself did not change: only block pointers carry owned payload, because treating every
  `*T` as owned would confuse parent and callback back-references with ownership, so a child
  reached solely through `blocks: *GroupBlock?` is still invisible to the ownership analysis.
  Find or build another case before extending the rule to linked storage.
- Both `Swag.Task.opDrop` and `Swag.TaskGroup.opDrop` join their work, including on early return
  and failure. An owner can still release a borrowed field in its own destructor before the
  implicit destruction of its task field; it must join before releasing that storage.
- Next: follow owned linked storage through accessors, with both an owned child and a non-owned
  parent pointer as regression cases. Then infer transferable (`Send`) and shared-readable
  (`Sync`) properties from fields, allocation, copy, move and destruction effects, and require
  them at captures. `NoCopy` does not imply `Send`, `const` does not imply deep immutability, and
  an atomic reference count does not synchronize its pointee. Raw pointers, opaque owners, native
  handles and foreign calls need a stated contract rather than automatic acceptance.
- Done when: a rejected capture names the concrete alias, allocator, destructor or executor
  constraint and points at a valid partition or ownership alternative; semantic tests reject
  hidden aliases, escaped borrows and cross-module global writes without optional analysis.
  Until then the capture list states intent rather than proving race freedom.
- Related: compiler.safety.006, compiler.safety.007, compiler.safety.014,
  language.parallelism.001.

### language.parallelism.001 — The shipped model, and the promises it does not yet make

- Evidence: `parallel for`, `Swag.Task`, `Swag.TaskGroup`, the runtime locks, conditions,
  semaphores, barriers, atomics, `Swag.Executor` and the language reference's memory model
  are shipped.
- What the model does not yet promise: race freedom. The capture list is written, not proved
  (.005); a partition can fail but cannot state disjointness (.004); there is no UI or blocking
  executor and no affinity rule beyond submitting to a dedicated executor (.003); nothing suspends (.002). A program can
  still write a data race through a capture, and the compiler accepts it.
- Next: the four foundational entries (.002 through .005) remain, in dependency order:
  suspension and typed results, then executors, then partition proofs, then checked captures.
  Keep this entry as the place that states the whole contract, and let each of them own its part.
  Do not advertise race freedom in the reference or in the runtime documentation until .005 holds.
- Done when: those four foundational entries are closed and the language reference states one contract for
  ownership, suspension, cancellation, failure and memory access that the compiler enforces.
- Related: std.core.025, language.parallelism.011, std.core.028, compiler.safety.006,
  compiler.safety.007, compiler.safety.014, platform.portability.035.

#### Progress and memory-model boundaries that already apply

These hold for the shipped model and constrain every entry in this domain.

| Construction | Progression boundary |
| --- | --- |
| Finite independent kernels and descendant-only fork/join | Completes with one worker if the sequential computations terminate and the executor services ready work. A `parallel for` and a joined `Swag.TaskGroup` are in this class. |
| Ranked locks | Prevent acquisition cycles only while all acquisitions obey the declared order. Nothing declares one yet. |
| Explicit task graph | Reject cycles when constructing or extending the dependency graph; other waits in node bodies need their own contract. |
| General channels, promises, actors, leases | Safe memory access does not prove the communication protocol terminates. |
| Foreign waits and external systems | Require explicit backend contracts; no universal deadline or deadlock guarantee. |

A joining thread can claim the queued task it is waiting for, and that task can join its own
children in turn. It does not execute unrelated ready tasks: a guard held across a join must
not be reentered by an unrelated callback. With no worker, submission executes synchronously.
An explicit `Swag.drainWork` still runs arbitrary accepted work and needs a context that permits
that reentrancy. Joining a task that itself needs a held lock can still deadlock; targeted helping
does not prove a task dependency graph or lock ordering correct.

A join briefly polls a running child, then parks on the process scheduler's completion condition.
A parked observer first publishes the address of the node it waits for, and a completion consults
that registry instead of the node it has just released: an owner can already have reused or freed
its node, so nothing reads it once Done is published. A completion therefore wakes observers only
for a node somebody waits for, and every woken observer still rechecks its own state. A process
with more parked observers than registry slots falls back to waking all of them, which is correct
and unselective. Parking reduces waiting CPU use but still occupies the calling thread and any
worker that called the join. It is not the stackless suspension or executor capacity release required by .002 and .003.

The scheduler's artifact-local cache publishes its pointer atomically after serialized first use.
The worker count is also atomic, while roster growth stays under the pool mutex; callers can
submit and inspect the pool while other callers increase its size. Runtime shutdown still assumes
its users have quiesced: atomic publication is not an admission or cancellation protocol for late
submissions during teardown.

#### Workloads still to be answered

These remaining workloads are acceptance cases for the entries in this domain.

| Workload | Desired expression | Adversarial case to settle | Evidence required |
| --- | --- | --- | --- |
| Bounded streaming pipeline | Transferred buffers and finite-capacity channels. | Consumer stops while producer is blocked; one stage fails after a partial transfer. | Every buffer and rejected message has an owner; failure closes and drains the pipeline under its stated policy. |
| Recursive CPU work | Nested structured tasks or parallel partitions. | One worker and an exhausted task-lifetime quota. | No hidden quota wait cycle, bounded bookkeeping, and equivalent completed results. |
| Dependency graph | Typed nodes with explicit result edges. | A dynamic edge introduces a cycle, or one node awaits an unrelated external event. | Cycle rejection for graph edges; no false claim that arbitrary node bodies are deadlock-free. |
| Foreign blocking operation | A task scheduled on the blocking or dedicated executor. | The operation ignores cancellation or synchronously calls back into the host. | Borrowed resources survive; callback and runtime attachment stay valid; no unsupported timeout bound is promised. |
| Lock-free shared structure | Typed atomics with a reclamation domain. | ABA, a stalled reader, and reclamation during shutdown. | Storage lifetime is justified separately from atomic ordering; the unchecked implementation boundary is explicit. |
| Latency-sensitive audio | Dedicated execution, preallocated memory, no-allocation and no-wait contracts. | A device callback that must never allocate or block. | The contract is checked rather than documented; no hard real-time guarantee is claimed on a general-purpose operating system. |

For each case, record the source size, annotations, explicit clones, unchecked escapes,
allocations, and runtime costs the preferred path needs. A short keyword example is not evidence
of simplicity when every useful helper needs an unchecked contract.

#### Validation that every entry here inherits

- Semantic tests accept safe transfers and partitions and reject hidden aliases, cross-module
  global writes, escaped borrows, incompatible callable effects, and wrong-executor destruction.
  A guarantee that only a warning or a devmode guard enforces is not the guarantee.
- A runtime-only consumer declares and uses the concurrency types without importing Core, and a
  sequential program starts no execution resource it never asked for.
- Native and JIT lifecycle tests cover every exit after capture, including failed admission before
  capture, a failing later capture after an earlier move, and serial fallback after partial
  dispatch.
- A controlled scheduler and a fake backend enumerate cancellation before publication, during
  registration, at commit, after completion, and during cleanup, together with simultaneous
  completions, withdrawn channel operations, producer abandonment, and late native callbacks.
- Runtime tests distinguish one worker from several, nested fork/join, quota exhaustion, pool
  shutdown, and a stalled foreign call. Soundness is not inferred from stress testing.
- Consumer evidence comes from a real pixel operation, a real GUI background lifecycle, and a real
  native-affinity operation. Measure creation and join cost, memory per live task, queue
  contention, cancellation latency under stated cooperation assumptions, serial thresholds, and
  throughput against what the code did before.
- Every implemented syntax change updates the language reference, the editor grammar, the
  formatter and the relevant diagnostics together. Keep `SWC_BUILD_NUM` stable during ordinary
  compiler changes; change it only for an explicit release or cache-identity decision. Isolate or
  clear affected caches when validating changed compiler behavior. Serialized effect summaries
  and runtime ABI changes must invalidate incompatible cached artifacts.

### language.parallelism.002 — Nothing suspends

- Evidence: [Swag.Task'T](../bin/runtime/task.swg) hands its value or its error to one observer
  through `take`, and its destruction asks the body to stop before joining it. Cancellation is a
  request the body reads, not an outcome: it returns a partial value or fails, and
  `Task.waitUnlessCancelled` lets a waiting task give up as soon as it is asked to stop. But a task
  that waits -- for another task, a lock, a foreign call -- still occupies its worker for the whole
  wait, reducing the capacity available to execute queued operations; Prism's build lease is such a
  wait.
- Next: settle the suspension gates before implementing. Fix the `async`/`await` grammar, the
  effect in the callable type, stackless frame ownership, stable frame addresses, and the async
  boundary for both native and JIT execution. Decide what `try`, a catch-all, `defer #fail` and
  `defer #nofail` observe across a suspension point.
- Done when: an awaiting task releases its worker, and native and JIT lifecycle tests cover every
  exit after capture: immediate completion, a suspended frame, a cancelled waiter whose child
  still owns a loan, and destruction exactly once.
- Elsewhere: [Swift structured concurrency](https://github.com/swiftlang/swift-evolution/blob/main/proposals/0304-structured-concurrency.md)
  scopes child-task lifetime; [Go's memory model](https://go.dev/ref/mem) makes synchronization and
  happens-before part of the language contract. These are references for separate decisions, not a
  proposal to import one language's complete model.
- Related: std.core.025, std.core.028, language.parallelism.001.

### language.parallelism.010 — Nothing detects a data race while the program runs

- Evidence: .005 states that a capture list is written rather than proved, and names the two cases
  that still compile: two partitions writing the same element, and a captured pointer whose
  pointee is mutated elsewhere. Neither is caught at run time either. The `devmode` configuration
  checks allocation lifetime and bounds, and the sanity pass reasons inside one function's flow,
  but no configuration records happens-before edges between threads. A race in a partitioned loop
  therefore surfaces as an occasional wrong pixel or an intermittent crash somewhere unrelated,
  which is the shape of several intermittent defects already recorded in this repository.
- Next: choose the instrument before writing it. Only a checker that knows the runtime's own
  synchronization points -- lock, unlock, atomic operation, submission, completion, join, and
  partition boundary -- can see the edges this runtime creates, so the shadow state belongs
  beside the scheduler rather than in a foreign tool. The edges to record are the ones the
  memory model of the language reference lists. Scope it to one build configuration with a
  stated slowdown budget, start from the accesses the compiler already instruments for bounds and
  lifetime, and decide what it does with a foreign call, which is opaque to it for the same reason
  it is opaque to compiler.safety.007.
- Done when: a test writing one element from two partitions fails deterministically in that
  configuration, naming both accesses and the edge that is missing between them, and a correct
  partitioned loop reports nothing.
- Elsewhere: Go ships `-race`, C++ and Rust use ThreadSanitizer, and Rust adds `loom` for
  exhaustive interleavings of a small structure. A language that claims checked memory access
  without a dynamic detector claims it only as far as its static analysis reaches.
- Related: language.parallelism.005, compiler.safety.007, compiler.safety.014

### language.parallelism.009 — Cancellation has no deadline and wakes no wait

- Evidence: the request is ambient: `Swag.isCancelled` answers for the running task, task-group
  child or `parallel for` partition, and a group or loop started inside cancelled work inherits
  the request. A `Swag.Task` deliberately does not inherit it, because it can outlive the work that
  submitted it; dropping it cancels it instead. A request wakes a task parked in
  `Task.waitUnlessCancelled`. Swag Vault's progress still keeps a cancellation flag of its own. No
  task, group or loop carries a deadline: a program that wants to stop after a duration polls a
  clock it wrote itself. The request is also invisible to the waiting primitives:
  `Swag.Condition.waitFor` expires on its own timeout without consulting it, and
  `Swag.Semaphore.acquire` and `Swag.Barrier.arrive` cannot be woken by it.
- Next: make a deadline one more source of the same request rather than a second mechanism, then
  migrate Swag Vault's flag to `Swag.isCancelled`. State the boundary at the waiting
  primitives instead of implying it: today `acquire` has no cancellation input or wake path.
  A cancellation-aware blocking wait can return early without async suspension; define its
  wake registration, permit-consumption race, and cleanup independently of .002.
- Done when: a deadline produces the same observable request, a cancelled wait returns early, and
  no consumer keeps a cancellation flag of its own.
- Elsewhere: Swift propagates cancellation to every child task and exposes it as task-local
  state; Kotlin cancels a `Job` together with its children; Java's `StructuredTaskScope` and
  .NET's linked `CancellationTokenSource` both build the tree explicitly. All four are
  cooperative, and none of them stops at one level.
- Related: language.parallelism.001, language.parallelism.002, language.parallelism.003

### language.parallelism.011 — No channel abstraction

- Evidence: no typed channel defines transfer, capacity, close, cancellation, and selection
  together. A producer and a consumer that need one build it from `Swag.Mutex` and
  `Swag.Condition` by hand, which is what the Swag Scope video queue does.
- Next: define the bounded, rendezvous, and one-shot forms in `bin/runtime`, with their endpoint,
  selection, and rejected-message types. Settle endpoint clone and drop behavior, draining after
  close, ownership of a moved message rejected before acceptance, and the single commit point of a
  selection before adding any Core convenience function.
- Done when: focused channel and selection tests cover backpressure, closure, cancellation,
  simultaneous readiness, and withdrawal without a lost message or a duplicate consumption.
- Related: language.parallelism.002, std.core.025

### language.parallelism.006 — One locked ready stack, so fine-grained work does not scale

- Evidence: every `submitWork` takes one process-wide mutex to push, and every `popWork`
  takes it to claim (`bin/runtime/scheduler.swg`). In `bench/scheduler`, fork/join over
  64-element leaves costs 115 ms on 22 workers against 13.7 ms on one, and spawn throughput
  falls from 2.1 to 0.5 children per microsecond over the same range. The pool does not know
  which class of hybrid core a worker runs on. The benchmark README states the
  alternating-worktree protocol these numbers need.
- Constraints: the worker cap stays at 64, because a parallel range reserves one runner per
  worker in its dispatch frame. Nesting stays unrestricted, because one process has one
  pool.
- Next: shard the ready list so that a submission and a claim do not serialize on one lock.
  Give each shard its own list and lock, choose the shard from the node's address so that a
  targeted claim still finds it in constant time, and let an idle worker scan the other
  shards. Keep the change only if it wins under the benchmark's alternating protocol on a
  quiet machine. Settle in the same change whether a worker spins before parking, and
  whether the pool should know its core class.
- Done when: fork/join over 64-element leaves stops getting slower as workers are added, and
  spawn throughput stops falling between one worker and every worker.
- Elsewhere: Rayon, Intel TBB, Java's `ForkJoinPool`, .NET's thread pool and the Go runtime
  all give each worker its own deque and steal from the others.
- Related: language.parallelism.001, language.parallelism.003, language.parallelism.005

### language.parallelism.012 — The runtime does not adapt background work to resource pressure

- Evidence: the process-wide scheduler chooses its worker count from logical processors once;
  it has no memory-pressure signal or admission policy for blocking background tasks.
- Next: add process-wide background-work admission that follows available CPU and memory while
  preserving foreground responsiveness; callers should submit useful work without choosing a
  machine-specific concurrency limit.
- Done when: deterministic scheduler tests show the shared budget grows beyond six on a capable
  host, contracts under constrained memory or CPU pressure, and queued work completes without
  per-module limits or starvation.
- Related: language.parallelism.001, language.parallelism.006

### language.parallelism.004 — Partitions cannot prove disjointness

- Evidence: `try/catch/expect parallel for` now carries failures across the join, but there is
  still no way to express an exclusive view of part of a container. Consumers index captured
  buffers, including H.264 reconstruction, and the compiler proves nothing about those indices.
- Next: add exclusive row, tile, chunk, stride, split and zip views with bounds and overlap
  contracts, and a checked partition constructor for the cases static proof cannot reach. That
  validation is semantic input checking, not a release-disabled guard. Read-only source halos
  beside disjoint destination tiles must be expressible, because stencils and image transforms
  need them. Preserve the fallible loop's join and partial-effect contract while adding views.
- Done when: a partitioned image operation needs no manual indexing into a captured buffer,
  overlapping mutable views are rejected, and success still means every index ran exactly once.
- Related: language.parallelism.001.

### language.parallelism.003 — A dedicated executor, but no UI or blocking executor

- Evidence: a `Swag.Barrier` with four participants, entered by four `Swag.TaskGroup` children,
  hangs. The pool decides how many children run at once; a participant then waits for one the
  pool has not started, and the waiting participants occupy the workers that would start it.
  Under compile-time execution, where the count is zero, the first child blocks the only thread.
  The same reasoning applies to `Swag.Semaphore.acquire` and `Swag.Condition.wait`: a waiting
  thread runs no ready work, so what it waits for must already be running. This is the
  evidence that the pool is the wrong owner for anything that waits for another task.
- Evidence: besides the pool, `Swag.Executor` gives work one thread of its own, and a task's
  notification can post a `Gui.TaskEvent` to a window. There is still no main/UI executor and no
  blocking executor, and nothing requires that a value is created, used and destroyed on one
  executor: the H.264 and H.265 lane decoders stay on their thread only because the stream submits
  their work there. The audio device and the GUI event loop still own a private thread; each runs
  one loop rather than a sequence of tasks.
- Next: a UI executor that the GUI event loop services, so a task can finish on the window thread
  instead of posting an event to it. Then the affinity restriction that makes a native handle's use
  and destruction stay on its executor, including during cancellation and shutdown, and a bounded
  blocking executor whose limit for mutually dependent foreign calls is documented and tested.
- Done when: a thread-affine resource is created, used and destroyed on its required executor
  under a shutdown that races its last callback, and the UI executor keeps servicing completion
  and destruction while it drains.
- Related: platform.portability.035.
