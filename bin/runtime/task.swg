#global namespace Swag

// What a running body reads through [[Swag.isCancelled]].
//
// A scope can chain to the scope current where its work was started, so a request made on an
// outer scope reaches every scope nested in it. The chain is only followed while the inner work
// runs, which must end before the outer scope's storage does.
#[Swag.NoDoc]
struct CancelScope
{
    stop:   AtomicFlag        // Raised by a cancellation request; never lowered while work runs.
    parent: *CancelScope?     // Outer scope whose requests this one also observes.
}

impl CancelScope
{
    // Returns whether this scope or any scope it chains to was asked to stop.
    mtd const isRaised()->bool
    {
        var scope: const *CancelScope? = me
        while scope
        {
            if scope.stop.isRaised() do
                return true
            scope = scope.parent
        }

        return false
    }
}

// Returns whether the work running on this thread was asked to stop.
//
// A task, a task-group child and every partition of a `parallel for` answer for the request made
// on them and for every request made on the work they were started from. Outside such work the
// answer is false. Cancellation is a request: a body that never asks runs to its end, and one that
// asks decides itself whether to return a partial result or to fail.
public func isCancelled()->bool
{
    let scope = Swag.getContext().cancelScope
    return scope != null and scope.isRaised()
}

// Runs `body` with `scope` as the cancellation state of this thread, then restores the previous one.
private func runInScope(scope: *CancelScope?, body: func||())
{
    let context  = Swag.getContext()
    let previous = context.cancelScope
    context.cancelScope = scope
    runTaskBody(body)
    context.cancelScope = previous
}

// How urgently a task's body competes for the processor with the rest of the process.
enum TaskPriority
{
    Normal         // As urgent as the code that submitted it.
    Background     // Yields to interactive work: the thread running it drops below normal priority.
}

// The part of a task that does not depend on the value it produces. The scheduler's entry reaches
// it through the node, whatever the task's result type.
#[Swag.NoDoc]
#[Swag.NoCopy]
struct TaskState
{
    using node: WorkNode
    run:        (func||())?     // Runs the body and stores its outcome; set at each submission.
    notify:     (func||())?     // Told the outcome exists, before the task reads as done.
    scope:      CancelScope     // The cancellation state the body observes.
    priority:   TaskPriority    // How urgently the body runs.
}

// One piece of work the runtime runs on its own schedule, and the outcome it produces.
//
// `T` is the type of the value the work produces; a task that produces nothing leaves it out.
// The body can fail: [[Swag.Task.take]] hands over either the value or the error, once.
//
// A task owns the closure it runs. Everything that closure reaches by address -- an `&` capture,
// a borrowed buffer, the task value itself -- must stay alive until the task is observed
// finished, which is what [[Swag.Task.wait]] establishes. A task cannot be copied: the runtime
// borrows its storage while the work is in flight.
//
// Destroying a task that still runs asks it to stop, then waits for it, including on an early
// return or a raised error: nobody can read its outcome any more, so the body may as well end.
// Captured storage must outlive that wait. Declare borrowed locals before the task; an owner
// with a task field must still wait before its own cleanup releases anything the task borrows.
// Waiting, including during destruction, must not hold a lock the task needs or wait on itself.
//
// The body has its own error state: a joining caller's handled or pending error does not decide
// the body's `defer #fail` or `defer #nofail`. A handled child error leaves the caller's error intact.
//
// A process with no worker thread runs the work inside [[Swag.Task.submit]], so a submitted task
// always reaches its end; only the thread that runs it changes.
//
// A task is worth submitting only when it carries real work. Publishing it, claiming it and
// observing it finish cost a few microseconds together, so a body below that runs faster where it
// was written. `parallel for` measures its own body and keeps short ranges on the caller; a task
// submitted by hand has no such protection.
//
// ```swag
// var task: Swag.Task'u64
// task.submit(func() => expensive())
// let total = try task.take()
// ```
#[Swag.NoCopy]
struct(T = void) Task
{
    // Scheduler and cancellation state shared by every result type.
    #[Swag.NoDoc]
    using state: TaskState

