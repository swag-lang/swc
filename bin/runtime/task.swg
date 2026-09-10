#global namespace Swag

// One piece of work the runtime runs on its own schedule.
//
// A task owns the closure it runs. Everything that closure reaches by address -- an `&` capture,
// a borrowed buffer, the task value itself -- must stay alive until the task is observed
// finished, which is what [[Swag.Task.wait]] establishes. Destruction also waits, including on
// an early return or a raised error. A task cannot be copied: the runtime borrows its storage
// while the work is in flight.
//
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
// var total = 0'u64
// var task:  Swag.Task
//
// task.submit(func|&total|() { total = expensive() })
// task.wait()
// ```
#[Swag.NoCopy]
struct Task
{
    // Scheduler state. Must stay first: the entry recovers the task from its node.
    #[Swag.NoDoc]
    using node: WorkNode

    // The work itself, owned by this task between submission and completion.
    #[Swag.NoDoc]
    body: (func||())?
}

impl Task
{
    // Waits for the last submission before releasing the task's storage.
    mtd opDrop()
    {
        .wait()
    }

    // Submits `body` for one execution.
    //
    // The task must not already be in flight. A task may be submitted again after it finished.
    mtd submit(body: func||())
    {
        Swag.assert(not .isPending())
        .body       = body
        .node.entry = &taskEntry
        submitWork(&.node)
    }

    // Returns whether the task is submitted and not finished.
    mtd const isPending()->bool
    {
        let state = .node.state.load()
        return state == WorkStateQueued or state == WorkStateRunning
    }

    // Returns whether the last submission finished.
    //
    // A task that was never submitted is not done: it has nothing to report.
    mtd const isDone()->bool => .node.state.load() == WorkStateDone

    // Waits until the last submission has finished.
    //
    // The waiting thread can run this task if it is still queued; it does not run unrelated
    // ready tasks. Descendant-only joins therefore progress even when every worker is busy.
    // Waiting on a task that was never submitted returns immediately.
    mtd wait() => waitWork(&.node)
}

private func taskEntry(node: *WorkNode)
{
    let task = cast(*Task) node
    let body = task.body
    if not body do
        return

    let safeBody = body orelse func() {}
    runTaskBody(safeBody)
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
// The bootstrap allocator rounds every request up to one host page, so a block of sixteen
// children already paid for a whole page and used a sixth of it. Filling that page instead costs
// nothing and makes a large group take one page per thirty-nine children rather than one per
// sixteen. The assertion below keeps that claim true if a child ever grows.
private const GroupBlockCapacity = 39'u32

#[Swag.NoDoc]
struct GroupChild
{
    using node: WorkNode        // Scheduler state. Must stay first.
    body:       (func||())?     // The child's work.
}

#[Swag.NoDoc]
struct GroupBlock
{
    next:     *GroupBlock?                        // Previously allocated block.
    used:     u32                                 // Children taken from this block.
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
// Cancellation is a request, not a stop. [[Swag.TaskGroup.cancel]] raises a flag every child can
// read; a child that never looks at it runs to its end.
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
    stop: AtomicFlag
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
            __bootstrapFree(cast([*] void?) block)
            block = next
        }

        .blocks      = null
        .count       = 0
        .inlinedUsed = 0
    }

    // Creates a child task running `body` and submits it.
    //
    // The child belongs to this group until the group joins it. `body` may read the group's
    // cancellation state through a captured reference to the group.
    mtd spawn(body: func||())
    {
        let child = .reserveChild()
        child.body       = body
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
    // observes it through [[Swag.TaskGroup.isCancelled]] and returns early on its own.
    mtd cancel()
    {
        discard .stop.raise()
    }

    // Returns whether cancellation was requested for this group.
    mtd const isCancelled()->bool => .stop.isRaised()

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

        let block = cast(*GroupBlock?) __bootstrapAlloc(#sizeof(GroupBlock))
        if not block do
            Swag.panic("cannot allocate task group storage", #curlocation)

        block.next = .blocks
        block.used = 1
        .blocks    = block
        return &block.children[0]
    }
}

private func groupChildEntry(node: *WorkNode)
{
    let child = cast(*GroupChild) node
    let body  = child.body
    if not body do
        return

    let safeBody = body orelse func() {}
    runTaskBody(safeBody)
}
