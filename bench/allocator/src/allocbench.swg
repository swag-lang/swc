using Core

// Allocation workloads for the runtime allocator, one per process so that the runner can read the
// process's peak working set and commit for that workload alone. Every block goes through
// 'Memory.alloc' and 'Memory.free', the path ordinary Swag code takes, and every allocated payload
// is touched. 'allocbench.c' runs the same workloads against mimalloc and the C runtime heap.
//
// Usage: allocbench <pair|trees|churn|medium|large|realloc|spread|grow|xfer> [threads]

const ChurnSlots  = 50_000'u64
const LargeSlots  = 32'u64
const MediumSlots = 256'u64
const XferCount   = 2_000_000'u64
const XferRing    = 4096'u64
const SpreadSizes = [16'u64, 48, 100, 200, 500, 1000, 3000, 6000, 12000, 20000, 40000, 60000]

enum Workload
{
    Pair        // One 32-byte block allocated and freed, over and over
    Trees       // Binary trees of 16-byte nodes, built then freed
    Churn       // 50 000 live blocks of mostly small, mixed sizes, replaced at random
    Medium      // 256 live blocks of 4 KiB to 64 KiB, replaced at random
    Large       // 32 live blocks of 64 KiB to 1 MiB, replaced at random, one byte touched per page
    Realloc     // Buffers doubled from 16 bytes to 4 MiB through reallocation
    Spread      // A few live blocks of twelve sizes, as a long-running application holds them
    Grow        // Four million 32-byte blocks allocated before any is freed
    Xfer        // Producer/consumer pairs: one thread allocates, the other frees
}

struct Xorshift
{
    state: u64
}

impl Xorshift
{
    #[Swag.Safety(.Overflow, false)]
    mtd next()->u64
    {
        .state ^= .state << 13
        .state ^= .state >> 7
        .state ^= .state << 17
        return .state
    }

    // Mostly small sizes, with a tail up to 17 KiB, as general-purpose programs request them.
    mtd smallSize()->u64
    {
        let r = .next()
        switch r & 0xFF
        {
        case 0 until 160:   return 8 + ((r >> 8) & 63)
        case 160 until 230: return 16 + ((r >> 8) & 255)
        case 230 until 252: return 64 + ((r >> 8) & 2047)
        }

        return 1024 + ((r >> 8) & 16383)
    }
}

struct Node
{
    left:  *Node?
    right: *Node?
}

func buildTree(depth: s32)->*Node
{
    let node = cast(*Node, Memory.alloc(#sizeof(Node)))
    node.left  = depth > 0 ? buildTree(depth - 1) : null
    node.right = depth > 0 ? buildTree(depth - 1) : null
    return node
}

func freeTree(node: *Node)
{
    if node.left and node.right
    {
        freeTree(node.left)
        freeTree(node.right)
    }

    Memory.free(node, #sizeof(Node))
}

// A table of live blocks replaced at random, sized by 'nextSize'.
func churn(random: *Xorshift, slots: u64, operations: u64, nextSize: func(*Xorshift)->u64, touchEveryPage: bool)
{
    let addresses = cast([*] u64, Memory.alloc(slots * #sizeof(u64)))
    let sizes     = cast([*] u64, Memory.alloc(slots * #sizeof(u64)))
    defer
    {
        for i in slots do
            Memory.free(cast([*] void, addresses[i]), sizes[i])
        Memory.free(addresses, slots * #sizeof(u64))
        Memory.free(sizes, slots * #sizeof(u64))
    }

    for i in slots
    {
        sizes[i]     = nextSize(random)
        addresses[i] = cast(u64, Memory.alloc(sizes[i]))
    }

    for operations
    {
        let i = random.next() % slots
        Memory.free(cast([*] void, addresses[i]), sizes[i])
        sizes[i] = nextSize(random)
        let block = cast([*] u8, Memory.alloc(sizes[i]))
        block[0] = 1
        block[sizes[i] - 1] = 1
        if touchEveryPage
        {
            for page in sizes[i] / 4096 do
                block[page * 4096] = 1
        }

        addresses[i] = cast(u64, block)
    }
}

func smallSize(random: *Xorshift)->u64  => random.smallSize()
func mediumSize(random: *Xorshift)->u64 => 4096 + random.next() % 61440
func largeSize(random: *Xorshift)->u64  => 65536 + random.next() % (1024 * 1024 - 65536)

// Runs one workload on the calling thread and returns the operations it performed.
func run(workload: Workload, seed: u64)->u64
{
    var random = Xorshift{seed}
    switch workload
    {
    case .Pair:
        for 20_000_000
        {
            let block = cast([*] u8, Memory.alloc(32))
            block[0] = 1
            Memory.free(block, 32)
        }

        return 20_000_000

    case .Trees:
        for 40 do
            freeTree(buildTree(14))
        return 40 * (1 << 15)

    case .Churn:
        churn(&random, ChurnSlots, 10_000_000, &smallSize, false)
        return 10_000_000

    case .Medium:
        churn(&random, MediumSlots, 2_000_000, &mediumSize, false)
        return 2_000_000

    case .Large:
        churn(&random, LargeSlots, 200_000, &largeSize, true)
        return 200_000

    case .Realloc:
        var operations = 0'u64
        for 2000
        {
            var size  = 16'u64
            var block = cast([*] u8, Memory.alloc(size))
            while size < 4 * 1024 * 1024
            {
                block           = cast([*] u8, Memory.realloc(block, size * 2, size))
                size            *= 2
                block[size - 1] = 1
                operations      += 1
            }

            Memory.free(block, size)
        }

        return operations

    case .Grow:
        const Count = 4_000_000'u64
        let addresses = cast([*] u64, Memory.alloc(Count * #sizeof(u64)))
        for i in Count
        {
            let block = cast([*] u8, Memory.alloc(32))
            block[0]     = 1
            addresses[i] = cast(u64, block)
        }

        for i in Count do
            Memory.free(cast([*] void, addresses[i]), 32)
        Memory.free(addresses, Count * #sizeof(u64))
        return Count * 2

    case .Spread:
        var addresses: [SpreadSizes.count * 10] u64
        for i in addresses.count
        {
            let block = cast([*] u8, Memory.alloc(SpreadSizes[i / 10]))
            block[0]     = 1
            addresses[i] = cast(u64, block)
        }

        for i in addresses.count do
            Memory.free(cast([*] void, addresses[i]), SpreadSizes[i / 10])
        return addresses.count
    }

    unreachable
}

// One ring per producer/consumer pair. The producer publishes a block by advancing 'head' after
// writing its slot; the consumer frees it and advances 'tail'.
struct Ring
{
    slots: [XferRing] u64
    head:  u64
    tail:  u64
}

struct Job
{
    workload:   Workload
    seed:       u64
    operations: u64
    ring:       *Ring?
    producer:   bool
}

func produce(ring: *Ring, seed: u64)
{
    var random = Xorshift{seed}
    for XferCount
    {
        let block = cast([*] u8, Memory.alloc(random.smallSize()))
        block[0] = 1
        while Swag.atomget(&ring.head) - Swag.atomget(&ring.tail) >= XferRing {}
        ring.slots[ring.head % XferRing] = cast(u64, block)
        discard Swag.atomxchg(&ring.head, ring.head + 1)
    }
}

// The consumer does not know the sizes, which the runtime allocator does not need.
func consume(ring: *Ring)
{
    for XferCount
    {
        while Swag.atomget(&ring.head) == ring.tail {}
        Memory.free(cast([*] void, ring.slots[ring.tail % XferRing]), 0)
        discard Swag.atomxchg(&ring.tail, ring.tail + 1)
    }
}

func parseWorkload(name: string)->Workload fail
{
    switch name
    {
    case "pair":    return .Pair
    case "trees":   return .Trees
    case "churn":   return .Churn
    case "medium":  return .Medium
    case "large":   return .Large
    case "realloc": return .Realloc
    case "spread":  return .Spread
    case "grow":    return .Grow
    case "xfer":    return .Xfer
    }

    fail Errors.BadParameterError{}
}

#main
{
    let args     = Swag.args()
    let workload = catch parseWorkload(args.count > 1 ? args[1] : "") as badWorkload
    let threads  = args.count > 2 ? catch StrConv.toU32(args[2]) : 1
    if badWorkload != null or threads < 1 or threads > 16
    {
        Console.println("usage: allocbench <pair|trees|churn|medium|large|realloc|spread|grow|xfer> [threads 1-16]")
        return
    }

    var jobs:  [32] Job
    var rings: [16] Ring
    var pool:  [32] Threading.Thread
    let count = workload == .Xfer ? threads * 2 : threads

    var watch: Time.Stopwatch
    watch.start()
    for i in count
    {
        jobs[i].workload = workload
        jobs[i].seed     = 1000 + i * 7919
        jobs[i].ring     = workload == .Xfer ? &rings[i / 2] : null
        jobs[i].producer = i % 2 == 0
        try pool[i].init(func||(thread: Threading.Thread)
        {
            let job = cast(*Job, thread.userParam!)
            if job.workload != .Xfer
            {
                job.operations = run(job.workload, job.seed)
            }
            elif job.producer
            {
                produce(job.ring!, job.seed)
            }
            else
            {
                consume(job.ring!)
                job.operations = XferCount
            }
        },
                         &jobs[i])
        try pool[i].start()
    }

    var operations = 0'u64
    for i in count
    {
        pool[i].wait()
        operations += jobs[i].operations
    }

    watch.stop()
    let ns = cast(f64, watch.elapsedMicroseconds()) * 1000.0 / cast(f64, operations)
    Console.println("allocbench workload=", args[1], " threads=", threads, " operations=", operations, " ns/op=", ns)
}