    // The work itself, owned by this task between submission and completion. A body that
    // cannot fail is kept apart: calling it needs no error frame, so tasks run inside one another
    // nest without consuming the bounded error stack.
    #[Swag.NoDoc]
    plainBody: (func||()->T)?

    // The work itself, when it can fail.
    #[Swag.NoDoc]
    fallibleBody: (func||()->T fail)?

    // The error the last run raised, if it failed.
    #[Swag.NoDoc]
    failure: Error

    #static if T != void
    {
        // The value the last run produced, until it is taken.
        #[Swag.NoDoc]
        result: T
    }
}

impl Task
{
    // Asks the work to stop, then waits for it before releasing the task's storage.
    mtd opDrop()
    {
        .cancel()
        .wait()
    }

    // Submits `body` for one execution.
    //
    // `notify`, when given, runs once on the thread that finished the work, after the outcome is
    // stored and before the task reads as done. It is how an owner on another thread learns that
    // [[Swag.Task.take]] will not wait, for example by posting an event to a window. It must be
    // short, and must not wait for this task.
    //
    // A `Background` task runs its body at a lower thread priority, whichever thread runs it, so
    // a long load or count does not slow the interface down.
    //
    // The task must not already be in flight. A task may be submitted again after it finished;
    // an outcome nobody took is released then.
    mtd submit(body: func||()->T, notify: (func||())? = null, priority = TaskPriority.Normal)
    {
        .prepare(notify, priority)
        .plainBody    = body
        .fallibleBody = null

        let task = me
        .run = func|task|() { task.runPlainBody() }
        submitWork(&.node)
    }

    // Submits a `body` that can fail for one execution; [[Swag.Task.take]] raises its error.
    mtd submit(body: func||()->T fail, notify: (func||())? = null, priority = TaskPriority.Normal)
    {
        .prepare(notify, priority)
        .plainBody    = null
        .fallibleBody = body

        let task = me
        .run = func|task|() { task.runFallibleBody() }
        submitWork(&.node)
    }

    // Asks the running work to stop.
    //
    // The request is idempotent and covers the current submission only. It stops nothing by
    // itself: the body observes it through [[Swag.isCancelled]], as does every task-group child
    // and `parallel for` partition the body starts.
    mtd cancel()
    {
        discard .scope.stop.raise()
    }

    // Returns whether a stop was requested for the current submission.
    mtd const isCancelled()->bool => .scope.stop.isRaised()

    // Returns whether the task is submitted and not finished.
    mtd const isPending()->bool
    {
        let state = .node.state.load()
        return state == WorkStateQueued or state == WorkStateRunning
    }

    // Returns whether the last submission finished and its outcome was not taken yet.
    //
    // A task that was never submitted is not done: it has nothing to report.
    mtd const isDone()->bool => .node.state.load() == WorkStateDone

    // Waits until the last submission has finished.
    //
    // The waiting thread can run this task if it is still queued; it does not run unrelated
    // ready tasks. Descendant-only joins therefore progress even when every worker is busy.
    // Waiting on a task that was never submitted returns immediately.
    mtd wait() => waitWork(&.node)

    // Waits for the work, then hands over its outcome: the value it produced, or the error it
    // raised, with its dynamic type.
    //
    // The outcome is handed over once. Afterwards the task is no longer done, and can be
    // submitted again.
    mtd take()->T fail
    {
        .wait()
        Swag.assert(.isDone(), "the task holds no outcome to take")
        .node.state.store(WorkStateIdle)

        defer .failure.reset()
        try .failure.raise()

        #static if T != void do
            return #move .result
    }
}

