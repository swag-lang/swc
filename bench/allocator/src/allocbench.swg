using Core

// Allocation workloads for the runtime allocator, one per process so that the runner can read the
// process's peak working set and commit for that workload alone. Every block goes through
// 'Memory.alloc' and 'Memory.free', the path ordinary Swag code takes, and every allocated payload
// is touched. 'allocbench.c' runs the same workloads against mimalloc and the C runtime heap.
//
// Usage: allocbench <pair|trees|churn|medium|large|realloc|spread|grow|xfer|aligned|huge|spreadrep|retain> [threads] [latency]
//
// The clock runs from before the first thread is created until the last one is joined, so a
// short workload also measures the thread lifecycle; every worker therefore times its own body too,
// and the slowest worker's nanoseconds per operation are reported beside the end-to-end figure.
// 'spreadrep' repeats the spread body behind a gate every worker reaches before the phase clock
// starts, which amortizes thread creation. 'retain' reports the process working set once its live
// set is freed, after the purge delay has passed, and after trim(). With 'latency', one worker
// records the duration of each of its operations, or of each batch of sixty-four for the
// workloads whose operations are shorter than the clock resolves, and the 50th and 99th
// percentiles are reported. Every run ends with the reservations, commits and decommits the
// runtime allocator asked the system for.

