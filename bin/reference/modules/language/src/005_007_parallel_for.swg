#global private

/**
# The 'parallel for' Statement

'parallel for' runs the iterations of an index range across the process worker
pool and returns when every one of them has finished. It is the language form
of independent work: the body must produce the same result whatever order the
indices run in and whichever thread runs them.

The runtime adapts the number of partitions to observed iteration cost. Short
work can stay entirely on the calling thread, even when workers exist. An
unknown loop can execute an initial iteration before distributing the rest;
later calls reuse and periodically refresh the cost estimate. This is a
scheduling hint, not a time bound: changing inputs and uneven iteration costs
can change which execution plan is useful. Every iteration still runs once,
and the statement still waits for all accepted work before returning.

The calling thread can execute the partition it is joining, including work
that partition explicitly joins in turn. It does not drain unrelated tasks
from the pool during the join. A partition that needs a lock held by its
caller can still deadlock; joining does not prove lock ordering correct.

The statement names its index like an ordinary 'for', and states between
'|...|' what the body reaches from the enclosing scope. That capture list is
the same one a closure takes, and it is written rather than inferred: what the
body shares with other partitions is the whole safety question, so it is
visible at the loop instead of hidden inside it.
*/
#test
{
    var squares: [16] u64

    parallel for |&squares| index in 16 do
        squares[index] = index * index

    Swag.assert(squares[0] == 0)
    Swag.assert(squares[15] == 225)
}

/**
# Capturing the Surrounding Scope

'&name' captures the variable itself, so the body reads and writes the
original storage; a bare name captures a copy of its value. Independent
destinations -- one array element per index, one row per index -- need no
synchronization, because no two iterations touch the same storage.
*/
#test
{
    let factor = 3'u64
    var values: [8] u64

    parallel for |&values, factor| index in 8 do
        values[index] = index * factor

    Swag.assert(values[7] == 21)
}

/**
# Ranges

The range is written like a 'for' range: a count, 'a until b' for a half-open
range, or 'a to b' when the upper bound belongs to it. A range that is empty
runs no iteration at all.
*/
#test
{
    var visited: [10] bool

    parallel for |&visited| index in 2 until 5 do
        visited[index] = true

    parallel for |&visited| index in 7 to 8 do
        visited[index] = true

    Swag.assert(!visited[1] and visited[2] and visited[4] and !visited[5])
    Swag.assert(visited[7] and visited[8] and !visited[9])
}

/**
# What the Body May Do

The body of one index is an ordinary block: it can declare, branch, loop, and
'continue' to the next index. It cannot leave the statement early. A 'break'
that would leave the loop, and a 'return' that would leave the enclosing
function, are rejected, because either one would skip indices the statement
promises to run while other partitions keep going.

Compute the answer into captured storage and act on it after the loop.
*/
#test
{
    var found: [32] bool

    parallel for |&found| index in 32
    {
        if index & 1 do
            continue
        found[index] = true
    }

    var count = 0
    for index in 32 where found[index] do
        count += 1
    Swag.assert(count == 16)
}

/**
# Shared Results

An accumulator every index writes is shared storage, so it goes through
[[Swag.AtomicValue]] rather than an ordinary variable.
*/
#test
{
    var total: Swag.AtomicValue'u64

    parallel for |&total| index in 100 do
        total.add(index)

    Swag.assert(total.load() == 4950)
}

/**
> NOTE:
> The number of partitions is not part of the contract, and neither is the
> thread a given index runs on. During compile-time execution, the whole range
> runs on the calling thread. Native execution starts the pool on demand;
> with fewer than two workers, the range also runs on the calling thread.
*/