private impl Task
{
    // Readies a submission: the previous outcome and request no longer apply.
    mtd prepare(notify: (func||())?, priority: TaskPriority)
    {
        Swag.assert(not .isPending())
        .failure.reset()
        .notify     = notify
        .priority   = priority
        .node.entry = &taskEntry
        .scope.stop.reset()
    }

    // Runs a body that cannot fail and stores its value.
    mtd runPlainBody()
    {
        let body = .plainBody
        if not body do
            return

        #static if T == void do
            body()
        else do
            .result = body()
    }

    // Runs a body that can fail and stores its value or its error.
    mtd runFallibleBody()
    {
        let body = .fallibleBody
        if not body do
            return

        #static if T == void
        {
            catch body() as error
            if error != null do
                .failure.capture(error)
        }
        else
        {
            .result = catch body() as error
            if error != null do
                .failure.capture(error)
        }
    }
}

private func taskEntry(node: *WorkNode)
{
    let state = assume cast (*TaskState, node)
    let run   = state.run
    if not run do
        return

    let safeRun = run orelse func() {}
    if state.priority == .Background
    {
        let previous = __hostThreadEnterBackground()
        runInScope(&state.scope, safeRun)
        __hostThreadLeaveBackground(previous)
    }
    else
    {
        runInScope(&state.scope, safeRun)
    }

    if let notify = state.notify do
        notify()
}

// A helped child is a separate computation, even when its caller is handling or unwinding an
// error. Park the caller's error frame and hide its pending-failure marker from child defers.
// Completion restores the caller before the scheduler publishes the task as done.
private func runTaskBody(body: func||())
{
    // Ordinary descendant joins consume no error frames and need no error-stack bookkeeping.
    if not __isErrContext()
    {
        body()
        return
    }

    let context = Swag.getContext()
    __pushErr()
    let frame   = context.errorIndex - 1
    let pending = context.errors[frame].pushHasError
    context.errors[frame].pushHasError = 0
    context.traceIndex = 0

    body()

    context.errors[frame].pushHasError = pending
    __popErr()
}

// Children a group keeps inside itself, so a small group allocates nothing at all. A child holds
// a closure with room for its captures, so it is large: this storage is a deliberate trade of
// four hundred bytes of the owner's stack against one page reservation and its release.
private const GroupInlineCapacity = 4'u32

// Children of one [[Swag.TaskGroup]] beyond the inline storage, allocated in blocks so a node
// never moves.
//
// The bootstrap allocator rounds every request up to one host page. Size each block to fill
// that page, accounting for the allocation header and the aligned block header.

#[Swag.NoDoc]
struct GroupChild
{
    using node: WorkNode            // Scheduler state and dynamic identity.
    body:       (func||())?         // The child's work.
    scope:      *CancelScope?       // The cancellation state of the group that owns the child.
}