const ChurnSlots        = 50_000'u64
const LargeSlots        = 32'u64
const MediumSlots       = 256'u64
const XferCount         = 2_000_000'u64
const XferRing          = 4096'u64
const SpreadSizes       = [16'u64, 48, 100, 200, 500, 1000, 3000, 6000, 12000, 20000, 40000, 60000]
const HugeBytes         = 32'u64 * 1024 * 1024
const HugeRounds        = 200'u64
const SpreadRepRounds   = 10_000'u64
const LatencyMaxSamples = 4_000_000'u64
const LatencyBatch      = 64'u64

enum Workload
{
    Pair          // One 32-byte block allocated and freed, over and over
    Trees         // Binary trees of 16-byte nodes, built then freed
    Churn         // 50 000 live blocks of mostly small, mixed sizes, replaced at random
    Medium        // 256 live blocks of 4 KiB to 64 KiB, replaced at random
    Large         // 32 live blocks of 64 KiB to 1 MiB, replaced at random, one byte touched per page
    Realloc       // Buffers doubled from 16 bytes to 4 MiB through reallocation
    Spread        // A few live blocks of twelve sizes, as a long-running application holds them
    Grow          // Four million 32-byte blocks allocated before any is freed
    Aligned       // Batches of 1024 mixed blocks aligned on 32 or 64 bytes
    Huge          // 32 MiB blocks, one at a time, every page touched: above the block cache
    SpreadRep     // The spread body repeated ten thousand times behind a start gate
    Retain        // A live set freed, then the working set while idle, after the purge, after trim
    Xfer          // Producer/consumer pairs: one thread allocates, the other frees
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

// The durations one worker records, in clock ticks, one per operation or per batch of operations.
struct Latency
{
    samples: [*] u32?
    count:   u64
    unit:    u64     // Operations per sample
}

impl Latency
{
    mtd record(ticks: u64)
    {
        if .count < LatencyMaxSamples
        {
            .samples![.count] = cast(u32, Math.min(ticks, cast(u64, Swag.U32.Max)))
            .count += 1
        }
    }

    // The sample at 'rank' per thousand, in nanoseconds.
    mtd percentile(rank: u64)->f64
    {
        if .count == 0 do
            return 0
        let sorted = Swag.makeSlice(.samples!, .count)
        Slice.sort(sorted)
        let index = Math.min((.count * rank) / 1000, .count - 1)
        return cast(f64, sorted[index]) * 1.0e9 / cast(f64, Time.monotonicFrequency())
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

// A table of live blocks replaced at random, sized by 'nextSize'. With a recorder, every
// replacement is timed on its own when 'perOperation' is set, else by batches.
func churn(random: *Xorshift, slots: u64, operations: u64, nextSize: func(*Xorshift)->u64, touchEveryPage: bool, latency: *Latency?, perOperation: bool)
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

    let unit = perOperation ? 1 : LatencyBatch
    if latency do
        latency.unit = unit

    var start = latency ? Time.monotonicTicks() : 0
    for n in operations
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
        if latency and (n + 1) % unit == 0
        {
            let now = Time.monotonicTicks()
            latency.record(now - start)
            start = now
        }
    }
}

func smallSize(random: *Xorshift)->u64  => random.smallSize()
func mediumSize(random: *Xorshift)->u64 => 4096 + random.next() % 61440
func largeSize(random: *Xorshift)->u64  => 65536 + random.next() % (1024 * 1024 - 65536)

// Repeated batches isolate aligned allocation from thread startup and keep its
// large pointer tables out of the other workloads' stack frames.
#[Swag.NoInline]
func alignedBatches(random: *Xorshift, latency: *Latency?)->u64
{
    var blocks: [1024] ([*] u8?)
    var sizes:  [1024] u64
    if latency do
        latency.unit = blocks.count
    for 10_000
    {
        let start = latency ? Time.monotonicTicks() : 0
        for i in blocks.count
        {
            let size      = 1 + (random.next() & 4095)
            let alignment = (i & 1) == 0 ? 32'u32 : 64'u32
            let block     = cast([*] u8, Memory.alloc(size, alignment: alignment))
            block[0]        = 1
            block[size - 1] = 1
            blocks[i]       = block
            sizes[i]        = size
        }

        for block, i in blocks do
            Memory.free(block, sizes[i])
        if latency do
            latency.record(Time.monotonicTicks() - start)
    }

    return 10_000 * blocks.count
}

// Ten live blocks of each of twelve sizes, allocated then freed: what 'spread' does once and
// 'spreadrep' repeats.
func spreadBody()->u64
{
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

// The process working set, which is what every program under comparison can report.
func workingSet()->u64
{
    var counters: Win32.PROCESS_MEMORY_COUNTERS
    counters.cb = cast(u32, #sizeof(counters))
    discard Win32.K32GetProcessMemoryInfo(Win32.GetCurrentProcess(), &counters, counters.cb)
    return counters.WorkingSetSize
}

struct Retained
{
    idle, purged, trimmed: u64
}

// Allocates the churn, medium and large live sets at once, frees them all, then reports what the
// process keeps: at once, after the purge delay has passed and an allocation has run a purge
// check, and after trim().
func retain(random: *Xorshift)->Retained
{
    const Small = 50_000'u64
    let small      = cast([*] u64, Memory.alloc(Small * #sizeof(u64)))
    let smallSizes = cast([*] u64, Memory.alloc(Small * #sizeof(u64)))
    var medium:      [MediumSlots] u64
    var mediumSizes: [MediumSlots] u64
    var large:       [LargeSlots] u64
    var largeSizes:  [LargeSlots] u64
    for i in Small
    {
        smallSizes[i] = random.smallSize()
        let block = cast([*] u8, Memory.alloc(smallSizes[i]))
        block[0] = 1
        small[i] = cast(u64, block)
    }

    for i in MediumSlots
    {
        mediumSizes[i] = mediumSize(random)
        let block = cast([*] u8, Memory.alloc(mediumSizes[i]))
        for page in mediumSizes[i] / 4096 do
            block[page * 4096] = 1
        medium[i] = cast(u64, block)
    }

    for i in LargeSlots
    {
        largeSizes[i] = largeSize(random)
        let block = cast([*] u8, Memory.alloc(largeSizes[i]))
        for page in largeSizes[i] / 4096 do
            block[page * 4096] = 1
        large[i] = cast(u64, block)
    }

    for i in Small do
        Memory.free(cast([*] void, small[i]), smallSizes[i])
    for i in MediumSlots do
        Memory.free(cast([*] void, medium[i]), mediumSizes[i])
    for i in LargeSlots do
        Memory.free(cast([*] void, large[i]), largeSizes[i])
    Memory.free(small, Small * #sizeof(u64))
    Memory.free(smallSizes, Small * #sizeof(u64))

    var result: retval
    result.idle = workingSet()
    Threading.Thread.sleep(700'ms)
    Memory.free(Memory.alloc(1024 * 1024), 1024 * 1024)
    result.purged = workingSet()
    Swag.defaultAllocator().trim()
    result.trimmed = workingSet()
    return result
}

// Runs one workload on the calling thread and returns the operations it performed.
func run(workload: Workload, seed: u64, latency: *Latency?)->u64
{
    var random = Xorshift{seed}
    switch workload
    {
    case .Pair:
        if latency do
            latency.unit = LatencyBatch
        var start = latency ? Time.monotonicTicks() : 0
        for n in 20_000_000
        {
            let block = cast([*] u8, Memory.alloc(32))
            block[0] = 1
            Memory.free(block, 32)
            if latency and (n + 1) % LatencyBatch == 0
            {
                let now = Time.monotonicTicks()
                latency.record(now - start)
                start = now
            }
        }

        return 20_000_000

    case .Trees:
        for 40 do
            freeTree(buildTree(14))
        return 40 * (1 << 15)

    case .Aligned:
        return alignedBatches(&random, latency)

    case .Huge:
        if latency do
            latency.unit = 1
        for HugeRounds
        {
            let start = latency ? Time.monotonicTicks() : 0
            let block = cast([*] u8, Memory.alloc(HugeBytes))
            for page in HugeBytes / 4096 do
                block[page * 4096] = 1
            Memory.free(block, HugeBytes)
            if latency do
                latency.record(Time.monotonicTicks() - start)
        }

        return HugeRounds

    case .Churn:
        churn(&random, ChurnSlots, 10_000_000, &smallSize, false, latency, false)
        return 10_000_000

    case .Medium:
        churn(&random, MediumSlots, 2_000_000, &mediumSize, false, latency, true)
        return 2_000_000

    case .Large:
        churn(&random, LargeSlots, 200_000, &largeSize, true, latency, true)
        return 200_000

    case .Realloc:
        var operations = 0'u64
        if latency do
            latency.unit = 1
        for 2000
        {
            var size  = 16'u64
            var block = cast([*] u8, Memory.alloc(size))
            while size < 4 * 1024 * 1024
            {
                let start = latency ? Time.monotonicTicks() : 0
                block           = cast([*] u8, Memory.realloc(block, size * 2, size))
                size            *= 2
                block[size - 1] = 1
                operations      += 1
                if latency do
                    latency.record(Time.monotonicTicks() - start)
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
        return spreadBody()

    case .SpreadRep:
        var operations = 0'u64
        for SpreadRepRounds do
            operations += spreadBody()
        return operations
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

// Workers of a gated workload arrive here before the phase clock starts, and leave together.
struct Gate
{
    arrived: u64
    open:    u64
}

struct Job
{
    workload:   Workload
    seed:       u64
    operations: u64
    bodyTicks:  u64
    ring:       *Ring?
    gate:       *Gate?
    latency:    *Latency?
    producer:   bool
}

func produce(ring: *Ring, seed: u64)
{
    var random = Xorshift{seed}
    for XferCount
    {
        let block = cast([*] u8, Memory.alloc(random.smallSize()))
        block[0] = 1
        while Swag.atomicLoad(&ring.head) - Swag.atomicLoad(&ring.tail) >= XferRing {}
        ring.slots[ring.head % XferRing] = cast(u64, block)
        discard Swag.atomicExchange(&ring.head, ring.head + 1)
    }
}

// The consumer does not know the sizes, which the runtime allocator does not need. With a
// recorder, every batch of its remote frees is timed, waiting for the producer excluded.
func consume(ring: *Ring, latency: *Latency?)
{
    if latency do
        latency.unit = LatencyBatch
    var spent = 0'u64
    for n in XferCount
    {
        while Swag.atomicLoad(&ring.head) == ring.tail {}
        let start = latency ? Time.monotonicTicks() : 0
        Memory.free(cast([*] void, ring.slots[ring.tail % XferRing]), 0)
        discard Swag.atomicExchange(&ring.tail, ring.tail + 1)
        if latency
        {
            spent += Time.monotonicTicks() - start
            if (n + 1) % LatencyBatch == 0
            {
                latency.record(spent)
                spent = 0
            }
        }
    }
}

// The body of one worker: waits at the gate when the workload has one, then times its own work.
func work(job: *Job)
{
    if job.gate
    {
        discard Swag.atomicAdd(&job.gate.arrived, 1)
        while Swag.atomicLoad(&job.gate.open) == 0 {}
    }

    let start = Time.monotonicTicks()
    if job.workload != .Xfer
    {
        job.operations = run(job.workload, job.seed, job.latency)
    }
    elif job.producer
    {
        produce(job.ring!, job.seed)
    }
    else
    {
        consume(job.ring!, job.latency)
        job.operations = XferCount
    }

    job.bodyTicks = Time.monotonicTicks() - start
}

func parseWorkload(name: string)->Workload fail
{
    switch name
    {
    case "aligned":   return .Aligned
    case "pair":      return .Pair
    case "trees":     return .Trees
    case "churn":     return .Churn
    case "medium":    return .Medium
    case "large":     return .Large
    case "realloc":   return .Realloc
    case "spread":    return .Spread
    case "grow":      return .Grow
    case "xfer":      return .Xfer
    case "huge":      return .Huge
    case "spreadrep": return .SpreadRep
    case "retain":    return .Retain
    }

    fail Errors.BadParameterError{}
}

#main
{
    let args = Swag.args()
    var badWorkloadOutcome: Swag.Error
    var workload: #decltype(expect parseWorkload(args.count > 1 ? args[1] : ""))
    catch { workload = try parseWorkload(args.count > 1 ? args[1] : "") } as &badWorkloadOutcome
    let badWorkload = badWorkloadOutcome.value()
    let threads     = args.count > 2 ? (catch StrConv.toU32(args[2]) else 0) : 1
    let latency     = args.count > 3 and args[3] == "latency"
    if badWorkload != null or threads < 1 or threads > 16
    {
        Console.println("usage: allocbench <pair|trees|churn|medium|large|realloc|spread|grow|xfer|aligned|huge|spreadrep|retain> [threads 1-16] [latency]")
        return
    }

    if workload == .Retain
    {
        var random = Xorshift{1000}
        let kept   = retain(&random)
        Console.print("allocbench workload=retain threads=1 operations=1 ns/op=0 retained_idle=", kept.idle, " retained_purged=", kept.purged, " retained_trimmed=", kept.trimmed)
        printOsCalls()
        Console.println()
        return
    }

    var jobs:     [32] Job
    var rings:    [16] Ring
    var pool:     [32] Threading.Thread
    var gate:     Gate
    var recorder: Latency
    if latency do
        recorder.samples = cast([*] u32, Memory.alloc(LatencyMaxSamples * #sizeof(u32)))
    let count = workload == .Xfer ? threads * 2 : threads
    let gated = workload == .SpreadRep

    var watch: Time.Stopwatch
    watch.start()
    for i in count
    {
        jobs[i].workload = workload
        jobs[i].seed     = 1000 + i * 7919
        jobs[i].ring     = workload == .Xfer ? &rings[i / 2] : null
        jobs[i].gate     = gated ? &gate : null
        jobs[i].latency  = latency and i == (workload == .Xfer ? 1 : 0) ? &recorder : null
        jobs[i].producer = i % 2 == 0
        try pool[i].init(func||(thread: const *Threading.Thread) { work(cast(*Job, thread.userParam!)) }, &jobs[i])
        try pool[i].start()
    }

    // The phase clock of a gated workload starts once every worker has arrived.
    var phaseStart = 0'u64
    if gated
    {
        while Swag.atomicLoad(&gate.arrived) < count {}
        phaseStart = Time.monotonicTicks()
        discard Swag.atomicExchange(&gate.open, 1)
    }

    var operations = 0'u64
    var slowest    = 0.0
    for i in count
    {
        pool[i].wait()
        operations += jobs[i].operations

        // A producer counts no operation of its own: the consumer counts the pair's.
        if jobs[i].operations != 0
        {
            let perOp = cast(f64, jobs[i].bodyTicks) * 1.0e9 / cast(f64, Time.monotonicFrequency()) / cast(f64, jobs[i].operations)
            slowest = Math.max(slowest, perOp)
        }
    }

    let phaseTicks = gated ? Time.monotonicTicks() - phaseStart : 0
    watch.stop()
    let ns = cast(f64, watch.elapsedMicroseconds()) * 1000.0 / cast(f64, operations)
    Console.print("allocbench workload=", args[1], " threads=", threads, " operations=", operations, " ns/op=", ns, " worker_ns/op=", slowest)
    if gated do
        Console.print(" phase_ns/op=", cast(f64, phaseTicks) * 1.0e9 / cast(f64, Time.monotonicFrequency()) / cast(f64, operations))
    if latency do
        Console.print(" p50_ns=", recorder.percentile(500), " p99_ns=", recorder.percentile(990), " per_ops=", recorder.unit)
    printOsCalls()
    Console.println()
}

// The system calls the runtime allocator made for the whole process, which the other programs
// cannot report the same way.
func printOsCalls()
{
    let stats = Swag.defaultAllocator().stats()
    Console.print(" os_reserves=", stats.countOsReserve, " os_commits=", stats.countOsCommit, " os_decommits=", stats.countOsDecommit)
}
