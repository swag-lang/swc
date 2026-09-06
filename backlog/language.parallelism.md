# Native Parallelism and Concurrency

This domain owns the proposed native concurrency model for Swag: structured tasks, checked memory
access, parallel computation, suspension, cancellation, and the runtime contract that connects
them. It covers both simultaneous CPU execution and concurrent operations that mostly wait.

The design and critical review remain together here until executable evidence settles the
contract. Syntax and API examples are proposals, not current language support. All new Swag types
of this concurrency system belong to `bin/runtime`. Library algorithms and consumer migration
stay in [std.core.md](std.core.md), general memory-safety prerequisites in
[compiler.safety.md](compiler.safety.md), and operating-system adapters in
[platform.portability.md](platform.portability.md). Shipped language behavior belongs in the
reference; the backlog keeps only unfinished decisions and implementation work.

## Reading guide

| Question | Start here |
| --- | --- |
| What is guaranteed, and by which layer? | [Scope](#scope-and-guarantees) and [responsibilities](#compiler-runtime-and-library-responsibilities). |
| How does application code use it? | [Syntax](#surface-syntax), [task lifetime](#task-ownership-and-lifetime), and [parallel loops](#parallel-iteration-and-reductions). |
| How do failures, waits, and memory stay safe? | [Memory access](#memory-access-and-effect-checking), [cancellation](#failure-and-cancellation), [state transitions](#task-and-operation-state-transitions), and [communication](#communication-and-synchronization). |
| What supports difficult workloads? | [Executors](#runtime-architecture-and-executors), [expert paths](#expert-workloads-and-trust-boundaries), and [workload cases](#workload-acceptance-matrix). |
| What must be decided or implemented next? | [Migration](#implementation-sequence-and-migration), [alternatives](#alternatives-and-tradeoffs), [open decisions](#open-decisions), [critical review](#critical-review), and [validation](#validation-and-acceptance). |
| Which deadlocks can the model actually exclude? | [Memory model and progress guarantees](#memory-model-and-progress-guarantees). |

## Vocabulary

| Term | Meaning in this proposal |
| --- | --- |
| Task | A logical computation owned by a group or supervisor, with one eventual terminal outcome. |
| Group | An owner that limits child lifetime, propagates policy, and joins accepted work before releasing its resources. |
| Operation | An awaitable action, such as a receive or I/O request; it need not allocate another task. |
| Executor | The authority that schedules accepted continuations under a placement and affinity contract. |
| Thread | A physical host execution resource; its identity is separate from task identity. |
| Region | Storage and aliases connected by ownership/access relationships that the compiler must track. |
| Isolation domain | An authority that controls access to mutable state; it is not necessarily a dedicated physical thread. |
| Cancellation | A request to stop, whose acknowledgement and cleanup occur before actual completion. |
| Data race | Conflicting unsynchronized accesses to the same memory, with at least one write. |
| Logical race | An incorrect result caused by operation ordering, even when all memory accesses are synchronized. |

## Entries

### language.parallelism.001 — Specify and prototype native structured concurrency

- Recorded: 2026-09-06 07:51
- Evidence: [Core.Jobs](../bin/std/modules/core/src/thread/job.swg) schedules borrowed callbacks
  and opaque caller-owned contexts; `parallelFor` and `parallelVisit` partition work through
  macros. [Core.Threading.Thread](../bin/std/modules/core/src/thread/thread.swg) exposes native
  thread lifetime and cooperative stop management. There is no common typed task, suspension,
  cancellation, or error-propagation contract for these consumers.
- Evidence: the [borrow reference](../bin/reference/modules/language/src/013_004_borrowing.swg)
  deliberately accepts cases it cannot prove invalid. The
  [closure reference](../bin/reference/modules/language/src/007_003_closure.swg) describes bounded
  byte-copy captures without owning lifecycle. Neither is sufficient to promise race-free task
  captures. [Swag.Context](../bin/runtime/api.swg) and
  [error storage](../bin/runtime/error.swg) also need task-aware ownership before work can migrate
  between threads.
- Status: proposed design and implementation sequence, recorded on 2026-09-06. The objective is
  native, simple, robust concurrency that replaces Core's current jobs and ordinary thread use.
  Runtime ownership of all new concurrency types is a selected constraint.
  The syntax, type names, and implementation choices below are candidates until the decision
  gates and executable prototype settle them; this entry is not evidence of shipped support.
- Next: resolve the semantic decision gates below with accepted/rejected source cases and a small
  executable prototype exercising partitioned CPU work, cancellable background preparation, and
  a resource tied to one native thread. Establish the checked-memory boundary before advertising
  a race-freedom guarantee or migrating production consumers.
- Complete when: suspension, ownership, scheduling, cleanup, cancellation, and failure have one
  recorded contract supported by the prototype; each decision gate has evidence and a selected
  outcome; std.core.025–.028 can integrate the runtime types against that contract. Then rewrite this entry around
  the remaining language work and keep the library work in its existing entries. The migration
  sequence below is a dependency map, not a requirement to finish every consumer to close this
  design/prototype outcome. Shipped semantics belong in the language reference, not permanently
  in the backlog.
- Elsewhere: [Swift structured concurrency](https://github.com/swiftlang/swift-evolution/blob/main/proposals/0304-structured-concurrency.md)
  scopes child-task lifetime; [Rust Send and Sync](https://doc.rust-lang.org/nomicon/send-and-sync.html)
  separates transfer from sharing; [Swift region-based isolation](https://github.com/swiftlang/swift-evolution/blob/main/proposals/0414-region-based-isolation.md)
  reasons about connected aliases. [Go's memory model](https://go.dev/ref/mem) makes synchronization
  and happens-before part of the language contract. These are references for separate decisions,
  not a proposal to import any one language's complete model.
- Related: std.core.004, std.core.025, std.core.026, std.core.027, std.core.028,
  compiler.safety.005, compiler.safety.006, compiler.safety.007, compiler.safety.014,
  runtime.allocator.004, platform.portability.035.

#### Scope and guarantees

The central contract is an owned task tree plus checked access to memory. Threads are runtime
execution resources. Jobs become an implementation detail of scheduling task continuations.
The language defines tasks, suspension, lifetime, isolation, and synchronization semantics; the
runtime implements them and owns their Swag types without depending on Core. Standard libraries
provide algorithms and domain adapters using those runtime types. No second task scheduler,
concurrency type hierarchy, or future ABI may be introduced by networking or GUI support.

The checked subset must rule out unsynchronized conflicting memory accesses, not merely diagnose
the ones an optional analysis happens to find. An unknown transfer, alias, indirect call, foreign
call, or destruction effect is rejected at a checked boundary until a valid contract is supplied.
This applies in release as well as devmode. Runtime scheduling and synchronization have real
costs; static checking is not a promise of zero-cost execution.

This guarantee assumes memory-valid execution inside the checked subset and correct trusted
primitives. Existing best-effort use-after-free detection or unchecked pointer fabrication cannot
be relabeled as a sound memory foundation merely by checking spawn captures. State and enforce
the admitted subset together with the concurrency effects; reject an opaque operation or isolate
it behind an audited contract rather than silently inheriting the old optimistic analysis.

Race freedom is distinct from logical correctness, determinism, termination, and deadlock
freedom. Atomics can implement a wrong protocol; an isolated object can process requests in the
wrong order; two channels can form a circular wait. Guarantee progression only for explicitly
restricted constructions and stated scheduler assumptions. General communication, low-level
interop, and arbitrary lock-free algorithms remain possible with narrower guarantees.

#### Compiler, runtime, and library responsibilities

| Owner | Contract it owns | Dependency constraint |
| --- | --- | --- |
| Language/compiler | Syntax, callable effects, capture semantics, region isolation, mandatory joins, memory ordering, and diagnostics. | Safety cannot depend on importing Core or enabling optional runtime guards. |
| Runtime | All new concurrency types and their generic implementations: tasks, groups, channels, guarded data, atomics, supervision, graphs, executors, and completion; scheduling, context, and lifetime machinery. | It must boot and shut down without a dependency on Core containers, GUI, or networking. |
| Standard library | Collection/stream algorithms, convenience functions, and domain-specific executor or I/O adapters using runtime protocols. | Public concurrency signatures use runtime types; the library does not own an alternative task, channel, synchronization, or cancellation family. |
| Host/platform adapter | Native threads, event notification, timers, I/O, affinity, and entry/exit from foreign code. | Native layouts and platform policy remain behind the portable ownership/completion contract. |
| Application | Task-tree ownership, admission limits, result publication, deadlines, and domain-specific failure policy. | Libraries inherit these policies where possible instead of silently starting an independent pool. |

**All new Swag types that define this concurrency system live in `bin/runtime`.** This is a module
ownership decision, not merely a requirement that their lowest-level primitives live there.

| Type family | Runtime-owned surface |
| --- | --- |
| Tasks and supervision | Tasks, groups, supervisors, futures/observers, outcomes, and task failure payloads. |
| Cancellation and time | Cancellation handles, deadlines, and the timing contracts used by the native concurrency API. |
| Execution and completion | Executor interfaces/handles, task-local context, awaitable operation protocols, completion records, and registration handles. |
| Communication | Channels, endpoints, selection cases/results, and rejected-message outcomes. |
| Shared state | Atomics, mutexes, read-write locks, guards, conditions, notifications, semaphores, barriers, and isolated-state wrappers. |
| Parallel algorithms | Reusable partition capabilities, reduction contracts, task graphs, nodes, and dependency/result handles. |
| Expert extensions | Generic reclamation domains and concurrency option, policy, and state types. |

Their public signatures, storage, lifecycle operations, and generic implementations cannot depend
on Core types. Reuse runtime allocation and value contracts; adapt existing Core collections or
time values at the library boundary where necessary. Type names and namespace spelling remain
open design choices, but the owning module is fixed.

GUI, audio, networking, and other modules keep their domain resources and platform adapters.
Those implementations conform to runtime protocols and expose runtime concurrency handles;
module-private backend state does not create a competing public concurrency model. A generic
concurrency type introduced by a later extension follows the same runtime ownership rule.

Runtime availability does not require eagerly creating every pool, timer, queue, or native handle.
Activate execution resources when needed and measure unused-feature footprint. Keep the runtime
independent of Core while avoiding an unnecessary startup cost for sequential programs.

One process needs a coherent scheduler/context ABI across static and shared module boundaries.
Joining work is also part of unloading a module whose code, task frames, callbacks, or destruction
functions are still referenced. An embedding host must be able to own runtime attachment, supply
an executor, stop admission, and drain accepted work without another hidden process-wide runtime.

A custom executor may choose queue order and placement within its contract. It cannot duplicate
continuations, resume one concurrently, lose accepted work, or invalidate outstanding completion
records. Executing untrusted executor code is not a way to extend the compiler's proof boundary.

#### Surface syntax

Use five candidate keywords and keep the remaining vocabulary in types and APIs.

| Form | Meaning |
| --- | --- |
| `async` | A function may suspend; the effect is part of its callable type. |
| `await` | Run/observe an operation and suspend the current task when necessary. |
| `taskgroup` | Own child tasks and delimit their mandatory join. |
| `spawn` | Capture an invocation and create an immediately schedulable child task. |
| `parallel` | Execute independent parts of a computation under checked partition rules. |

Illustrative new syntax, deliberately not a compilable current-language example:

```swag
func loadView(id: u64)->View async fail
{
    try await taskgroup
    {
        let document = try spawn loadDocument(id)
        let style = try spawn loadStyle(id)

        return makeView(try await document, try await style)
    }
}
```

`await f()` calls `f` in the current task; it does not create parallel work. `spawn f()` creates
a child whether `f` is synchronous CPU work or an async function. Arguments are evaluated and
captured in the parent before the invocation is published. The first `try` handles creation or
admission failure; `try await` handles task completion, failure, or cancellation. A task executes
at most one continuation at a time, even when it migrates between physical threads.

Ordinary spawn requires a current task group and chooses the general concurrent executor.
Placement on another executor is explicit. Calling an async function directly preserves the
caller's isolation contract; a continuation returns to its required executor after an await.
An `async` annotation does not make GUI state transferable or a blocking foreign call suspendable.
Reserve and validate the exact grammar, keyword collisions, effect ordering, and callable-type
spelling at the syntax gate rather than treating this example as a finished parser specification.

#### Task ownership and lifetime

Task ownership controls every exit, not just the happy path.

- The group owns execution; a `Task'T` handle owns one opportunity to extract its result. Dropping
  that handle neither detaches the child nor silently discards its failure.
- Normal fallthrough joins all children. Return, break/continue leaving the group, failure, and
  cancellation close admission, request cancellation of unfinished children, and join them.
  A return expression is evaluated under the current borrow rules before exit processing; an
  implicit join does not retroactively make a conflicting read in that expression legal.
- A group cannot finish until its descendants and outstanding native operations have actually
  finished using its resources. Captured resources stay alive through that join. Define cleanup
  in the compiler's control-flow lowering, not by a library destructor that might block.
- `await` consumes the unique result handle; explicit shared observation requires an immutable
  shared result or a declared copy operation. A borrowed result keeps its origin relation after
  task completion. Neither a discarded handle nor a readiness poll releases an exclusive loan.
  If the waiter is cancelled before the child completes, the group still owns the child, its
  eventual result, and its loans. Specify whether that await has consumed the result handle;
  never infer that a cancelled wait has joined its target.
- Lifetimes follow storage regions, including locals declared in nested scopes and loop bodies.
  A child cannot keep an inner local until an outer group ends after that local has died. Require
  a nearer group or an owned capture when the lexical lifetime is too short.
- Group-scope cleanup that protects borrowed storage runs after joining its users. Operations
  needed for children to terminate, such as closing the last producer endpoint, must occur in
  the body before normal join. Detect simple violations and include this rule in diagnostics.
- A long-lived async manager owns application, window, connection, or service groups. Their
  shutdown is async. An ordinary `opDrop` never becomes an implicit blocking or suspending join.
  Background work is transferred to a live supervisor with owned captures and an error policy;
  there is no ordinary orphaning `detach` operation.
- Settle exactly which handles can leave a group, which descendants may observe them, and how
  result consumption is checked across branches. The basic acyclic-join subset only permits
  waiting on descendants. Shared observers, graph edges, or general promises are an explicit
  extension that does not inherit that progression guarantee.

#### Memory access and effect checking

Permit four forms of concurrent access and prove every alias involved.

| Access | Required proof |
| --- | --- |
| Ownership transfer | The receiving task owns the region and no incompatible source alias remains usable. |
| Exclusive loan | Only one execution domain can access the region until the loan ends. |
| Shared read | The owner survives and no incompatible mutation is possible while readers are live. |
| Synchronized sharing | Every access passes through an abstraction whose contract protects the underlying state. |

Use existing `#move` for an explicit transfer. Preserve its documented source reset and lifecycle
semantics; do not silently replace them with another language's moved-from rules. A move alone
does not invalidate every alias by magic. Track views inside moved aggregates, containers,
interfaces, closures, returned values, and pointer-derived accesses.

An invocation can borrow a large input without cloning it. Swag's by-value struct ABI already
borrows storage, so asynchronous argument capture must explicitly extend that storage's lifetime
and access restrictions rather than treating a by-value parameter as an owned snapshot. Mutable
borrowed arguments exclude parent and sibling access until actual completion. Independent fields
or partitions may be borrowed separately when disjointness is proven.

Infer separate `Send` and `Sync` properties: transferable ownership and safe shared read access.
They include allocation, copy, move, and destruction effects, not just the representation's fields.
`NoCopy` does not imply `Send`; `const` does not imply deep immutability; an atomic reference count
does not synchronize the pointee. Raw pointers and opaque owner implementations need contracts,
not automatic acceptance. Native handles and their destruction may require a particular executor.

Task captures own their environment and run the appropriate lifecycle operations exactly once.
The representation is not restricted to the current closure's fixed-size POD byte capture.
Allow group/frame allocation and inline small captures as optimizations, without making a fixed
capture capacity part of task semantics. Rejected transfers must explain the concrete alias,
allocator, destructor, or executor constraint and identify a valid ownership/partition alternative.

The check is transitive. Export inferred summaries for reads, writes, retained borrows, mutable
globals, suspension, blocking, lock acquisition, executor requirements, and relevant lifecycle
effects. Carry effect bounds through function pointers, generic callbacks, interfaces, module
APIs, and cache identity. Unknown summaries are not empty summaries. Mutable globals belong to
an isolation domain or a checked synchronization abstraction. Legacy code is checked transitively,
isolated, or admitted through an audited unchecked boundary; a safe-looking wrapper alone does
not upgrade its guarantee. Define that boundary together with compiler.safety.006/.007/.014.

#### Failure and cancellation

Failure and cancellation follow the ownership tree.

Tasks have success, failure, or cancellation outcomes. The default group policy stops admission
and requests sibling cancellation when a child terminates in failure. It joins every child and
reports a group failure containing the trigger and other observed failures. Catching a failed
child in the parent does not restart a group already stopping; expected errors are handled inside
the child or represented as values. A supervised policy collects outcomes without sibling
cancellation. Define failure precedence for a concurrent parent failure, child failures, external
cancellation, and cleanup failure; preserve all observed causes without reporting one twice.

Cancellation is an idempotent cooperative request, inherited by descendants and observed at
cancellable awaits and explicit checkpoints. A long synchronous computation must cooperate;
neither a keyword nor a priority hint bounds its response time. Deadlines are absolute monotonic
instants and compose by retaining the earliest deadline. Resource cleanup runs with cancellation
masked where necessary to preserve invariants. Fallible or async finalization is explicit; its
error handling and interaction with an existing failure must be defined, not hidden in `opDrop`.

Decide whether cancellability is a separate control effect or an outcome carried by `fail`,
including `async` functions whose body cannot otherwise fail. Define what `try`, a catch-all,
`defer #fail`, `defer #nofail`, and cleanup masking observe. A caught cancellation must not clear
the inherited stop request, and no implicit cancellation path may bypass required destruction.
The `try await` examples do not settle that interaction with the existing error language.

Cancellation is not completion. The task's frame, borrowed buffers, native request records, and
callback environment survive until the backend acknowledges completion and no late callback can
touch them. A timeout requests stopping; it is not a promise to return by the deadline when a
foreign call or child cannot cooperate. Never trade lifetime safety for a timely timeout return.
Fatal panic keeps a separate process-level contract and is not automatically a recoverable task
failure.

Errors crossing tasks own their payload and satisfy transfer/isolation requirements. They cannot
be borrowed views into a child's error allocator. Specify how this interacts with today's erased
`fail` payloads and dynamically called functions before claiming end-to-end safety.

#### Task and operation state transitions

The prototype must represent cancellation requests, execution state, and resource ownership
separately. A single done/cancelled flag cannot describe all three. The following dimensions are
candidate implementation invariants to prove at D3, D4, D6, and D9.

| Dimension | State | Ownership invariant |
| --- | --- | --- |
| Admission | Reserved | The reservation owns capacity and unpublished capture storage; no executor may run a child yet. |
| Admission | Published | A live group owns the child and an executor owns the obligation to service accepted work. |
| Execution | Runnable / running / waiting | At most one continuation runs; a wait record retains every object its eventual notification may touch. |
| Closing | Open / draining | Draining closes child admission and joins existing dependencies; it can itself require running or suspended cleanup. |
| Outcome | Success / failure / cancelled | One terminal outcome is published only after required descendants, native users, and cleanup have finished. |
| Observation | Available / consumed / abandoned | Taking or abandoning a result changes its owner, not whether unfinished execution still exists. |

Cancellation is a monotonic request alongside these states. A completed result may already have
won the relevant operation's race when cancellation arrives. The final arbitration policy belongs
in D4/D6; do not overwrite an accepted result and lose its payload just to make cancellation look
immediate. Draining and waiting can coexist, so they must not be modeled as mutually exclusive
states of one simplistic enum.

The completion protocol has a second ownership problem: a waiter can disappear before its
producer, while the producer can finish before waiter registration completes.

| Transition | Obligation |
| --- | --- |
| Prepare an operation | Establish ownership of arguments, buffers, and any eventual result before exposing a callback. |
| Register interest | Handle completion before, during, or immediately after registration without losing a wakeup. |
| Observe readiness | Readiness alone does not consume a channel message or release a buffer still used by a native backend. |
| Claim a result or selection | Exactly one permitted observer receives ownership; losing alternatives are withdrawn or drained according to their contracts. |
| Request cancellation | Retain records until the producer/backend confirms it cannot touch them again. |
| Retire registration | Make late or duplicate callbacks harmless through lifetime and generation rules, then release the registration's resources. |

A common lifecycle does not make every operation transactional. Channel selection has a transfer
commit point; a network write can have partial external effects before it completes. Record those
effects and their ownership under the operation's own contract. A cancelled/losing branch does not
undo bytes already sent, files already changed, or work already accepted by an external system.

Use generation or equivalent identity rules when storage for wait records is reused. A delayed
notification from a previous operation must not complete a new operation that happens to occupy
the same address. Instrument the fake backend to deliver that case as well as duplicate and
immediate notifications.

#### Parallel iteration and reductions

Parallel loops expose independent regions rather than opaque callback contexts.

```swag
// Proposed syntax and API: each row is an exclusive disjoint partition.
parallel for &row in image.rowsMut()
{
    convertRow(row)
}
```

The compiler proves separation between iterations and checks all storage reachable from each
element. Distinct elements containing aliases to the same mutable object are not independent.
Provide exclusive row, tile, chunk, stride, split, and zip views with bounds and overlap contracts.
Where static proof is unavailable, a checked partition constructor may validate disjointness and
return an exclusive capability. Such validation is semantic input checking, not a release-disabled
diagnostic guard. Read-only source halos and disjoint destination tiles must be expressible for
stencils and image transforms.

- On success, execute each iteration once; execution order is unspecified and retries are never
  implicit. Failure/cancellation can leave partial mutations. Atomic publication needs separate
  result storage followed by an explicit successful commit.
- Keep the iteration structure stable. `continue` is local; a global `break` or return from the
  enclosing function is rejected. Supply separate `findFirst` and `findAny` operations when the
  selection order matters.
- Ordinary bodies do not suspend or wait on other tasks. Check these effects through callees.
  An async bounded map handles operations that await I/O. Synchronization that could create a
  wait cycle is outside the simple independent-kernel progression contract.
- A synchronous `parallel for` joins synchronously and remains callable from ordinary functions.
  An `await parallel for` candidate suspends its caller during the join. Synchronous helping must
  not run arbitrary unrelated user tasks or conceal reentrancy under a guard or isolation lease.
  The candidate default preserves an infallible synchronous body as an infallible loop: scheduler
  admission/storage pressure uses serial execution, and cancellation is deferred until completion
  if the enclosing contract has no way to report it. It must not return success after skipping
  iterations. Fallible/cancellable loops need an explicit effect and partial-progress contract.
  Prototype serial fallback without rerunning any chunk that was already published or executed.
- Partition into a bounded number of useful chunks, with a serial path for small work and shared
  worker budgets for nested loops. Cancellation is checked at defined chunk boundaries; one
  long body may need explicit checkpoints.
- Reductions use local accumulators and an explicit identity/combiner contract. A captured
  `sum += value` is not a reduction. Require the selected associativity/order assumptions and
  forbid hidden side effects in combiners. Reproducible mode uses a logical combination tree
  independent of worker count; this alone does not guarantee identical floating-point bits across
  architectures, vectorization, or aggressive FP settings. Distinguish it from a sequential fold.

#### Communication and synchronization

Communication and synchronization use one wait/completion protocol.

| Family | Required public contract |
| --- | --- |
| Bounded channel | Typed ownership transfer, finite capacity, backpressure, endpoint ownership, close and drain behavior. |
| Rendezvous channel | Capacity zero; transfer commits when sender and receiver meet. |
| One-shot result | One producer, one result, observable producer abandonment. |
| Selection | Register alternatives, reserve/commit one operation, safely withdraw losers. |
| Isolated object | State belongs to one executor; operations expose no unrestricted mutable alias. |
| `Mutex'T` / read-write lock | Data access requires the appropriate live guard; acquisition and wait effects are explicit. |
| `Atomic'T` | All accesses use the atomic API; no ordinary pointer into its storage is exposed. |
| Semaphore | Owned permits returned on every exit; distinguish capacity from task lifetime quotas. |
| Barrier | Explicit phases and participant lifetime; a cancelled/dropped participant breaks or leaves the barrier under a defined protocol. |
| Condition / notification | Durable state and predicate-loop waiting; release/reacquire or generation rules prevent lost wakeups. |

An accepted send means queued/transferred, not processed. Closing a channel drains accepted
messages before end-of-stream. Specify sender/receiver clone and final-drop behavior. A moved
message rejected before acceptance is returned through a typed unsent outcome, including on
cancellation, instead of becoming an inaccessible error payload. Receives must not consume a
message and then report cancellation without a defined owner for that message.

Selection is not a race between consuming receive tasks: only the selected operation may consume.
Define its commit point, readiness recheck, simultaneous-ready policy, fairness, registration
lifetime, and cancellation arbitration. Separate first completion, first success, and all-results
combinators. Cancel and join losing tasks before releasing anything they borrow; already committed
external effects cannot be rolled back merely because another branch won.

Isolated state operations are non-suspending by default. Perform long work outside the state
operation, then publish with a version check or another explicit validity test. Reentrant async
operations are an opt-in contract: invariants must be re-established after every suspension.
A serial executor alone does not make arbitrary mutable aliases safe or preserve an invariant
across an await.

Ordinary guards cannot cross suspension, channel waits, parallel joins, or other incompatible
waits. Async acquisition may suspend before it returns a guard; the guarded state operation
remains non-suspending. Ordered-lock contracts are transitive through calls. Multiple acquisition
orders instances consistently and handles duplicate objects; read-to-write upgrade has no implicit
atomicity. A condition wait is a specified release/wait/reacquire transition with predicate
rechecking and cancellation behavior. Specialized logical leases that intentionally span awaits
remain possible, but do not carry the ordinary no-wait-under-guard guarantee.

#### Memory model and progress guarantees

State the memory model and the limit of every progression claim.

Define conflicting accesses, atomic modification order, sequenced-before, synchronizes-with, and
happens-before independently of x86 implementation behavior. Publication of captures precedes
child execution; completion precedes a successful join; channel acceptance/receipt and lock
release/acquisition supply their specified synchronization edges. Default atomics are sequentially
consistent. Acquire/release/relaxed orders remain explicit expert operations with their legal
combinations and precise guarantees. The strong-order checked subset admits a sequentially
consistent interpretation; weak-order operations do not inherit that stronger claim.

Concurrent conflicting non-atomic access is invalid. Checked code cannot express it under the
trusted runtime and abstraction contracts; violating those contracts in unchecked code does not
come with a promise of runtime repair or detection. Atomics do not create multi-location
transactions. Atomic pointer algorithms also need a valid reclamation protocol and lifetime proof.

| Construction | Progression boundary |
| --- | --- |
| Finite independent kernels and descendant-only fork/join | Must complete with one worker if their sequential computations terminate and the executor services ready work. |
| Ranked locks | Prevent acquisition cycles only while all acquisitions obey the declared order. |
| Explicit task graph | Reject cycles when constructing or extending the dependency graph; other waits in node bodies need their own contract. |
| General channels, promises, actors, leases | Safe memory access does not prove the communication protocol terminates. |
| Foreign waits and external systems | Require explicit backend contracts; no universal deadline or deadlock guarantee. |

A diagnostic scheduler records known wait edges, task ancestry, source locations, and cancellation
state. It can explain supported cycles or stalled operations; absence of a recorded cycle is not
a proof about an opaque external dependency. Controlled scheduling and replay cover registered
events, not arbitrary real-time or external nondeterminism.

#### Runtime architecture and executors

Use stackless async lowering and interchangeable execution resources.

Prefer compiler-generated state machines for `async`; retain only values needed across suspension.
Stabilize the coroutine frame and any self-references before publication. Specify frame destruction,
resume/completion arbitration, and a versioned runtime ABI for generic and erased operations.
Optimizing away a frame or allocating it in a parent arena must preserve lifetime and cancellation
semantics. Ordinary synchronous stacks and foreign call stacks do not become suspendable.

The runtime owns a common task representation, local queues/work stealing, wakeups, an I/O
reactor, monotonic timers, admission accounting, and shutdown. Scheduler implementation belongs
below Core and is shared across linked modules. OS adapters remain backend leaves; additional
ports belong in platform.portability rather than duplicate per-library task designs.

| Executor | Intended use |
| --- | --- |
| General concurrent | Ordinary tasks and CPU computations. |
| Main/UI | State and handles tied to the application's event-loop thread. |
| Blocking | Foreign/system calls that occupy a physical thread. |
| Dedicated thread | Strong affinity or a specialized native loop. |
| Custom | Host engine integration, NUMA placement, or an explicit scheduling policy. |

An executor contract includes affinity, accepted operation kinds, completion ownership, and what
happens when submission fails or shutdown starts. Accepted continuations cannot simply disappear.
Priority and fairness are best-effort under cooperative execution, with no implicit hard latency
bound. A bounded blocking executor does not guarantee progress for arbitrary mutually dependent
foreign calls; document and test that boundary.

Separate the CPU-worker budget, runnable work, live tasks, buffered results, and outstanding I/O.
`spawn` does not silently wait for a saturated lifetime quota. It either publishes one fully owned
child or reports admission failure. Bounded map/pipeline operations produce work progressively
instead of creating one waiting task per input. Admission itself must not introduce a hidden
parent-waits-for-child-waits-for-parent quota cycle.

Submission has a separate ownership decision: `try spawn consume(#move value)` can fail before
admission, while captures are evaluated, or when an executor shuts down. Prefer reserving admission
and frame storage before evaluating captures, then materializing captures left to right and
publishing once. Such a reservation must either remain valid through publication or specify who
owns/destroys the captures when publication is rejected. A later capture expression can itself
fail after an earlier source was moved; preserve ordinary source-reset semantics and destroy
materialized captures exactly once. Do not promise rollback of argument side effects or restoration
of moved sources. Fix that evaluation order explicitly in the language contract and test each
failure boundary, rather than assuming `try` makes submission transactional.

Split the current thread context into task-owned logical state and physical-thread caches.
Install/restore the logical context on every task entry/resume and synchronous helping transition.
Give children independent scratch/error storage; inherit only context values whose ownership
allows it. An allocation's allocator must remain valid and support the eventual freeing thread,
or impose explicit affinity/ownership restrictions. Exported results cannot point into scratch
that is reset when the child ends.

Keep task-local values distinct from true native TLS. A TLS borrow cannot survive a migrating
suspension without an appropriate restriction. Executor-bound resources must be destroyed on
their required executor even during cancellation and shutdown. Complete these destructions before
retiring that executor. Async entry points, synchronous host entry/exit, callbacks, dynamic-module
unload, and compile-time execution need explicit runtime attachment and drain rules.

#### Expert workloads and trust boundaries

Preserve an expert path without weakening the ordinary one.

| Workload | Composition |
| --- | --- |
| Bounded media pipeline | Owned buffers, typed channels, cancellation, per-stage capacity. |
| Render/build dependency graph | Typed nodes and edges, cycle checking, immutable fan-out results. |
| Matrices/images/stencils | Exclusive destination tiles and shared source regions/halos. |
| Lock-free structures | Explicit atomics plus audited epoch/hazard-pointer or other reclamation domains. |
| Latency-sensitive audio | Dedicated execution, preallocated memory, no-allocation/no-wait contracts. |
| GUI/native handles | Executor isolation that includes creation, use, callback delivery, and destruction. |
| NUMA/host engines | Custom placement and allocator contracts within the same task ABI. |
| GPU work | Awaitable command/fence completion and explicit host/device buffer ownership. |

No-allocation/no-wait checking is not a hard real-time guarantee on a general-purpose OS. GPU
and remote execution retain their own memory/consistency boundaries; an awaitable completion is
not automatic CPU-to-GPU compilation or shared-memory semantics across machines. Unsafe pointer,
foreign, and custom synchronization implementations require a small auditable trust boundary
and safe public wrappers. Exact unchecked spelling is part of the safety decision, not a sixth
concurrency keyword assumed here.

#### Workload acceptance matrix

The first three rows are the joint prototype boundary. The remaining rows are design coverage
checks and later implementation work; they must not turn the first prototype into a complete
production scheduler campaign.

| Workload | Desired expression | Adversarial case to settle | Evidence required |
| --- | --- | --- | --- |
| Image conversion | Exclusive row/tile views in a parallel loop. | Aliased buffers, an infallible caller, nested loops, and admission failure after partial dispatch. | No unchecked caller workaround; each element processed once on success; one-worker progress and measured serial threshold. |
| Background GUI preparation | Owned input, cancellable child task, isolated publication. | Window closes or the document changes before completion. | No access to dead UI state; stale results rejected; required cleanup still runs on the UI executor. |
| Native thread-bound resource | Dedicated executor with checked use and destruction affinity. | Cancellation or shutdown races the final callback and drop. | Use and destruction stay on the required live thread; shutdown does not block that thread's own completion work. |
| Bounded streaming pipeline | Transferred buffers and finite-capacity channels. | Consumer stops while producer is blocked; one stage fails after a partial transfer. | Every buffer and rejected message has an owner; failure closes/drains the pipeline under its stated policy. |
| Recursive CPU work | Nested structured tasks or parallel partitions. | One worker and an exhausted task-lifetime quota. | No hidden quota wait cycle, bounded bookkeeping, and equivalent completed results. |
| Dependency graph | Typed nodes with explicit result edges. | A dynamic edge introduces a cycle, or one node awaits an unrelated external event. | Cycle rejection for graph edges; no false claim that arbitrary node bodies are deadlock-free. |
| Foreign blocking operation | A task scheduled on the blocking or dedicated executor. | The operation ignores cancellation or synchronously calls back into the host. | Borrowed resources survive; callback/runtime attachment is valid; no unsupported timeout bound is promised. |
| Lock-free shared structure | Typed atomics with a reclamation domain. | ABA, a stalled reader, and reclamation during shutdown. | Storage lifetime is justified separately from atomic ordering; the unchecked implementation boundary is explicit. |

For each prototype case, record the source size, annotations, explicit clones, unsafe escapes,
allocations, and runtime costs needed by the preferred path. A short keyword example is not
sufficient evidence of simplicity if every useful helper needs an unchecked contract.

#### Implementation sequence and migration

Migration follows dependency order and keeps one owner for each outcome.

| Stage | Deliverable and acceptance gate | Owning work |
| --- | --- | --- |
| 0 | Formulate candidate answers to the decision table and define accepted/rejected examples, trust boundary, and runtime ABI outline. | This language decision; compiler.safety.005/.006/.007/.014 for the underlying safety gaps. |
| 1 | Minimal task/group prototype, capture lifecycle, cancellation, one-worker join, task context, and one affinity-bound resource; lower to both native and JIT execution. | This prototype outcome; derive focused implementation entries from its evidence. |
| 2 | Partitioned CPU loops with serial/nested behavior and reductions; migrate a real pixel transform after its proofs and performance hold. | Language/compiler implementation and owning pixel module. |
| 3 | Runtime channels, selection, I/O completion types, isolated publication, and long-lived async shutdown; migrate GUI/Swag Scope background work. | Native implementation under this domain; std.core.025/.026/.027/.028 and owning modules integrate the runtime types; backend ports stay in platform.portability. |
| 4 | Dedicated-thread/audio and foreign-call migration; graph and expert synchronization contracts; remove legacy APIs after the consumer inventory is empty. | Owning library/application entries and remaining language/runtime implementation. |

The prototype uses three forcing cases together: one partitioned image operation, one cancelled
background result published to an isolated UI owner, and one native-thread-bound resource.
A fake I/O backend is sufficient to explore completion races early; a real backend must confirm
late callbacks and buffer lifetime before production migration. Review the API against those
cases before investing in every scheduler optimization or expert combinator.

| Existing surface | Target contract |
| --- | --- |
| `Jobs.initialize()` | Runtime-owned initialization and configuration at the host boundary. |
| Callback `Job` plus `*void` | Typed child task with checked captures. |
| `Jobs.schedule` / `Jobs.wait` | Spawn plus scoped async or synchronous join. |
| `Jobs.waitAll()` | Close the owning group, not an ambient process-wide work set. |
| `parallelFor` / `parallelVisit` | Native parallel iteration over proven partitions. |
| Stop/ready flags | Cancellation and typed completion, with explicit progress observation when needed. |
| Mutex beside mutable data | Guarded data or an isolated owner; audit the whole access family. |
| Atomics through ordinary pointers | Typed atomic storage with no mixed ordinary access. |
| Ordinary application threads | Tasks, retaining a dedicated executor for genuine thread affinity. |

Inventory callers, tests, generated API consumers, initialization/shutdown, and shared-library
boundaries before mechanical migration. Temporary adapters may schedule old callbacks on the new
runtime, but remain explicitly unchecked and preserve their documented borrowed lifetime. They
cannot infer ownership from `*void` or make old global-wait semantics local without changing the
contract. Do not retain two permanent public vocabularies or hide swallowed cancellation/errors
behind compatibility forwarding.

#### Alternatives and tradeoffs

These are design choices to revisit when prototype evidence contradicts the proposed default.

| Alternative | Proposed decision | Tradeoff to measure or constrain |
| --- | --- | --- |
| Unstructured spawning by default | Require an owning group or supervisor. | Service lifetimes need a usable async owner; structured cleanup must remain practical in callback-driven applications. |
| Actors for all mutable state | Keep isolation alongside exclusive partitions and guarded sharing. | Actors simplify ownership of service state, but independent data processing must not require one message per element. |
| Shared mutable objects guarded only by programmer convention | Require checked access capabilities and transitive effects. | Unknown safe legacy idioms may be rejected; D1/D10 must establish a workable migration and annotation surface. |
| Stackful fibers as the universal mechanism | Prefer stackless async lowering, with dedicated/native adapters for synchronous stacks. | Measure frame cost and function-effect propagation; do not claim ordinary foreign frames can suspend transparently. |
| A separate CPU jobs API and I/O futures API | Use one task, ownership, and completion model with specialized execution policies. | CPU serial fallback and non-fallible calls must fit the shared model without inheriting unnecessary I/O costs. |
| Implicitly parallelize an ordinary loop | Require explicit parallel intent and prove permitted accesses. | Preserve side-effect ordering in ordinary loops; make partition construction concise enough that users choose the verified form. |
| Universal static deadlock freedom | State progression guarantees for restricted constructions. | General protocols remain expressive; diagnostics must distinguish proof, detected cycle, and unknown external wait. |

#### Open decisions

Settle these gates before the model is called complete.

| Gate | Required decision or counterexample |
| --- | --- |
| D1: soundness boundary | Explain how opaque pointers, globals, foreign calls, lifecycle hooks, erased values, and modules are admitted or rejected. Demonstrate a hidden-alias rejection without depending on optional sanity guards. |
| D2: suspension and ABI | Fix the syntax/effect grammar, stackless frame ownership, stable addresses, callable ABI, and async host/JIT boundaries. |
| D3: task and region lifetime | Specify handle escape/consumption, borrowed results, nested-scope captures, normal/early exits, and join-versus-defer ordering. |
| D4: cancellation and failure | Define primary/secondary errors, owned failure payloads, cancellation arbitration, cleanup masking, and timeout semantics; settle cancellability versus `fail`, catch-all handlers, and existing defer modes. |
| D5: progress and capacity | Prove one-worker finite fork/join, separate lifetime quotas from worker limits, and constrain synchronous helping, guards, and nested blocking. |
| D6: completion protocol | Model channel/selection/native I/O registration, readiness, commit, cancellation, and late completion with one terminal owner. |
| D7: context and affinity | Prove allocator/scratch/error ownership across task migration and destruction on an executor that is itself shutting down. |
| D8: parallel semantics | Specify partition proof construction, serial fallback for infallible loops, cancellation/effect propagation, partial progress, reductions/FP policy, and cost thresholds measured on a real consumer. |
| D9: submission ownership | Fix admission-versus-capture evaluation order, partial capture failure after `#move`, executor shutdown racing publication, and the owner of every rejected capture. |
| D10: usable proof surface | Show ordinary image, GUI, and native-affinity cases without routine unchecked escapes, accidental whole-object cloning, or annotation-heavy helper APIs. Record necessary annotations and rejected safe idioms before freezing the surface. |

#### Critical review

These findings still require prototype evidence.

- D1 is the critical dependency. Replacing optimistic analysis at the concurrent boundary also
  requires a defensible checked memory subset and transitive effects. A prototype that only
  rejects two direct writes to a captured local has not established the proposed guarantee.
- D3/D4 must distinguish a child's lifetime from its waiter's lifetime. Reproduce a cancelled
  await caught inside the group, then an attempted access to the child's exclusive borrow; the
  access remains forbidden until a real join. Also check an inner-loop local captured by an
  outer group and a return expression that reads data before the implicit join.
- D4 must specify how the waiting parent observes an immediate sibling failure without depending
  on the order it awaits handles. Sibling cancellation must not mask the actual triggering error,
  manufacture unrelated duplicate failures, or leave an uncooperative parent falsely considered
  terminated. The aggregate's observed failure set need not be scheduling-independent.
- D8/D9 expose an API compatibility tension: explicit spawn is fallible, but existing pixel
  methods and the proposed simple parallel loop often are not. Serial fallback and deferred
  cancellation are candidate semantics to test, not permission to discard a creation error or
  claim a partially executed loop succeeded. Inject failure after some work was dispatched.
- D5/D6 need state-machine evidence, not only stress runs. Use one worker, a full lifetime quota,
  a selected receive racing cancellation, and shutdown racing submission to distinguish library
  protocol deadlocks from scheduler faults. Safe channels remain capable of circular waits.
- D7 must keep the UI/dedicated executor servicing completion and required destruction during
  shutdown. Blocking that executor while waiting for an affine child recreates the very deadlock
  the task API is intended to avoid. Include an actual thread-affine resource in this probe.
- D10 keeps the implementation sequence bounded. The five keywords conceal substantial ownership,
  effect, lifecycle, and ABI work. Validate the three forcing cases and their annotation/copy cost
  first; graph scheduling, NUMA policies, GPU adapters, and hard latency claims cannot substitute
  for those proofs. No hard real-time guarantee is part of this proposal.

#### Validation and acceptance

Validation is staged at the boundary that can observe each promise.

- Semantic tests accept safe transfers/partitions and reject hidden aliases, cross-module global
  writes, escaped borrows, incompatible callable effects, and wrong-executor destruction. The
  guarantee must be mandatory rather than a warning or a devmode-only guard.
- A runtime-only consumer must declare and use native tasks, channels, and synchronization types
  without importing Core. Inspect public signatures and dependencies for accidental Core value
  types, and verify that a sequential consumer does not eagerly start unused execution resources.
- Native and JIT lifecycle tests cover every exit after capture, immediate completion, suspended
  frames, result/error transfer, source reset, nested scopes, and destruction exactly once.
  Include failed admission before capture, a failing later capture after an earlier move, a
  cancelled waiter whose child still owns a loan, and serial fallback after partial dispatch.
- A controlled scheduler and fake backend enumerate cancellation before publication, during
  registration, at commit, after completion, and during cleanup. Test simultaneous completions,
  selected versus withdrawn channel operations, producer abandonment, and late native callbacks.
- Runtime tests distinguish one worker from several, nested fork/join, quota exhaustion, pool
  shutdown, and a stalled foreign call. They must not infer soundness from stress testing alone.
- Consumer evidence comes from the precise pixel operation, GUI/background lifecycle, and audio
  or other native-affinity operation used by the prototype. Measure creation/join cost, memory
  per live task, queue contention, cancellation latency under stated cooperation assumptions,
  serial thresholds, and throughput against the existing implementations. Do not invent numeric
  acceptance thresholds before collecting those baselines.
- Follow validate-swag-changes for the actual implementation diff: focused sema/native/jit/workspace
  boundaries and owning module tests; both compiler executables when architecture changes require
  them, and program configurations that exercise distinct lowering/optimization paths. Apply load
  admission and worker limits to every build/test invocation. No build is evidence for this prose.
- Every implemented syntax change updates the language reference, editor grammar, formatter and
  relevant diagnostics together. Compiler-source changes increment `SWC_BUILD_NUM`; serialized
  effect summaries and runtime ABI changes must invalidate incompatible cached artifacts.