private const GroupBlockCapacity = cast(u32, ((AllocatorHostCommitGranularity - BootstrapAllocationHeaderSize - 2 * #sizeof(u64)) / #sizeof(GroupChild)))

#[Swag.NoDoc]
struct GroupBlock
{
    next:     *GroupBlock?     // Previously allocated block.
    used:     u32     // Children taken from this block.
    children: [GroupBlockCapacity] GroupChild     // Storage the scheduler borrows.
}

// One block must still fit the single page its allocation reserves.
#assert(#sizeof(GroupBlock) + BootstrapAllocationHeaderSize <= AllocatorHostCommitGranularity)

// Owns a set of child tasks and joins every one of them before it is released.
//
// The group is the lifetime that makes a spawn safe: a child can borrow anything that outlives
// the group, because the group cannot be released while a child is still running. Leaving the
// scope of a group joins its children, whether the scope ends normally, by an early return, or
// by a raised error.
// Children use the same isolated error state as [[Swag.Task]], including when the joining
// caller executes them during cleanup.
//
// Cancellation is a request, not a stop. [[Swag.TaskGroup.cancel]] raises a request every child
// reads through [[Swag.isCancelled]]; a child that never asks runs to its end. A group spawned
// from inside other work -- a task, a partition, another group's child -- also passes that work's
// request on to its children, so it must be joined before that work ends, which is what a group
// declared in the body does.
//
// The group holds its first children itself and takes one page for each further batch, so a small
// group allocates nothing. Because that storage belongs to the group, a captured borrow must
// outlive the group: declare what a child borrows before the group that joins it.
//
// ```swag
// var results: [4] u64
// {
//     var group: Swag.TaskGroup
//     for index in 4 do
//         group.spawn(func|&results, index|() { results[index] = compute(index) })
// }
// // Every child has finished here.
// ```
#[Swag.NoCopy]
struct TaskGroup
{
    // The first children, held by the group itself.
    #[Swag.NoDoc]
    inlined: [GroupInlineCapacity] GroupChild

    // Children taken from the inline storage.
    #[Swag.NoDoc]
    inlinedUsed: u32

    // Blocks holding the children beyond the inline storage, most recent first.
    #[Swag.NoDoc]
    blocks: *GroupBlock?

    // Children spawned into this group.
    #[Swag.NoDoc]
    count: u32

    // Raised by cancel, read by children.
    #[Swag.NoDoc]
    scope: CancelScope
}

impl TaskGroup
{
    // Joins every child, then releases the group's storage.
    mtd opDrop()
    {
        .wait()

        var block = .blocks
        while block
        {
            let next = block.next
            __bootstrapFree(cast([*] void?, block))
            block = next
        }

        .blocks      = null
        .count       = 0
        .inlinedUsed = 0
    }

    // Creates a child task running `body` and submits it.
    //
    // The child belongs to this group until the group joins it. `body` reads the group's
    // cancellation state, and that of the work spawning it, through [[Swag.isCancelled]].
    mtd spawn(body: func||())
    {
        .scope.parent = Swag.getContext().cancelScope

        let child = .reserveChild()
        child.body       = body
        child.scope      = &.scope
        child.node.entry = &groupChildEntry
        .count           += 1
        submitWork(&child.node)
    }

    // Waits until every child spawned so far has finished.
    //
    // The waiting thread can run the child it is joining, but does not run unrelated ready
    // tasks. Children spawned after this call are not covered by it; leaving the group's scope
    // joins those too.
    mtd wait()
    {
        for index in .inlinedUsed do
            waitWork(&.inlined[index].node)

        var block = .blocks
        while block
        {
            for index in block.used do
                waitWork(&block.children[index].node)
            block = block.next
        }
    }

    // Requests that every child stop.
    //
    // The request is idempotent and is never withdrawn. It stops nothing by itself: a child
    // observes it through [[Swag.isCancelled]] and returns early on its own.
    mtd cancel()
    {
        discard .scope.stop.raise()
    }

    // Returns whether cancellation was requested for this group, or for the work that spawned it.
    mtd const isCancelled()->bool => .scope.isRaised()

    // Returns storage for one more child, allocating a block when the inline storage and the
    // current block are both full.
    private mtd reserveChild()->*GroupChild
    {
        if .inlinedUsed < GroupInlineCapacity
        {
            let child = &.inlined[.inlinedUsed]
            .inlinedUsed += 1
            return child
        }

        let head = .blocks
        if head and head.used < GroupBlockCapacity
        {
            let child = &head.children[head.used]
            head.used += 1
            return child
        }

        let block = cast(*GroupBlock?, __bootstrapAlloc(#sizeof(GroupBlock)))
        if not block do
            Swag.panic("cannot allocate task group storage", #curlocation)

        Swag.init(block, 1)
        block.next = .blocks
        block.used = 1
        .blocks    = block
        return &block.children[0]
    }
}

private func groupChildEntry(node: *WorkNode)
{
    let child = assume cast (*GroupChild, node)
    let body  = child.body
    if not body do
        return

    let safeBody = body orelse func() {}
    runInScope(child.scope, safeBody)
}
