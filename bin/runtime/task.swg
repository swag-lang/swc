#global namespace Swag

// One piece of work the runtime runs on its own schedule.
//
// A task owns the closure it runs. Everything that closure reaches by address -- an `&` capture,
// a borrowed buffer, the task value itself -- must stay alive until the task is observed
// finished, which is what [[Swag.Task.wait]] establishes. A task cannot be copied: the runtime
// borrows its storage while the work is in flight.
//
// A process with no worker thread runs the work inside [[Swag.Task.submit]], so a submitted task
// always reaches its end; only the thread that runs it changes.
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
    // Releases the task, which must no longer be in flight.
    mtd opDrop()
    {
        Swag.assert(!.isPending())
    }

    // Submits `body` for one execution.
    //
    // The task must not already be in flight. A task may be submitted again after it finished.
    mtd submit(body: func||())
    {
        Swag.assert(!.isPending())
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
    // The waiting thread runs ready work while it waits, so the wait makes progress even when
    // every worker is busy. Waiting on a task that was never submitted returns immediately.
    mtd wait() => waitWork(&.node)
}

private func taskEntry(node: *WorkNode)
{
    let task = cast(*Task) node
    let body = task.body
    if !body do
        return

    let safeBody = body orelse func() {}
    safeBody()
}

// Children of one [[Swag.TaskGroup]], allocated in blocks so a node never moves.
private const GroupBlockCapacity = 16'u32

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

// Owns a set of child tasks and joins every one of them before it is released.
//
// The group is the lifetime that makes a spawn safe: a child can borrow anything that outlives
// the group, because the group cannot be released while a child is still running. Leaving the
// scope of a group joins its children, whether the scope ends normally, by an early return, or
// by a raised error.
//
// Cancellation is a request, not a stop. [[Swag.TaskGroup.cancel]] raises a flag every child can
// read; a child that never looks at it runs to its end.
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
    // Blocks holding the children, most recent first.
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

        .blocks = null
        .count  = 0
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
    // The waiting thread runs ready work while it waits. Children spawned after this call are
    // not covered by it; leaving the group's scope joins those too.
    mtd wait()
    {
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

    // Returns storage for one more child, allocating a block when the current one is full.
    private mtd reserveChild()->*GroupChild
    {
        let head = .blocks
        if head and head.used < GroupBlockCapacity
        {
            let child = &head.children[head.used]
            head.used += 1
            return child
        }

        let block = cast(*GroupBlock?) __bootstrapAlloc(#sizeof(GroupBlock))
        if !block do
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
    if !body do
        return

    let safeBody = body orelse func() {}
    safeBody()
}
