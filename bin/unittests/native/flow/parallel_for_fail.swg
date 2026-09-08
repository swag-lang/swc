#global private

struct LoopFailure
{
    index: u64
    data:  [32] u64
}

var copiedErrorDrops: [16] Swag.AtomicValue'u32

struct CopiedLoopFailure
{
    generation: u32
}

impl CopiedLoopFailure
{
    mtd opPostCopy() { .generation += 1 }
    mtd opDrop() { copiedErrorDrops[.generation].add(1) }
}

func failCopied() fail
{
    fail CopiedLoopFailure{}
}

// Error transport owns a copy and releases it after re-raising on the caller.
#test
{
    catch failCopied() as serialError
    Swag.assert(serialError != null and serialError is CopiedLoopFailure)
    let serialGeneration = (cast(const *CopiedLoopFailure) serialError).generation
    for &drops in copiedErrorDrops do
        drops.store(0)

    catch parallel for || index in 1
    {
        try failCopied()
    } as error
    Swag.assert(error != null and error is CopiedLoopFailure)
    let generation = (cast(const *CopiedLoopFailure) error).generation
    Swag.assert(generation == serialGeneration + 2)
    Swag.assert(copiedErrorDrops[serialGeneration + 1].load() == 1)
}

func failAt(index: u64) fail
{
    var error: LoopFailure
    error.index = index
    for slot in 32 do
        error.data[slot] = index * 100 + slot
    fail error
}

func fillFallible(values: [..] u64, fault: u64, unwound: *Swag.AtomicValue'u32) fail
{
    defer #fail unwound.add(1)
    try parallel for |values, fault| index in values.count
    {
        if index == fault do
            try failAt(index)
        values[index] += index + 1
    }
}

// Success, empty input and a failure all use the same body and borrowed destination.
#test
{
    var values:  [257] u64
    var unwound: Swag.AtomicValue'u32
    expect fillFallible(values, Swag.U64.Max, &unwound)
    for index in 257 do
        Swag.assert(values[index] == index + 1)
    Swag.assert(unwound.load() == 0)

    catch fillFallible(values, 128, &unwound) as error
    Swag.assert(error != null and error is LoopFailure)
    let detail = cast(const *LoopFailure) error
    Swag.assert(detail.index == 128)
    for slot in 32 do
        Swag.assert(detail.data[slot] == 12800 + slot)
    Swag.assert(unwound.load() == 1)
    Swag.assert(values[128] == 129)

    catch parallel for || index in 0
    {
        try failAt(index)
    } as emptyError
    Swag.assert(emptyError == null)
}

// Every active body has left before the error escapes, including its failure defers.
#test
{
    Swag.setWorkerCount(4)
    var active:   Swag.AtomicValue'u32
    var finished: Swag.AtomicValue'u32
    catch parallel for |&active, &finished| index in 1024
    {
        active.add(1)
        defer active.sub(1)
        defer #fail finished.add(1)
        try failAt(index)
    } as error
    Swag.assert(error != null and error is LoopFailure)
    Swag.assert(active.load() == 0 and finished.load() > 0)
    let detail = cast(const *LoopFailure) error
    Swag.assert(detail.index < 1024)
    for slot in 32 do
        Swag.assert(detail.data[slot] == detail.index * 100 + slot)
}

// Catch handlers run once on the caller, and handled failures do not poison a later loop.
#test
{
    var handled = 0'u32
    catch parallel for || index in 1 do
        try failAt(index)
    else do
        handled += 1
    Swag.assert(handled == 1)

    var values: [17] u64
    expect parallel for |&values| index in 17 do
        values[index] = index + 1
    for index in 17 do
        Swag.assert(values[index] == index + 1)
}

// Nested failures cross two joins; both loops retain their captured frames through cleanup.
#test
{
    var active: Swag.AtomicValue'u32
    catch parallel for |&active| row in 8
    {
        active.add(1)
        defer active.sub(1)
        try parallel for |row| column in 8
        {
            if column == 3 do
                try failAt(row * 8 + column)
        }
    } as error
    Swag.assert(active.load() == 0)
    Swag.assert(error != null and error is LoopFailure)
    let detail = cast(const *LoopFailure) error
    Swag.assert(detail.index < 64 and detail.index % 8 == 3)
}

// Concurrent callers share a body profile, but never an error owner or captured destination.
#test
{
    var results: [8] u64
    {
        var group: Swag.TaskGroup
        for row in 8
        {
            group.spawn(func|&results, row|()
            {
                catch parallel for |row| index in 257
                {
                    if index == 128 do
                        try failAt(row * 1000 + index)
                } as error
                if error != null and error is LoopFailure do
                    results[row] = (cast(const *LoopFailure) error).index
            })
        }
    }
    for row in 8 do
        Swag.assert(results[row] == row * 1000 + 128)
}
