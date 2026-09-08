// Scheduler cost against worker count.
//
// Four workloads answer four separate questions about the scheduler in `bin/runtime`: what one
// submission costs when the work is small (fork/join), what concurrent submission costs when
// every worker publishes at once (spawn), what a task group's own storage costs beside that
// (spawn-task), and what one completion costs while other threads are parked on their own work
// (herd).
//
// Every case runs at ascending worker counts, because the pool only grows: asking for fewer
// workers never stops a running one. Absolute microseconds are not comparable between two runs on
// a shared or hybrid machine, so every case carries a control measured in the same process --
// the one-worker step for the two submission cases, and the unobserved stream for the herd.

using Core

const Elements     = 1'u64 << 20
const Samples      = 5'u32
const StreamLength = 20_000'u64
const MaxOccupancy = 64'u64
const PerPartition = 512'u64

// Cut-offs sweep the grain of one fork/join leaf. The crossover between them is the size below
// which submitting a task costs more than running its work on the spot.
const Cutoffs: [6] u64 = [64, 256, 1024, 4096, 16384, 65536]

// Worker counts, ascending. The last step asks for more than any host provides, so the pool grows
// to whatever the machine allows and the run reports what it actually got.
const WorkerSteps: [5] u32 = [1, 2, 4, 8, 1024]

// Sorts the samples in place and returns the middle one. A median resists the single slow sample
// a background process or a core migration produces.
func median(samples: [..] u64)->u64
{
    for index in 1 until samples.count
    {
        let value = samples[index]
        var slot  = index
        while slot > 0 and samples[slot - 1] > value
        {
            samples[slot] = samples[slot - 1]
            slot          -= 1
        }

        samples[slot] = value
    }

    return samples[samples.count / 2]
}

func report(name: string, workers: u32, detail: string, value: u64, samples: [..] u64)
{
    Console.println(name, " workers=", workers, " ", detail, "=", value, " median-us=", median(samples))
}

// One leaf of the fork/join tree. The multiplication keeps the loop from folding away and makes
// one iteration cost a few nanoseconds, so the grain sweep spans the interesting range.
func leafSum(values: const [..] u64, begin, end: u64)->u64
{
    var total = 0'u64
    for index in begin until end do
        total += values[index] * 2654435761 + index
    return total
}

// Splits the range until a leaf is at most `cutoff` long, running one half here and submitting the
// other. This is the shape a work-stealing pool is built for: every node joins only its own
// descendant, and the caller has useful work while that descendant runs.
func forkJoinSum(values: const [..] u64, begin, end, cutoff: u64)->u64
{
    if end - begin <= cutoff do
        return leafSum(values, begin, end)

    let middle = begin + (end - begin) / 2
    var right  = 0'u64
    var task: Swag.Task

    task.submit(func|values, middle, end, cutoff, &right|()
    {
        right = forkJoinSum(values, middle, end, cutoff)
    })

    let left = forkJoinSum(values, begin, middle, cutoff)
    task.wait()
    return left + right
}

func measureForkJoin(values: const [..] u64, expected: u64)
{
    let workers = Swag.workerCount()
    for cutoff in Cutoffs
    {
        var samples: [Samples] u64
        for sample in Samples
        {
            var watch: Time.Stopwatch
            watch.start()
            let total = forkJoinSum(values, 0, values.count, cutoff)
            watch.stop()

            Swag.assert(total == expected, "fork/join result must match the sequential sum")
            samples[sample] = watch.elapsedMicroseconds()
        }

        report("forkjoin", workers, "cutoff", cutoff, samples)
    }
}

// Every partition publishes `PerPartition` children at once, so the shared ready stack takes
// submissions from every worker simultaneously. Each child writes one slot nothing else touches.
func spawnWithGroup(values: [..] u64, partitions: u64)
{
    parallel for |values| partition in partitions
    {
        var group: Swag.TaskGroup
        for child in PerPartition
        {
            let slot = partition * PerPartition + child
            group.spawn(func|values, slot|()
            {
                values[slot] = slot * 2654435761 + 1
            })
        }
    }
}

// The same submissions through plain tasks the partition owns itself. A group differs from this
// only by the storage it keeps for its children, so the pair prices that storage in one process.
func spawnWithTasks(values: [..] u64, partitions: u64)
{
    parallel for |values| partition in partitions
    {
        var tasks: [PerPartition] Swag.Task
        for child in PerPartition
        {
            let slot = partition * PerPartition + child
            tasks[child].submit(func|values, slot|()
            {
                values[slot] = slot * 2654435761 + 1
            })
        }

        for child in PerPartition do
            tasks[child].wait()
    }
}

