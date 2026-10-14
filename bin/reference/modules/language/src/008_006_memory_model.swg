#global private

/**
# Memory Model

Threads share memory. A 'parallel for' partition, a 'Swag.TaskGroup' child, a 'Swag.Task'
body, and the thread of a 'Swag.Executor' all read and write the same storage as the code that
started them. This page states what one thread may assume about the writes of another.

The compiler and the processor both reorder memory accesses for speed. Everything below is
what they keep; nothing else is promised.

# Data Races

Two accesses conflict when they reach the same memory location, at least one of them writes,
and they come from different threads. A program has a **data race** when two conflicting
accesses are not both atomic and neither happens before the other.

A data race is a defect, not a slower path. The compiler assumes there is none: it keeps a
value in a register, merges two reads, or moves a write. The processor may delay a write, or
let a later read pass it. A racing read may therefore return a stale value, a value no thread
ever wrote whole, or a different value each time it is repeated. The safety checks bound
memory accesses and lifetimes; they do not make a race defined.

# Happens Before

One access happens before another in these cases, and through any chain of them:

- both are in one thread, and the first comes first in the program;
- releasing a 'Swag.Mutex' or a 'Swag.RWLock' happens before acquiring it again;
- releasing a 'Swag.Semaphore' permit happens before the acquisition that takes it, and every
  arrival at a 'Swag.Barrier' phase happens before any participant leaves that phase;
- submitting a 'Swag.Task' happens before its body starts, and the end of the body happens
  before 'wait', 'take' or 'isDone' returning, and before the 'Gui.TaskEvent' it posts is
  delivered;
- spawning a 'Swag.TaskGroup' child happens before it starts, and the end of every child
  happens before 'join' or 'wait' returns;
- entering a 'parallel for' happens before each partition starts, and the end of each
  partition happens before the statement after the loop;
- the end of one task of a 'Swag.Executor' happens before the next one starts;
- an atomic write happens before an atomic read that returns the value it wrote, with the
  orders described below.

Everything a thread wrote before one of these edges is visible after it, ordinary accesses
included. That is how a body reads its captured inputs without any atomic operation, and how
the code after a join reads what the partitions wrote.
*/
#test
{
    var squares: [8] u64

    parallel for |&squares| index in 8 do
        squares[index] = index * index

    // The join is the edge: every partition's write happens before these reads.
    for index in 8 do
        Swag.assert(squares[index] == index * index)
}

/**
# Atomic Operations

An operation of 'Swag.AtomicValue', and each atomic intrinsic, is atomic: no thread sees it
half done, and two of them on one location never race. By default they are also
**sequentially consistent**. All of them, on every location, happen in one order that every
thread observes and that agrees with each thread's program order. It is the strongest order,
and the one to reason with.

Two weaker forms give up part of that guarantee for speed, where a stated reason allows it:

- 'storeRelease' and 'loadAcquire' go in pairs. When an acquire read returns the value a
  release write stored, everything the writing thread did before the write happens before
  everything the reading thread does after the read. That is what publishing data behind a
  flag, or releasing a lock, needs. It is not one order for all threads: two threads may see
  two unrelated release writes in different orders, and a read of another location that
  follows a release write in the same thread may pass it.
- 'storeRelaxed' and 'loadRelaxed' order nothing beyond the value itself. They suit a count
  or a statistic that no other access depends on.

Read-modify-write operations, 'add', 'exchange', 'compareExchange' and the bitwise forms, are
always sequentially consistent.
*/
#test
{
    var data:  u64
    var ready: Swag.AtomicValue'u32
    var task:  Swag.Task

    task.submit(func|&data, &ready|()
    {
        // An ordinary write, published by the release write that follows it.
        data = 42
        ready.storeRelease(1)
    })

    // An acquire read that returns the flag also sees what was written before it.
    while ready.loadAcquire() == 0 {}
    Swag.assert(data == 42)
    task.wait()
}

/**
# What the Compiler Keeps

An atomic operation is an ordering point for the optimizer, whatever its order. No ordinary
access moves across it, is merged with an access on its other side, or is assumed unchanged
across it, even storage the function never writes itself. Two kinds of storage are exempt, by
contract rather than by analysis:

- a struct parameter is a value frozen for the call, so another thread changing it while the
  call runs is a data race;
- a function marked '#[Swag.ReadOnly]' is assumed to write nothing, so reads move across a
  call to it: it must not be how a thread waits for another.

On x86-64, an atomic read and a release or relaxed write are plain moves. A sequentially
consistent write and every read-modify-write take a bus lock.

# Atomic Storage

While other threads may reach a location, every access to it must be atomic. Before it is
shared, and after every thread that shared it has been joined, it is ordinary storage again:
initializing a 'Swag.AtomicValue' in its declaration, or reading it after a join, needs no
atomic operation.
*/
#test
{
    var visited: Swag.AtomicValue'u32

    parallel for |&visited| 16 do
        visited.add(1)

    Swag.assert(visited.loadRelaxed() == 16)
}