func measureSpawn(name: string, values: [..] u64, grouped: bool)
{
    let workers    = Swag.workerCount()
    let partitions = cast(u64) (workers < 1 ? 1'u32 : workers)

    var samples: [Samples] u64
    for sample in Samples
    {
        Memory.clear(values.buffer, values.count * #sizeof(u64))

        var watch: Time.Stopwatch
        watch.start()
        if grouped do
            spawnWithGroup(values, partitions)
        else do
            spawnWithTasks(values, partitions)
        watch.stop()

        for slot in partitions * PerPartition do
            Swag.assert(values[slot] == slot * 2654435761 + 1, "every spawned child must have written its slot")
        samples[sample] = watch.elapsedMicroseconds()
    }

    report(name, workers, "children", partitions * PerPartition, samples)
}

// One iteration of the nesting pair, sized to a few tens of microseconds so a partitioning is
// worth making at both levels.
func stirred(slot, rounds: u64)->u64
{
    var value = slot
    for round in rounds do
        value = value * 6364136223846793005 + 1442695040888963407
    return value
}

// The same total work as one flat range, expressed as a parallel region inside a parallel region.
// The pair says what nesting costs, because an inner region asks the pool for the same width its
// caller already took.
func nestedWork(values: [..] u64, outer, inner, rounds: u64)
{
    parallel for |values, inner, rounds| first in outer
    {
        parallel for |values, inner, rounds, first| second in inner do
            values[first * inner + second] = stirred(first * inner + second, rounds)
    }
}

func flatWork(values: [..] u64, outer, inner, rounds: u64)
{
    parallel for |values, rounds| slot in outer * inner do
        values[slot] = stirred(slot, rounds)
}

func measureNesting(name: string, values: [..] u64, nested: bool)
{
    let workers = Swag.workerCount()
    let outer   = cast(u64) (workers < 1 ? 1'u32 : workers)
    let inner   = 8'u64
    let rounds  = 20_000'u64

    var samples: [Samples] u64
    for sample in Samples
    {
        Memory.clear(values.buffer, values.count * #sizeof(u64))

        var watch: Time.Stopwatch
        watch.start()
        if nested do
            nestedWork(values, outer, inner, rounds)
        else do
            flatWork(values, outer, inner, rounds)
        watch.stop()

        for slot in outer * inner do
            Swag.assert(values[slot] == stirred(slot, rounds), "both shapes must produce the same values")
        samples[sample] = watch.elapsedMicroseconds()
    }

    report(name, workers, "iterations", outer * inner, samples)
}

// One parked observer, waiting on a task of its own.
struct ObserverPayload
{
    late task: *Swag.Task
}

func observerEntry(th: Threading.Thread)
{
    let payload = cast(*ObserverPayload) th.userParam!
    payload.task.wait()
}

// Submits and joins `count` tiny tasks one after another, on the calling thread. Every worker is
// busy for the whole call, so the caller claims each queued node itself and the measurement is a
// straight count of submit, run, and publish-completion cycles.
func streamShortTasks(count: u64)->u64
{
    var total = 0'u64
    var task: Swag.Task

    for index in count
    {
        task.submit(func|&total, index|()
        {
            total += index
        })

        task.wait()
    }

    return total
}

// Occupies every worker with a task that waits for `stop`, optionally parks one thread per
// occupied worker on those tasks, then times a stream of short tasks on the calling thread.
//
// The two variants differ only in whether observers are registered, which is what makes the pair
// a price for the completion path alone: a finished unit that finds a registered observer has to
// decide whether that observer was waiting for it.
func measureHerd(observed: bool)
{
    let workers  = Swag.workerCount()
    var occupied = cast(u64) workers
    if occupied > MaxOccupancy do
        occupied = MaxOccupancy
    if occupied == 0 do
        occupied = 1

    var stop:     Swag.AtomicFlag
    var running:  Swag.AtomicValue'u32
    var sleepers: [MaxOccupancy] Swag.Task
    var payloads: [MaxOccupancy] ObserverPayload
    var threads:  [MaxOccupancy] Threading.Thread

    for index in occupied
    {
        sleepers[index].submit(func|&stop, &running|()
        {
            discard running.add(1)
            while !stop.isRaised() do
                Threading.Thread.sleep(1'ms)
        })
    }

    // Every sleeper must be running before an observer joins it, otherwise the observer claims the
    // queued node and runs the sleep itself instead of parking.
    while running.load() != cast(u32) occupied do
        Threading.Thread.sleep(1'ms)

    if observed
    {
        for index in occupied
        {
            payloads[index].task = &sleepers[index]
            discard expect threads[index].init(&observerEntry, &payloads[index])
            discard expect threads[index].start()
        }

        // Give every observer time to exhaust its spin and park on the scheduler condition.
        Threading.Thread.sleep(50'ms)
    }

    var samples: [Samples] u64
    for sample in Samples
    {
        var watch: Time.Stopwatch
        watch.start()
        let total = streamShortTasks(StreamLength)
        watch.stop()

        Swag.assert(total == StreamLength * (StreamLength - 1) / 2, "every short task must have run once")
        samples[sample] = watch.elapsedMicroseconds()
    }

    report("herd", workers, "observers", observed ? occupied : 0, samples)

    discard stop.raise()

    if observed
    {
        for index in occupied do
            threads[index].wait()
    }

    for index in occupied do
        sleepers[index].wait()
}

#main
{
    var values: Array'u64
    values.reserve(Elements)
    for index in Elements do
        values.add(index * 31 + 7)

    let slice    = values.toSlice()
    let expected = leafSum(slice, 0, Elements)

    for step in WorkerSteps
    {
        Swag.setWorkerCount(step)
        Swag.startWorkers()
        Console.println("--- requested=", step, " actual=", Swag.workerCount())

        measureForkJoin(slice, expected)
        measureSpawn("spawn-group", values.toSlice(), true)
        measureSpawn("spawn-task", values.toSlice(), false)
        measureNesting("flat", values.toSlice(), false)
        measureNesting("nested", values.toSlice(), true)
        measureHerd(false)
        measureHerd(true)
    }
}
