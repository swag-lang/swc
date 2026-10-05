#global if #command == Swag.CompilerCommand.Test
#global private

using Swag

struct PageCommitShared
{
    allocator: IAllocator
    ready:     u32
    start:     u32
    done:      u32
    errors:    u32
}

func pageCommitWorker(thread: Threading.Thread)
{
    let shared = cast(*PageCommitShared) thread.userParam!
    discard Swag.atomadd(&shared.ready, 1)
    while Swag.atomget(&shared.start) == 0 do
        Threading.Thread.yield()

    for round in 48
    {
        let sizes = [128'u64, 4096, 32768, 65536]
        let size  = sizes[round % sizes.count]
        var addresses: [48] u64
        for i in addresses.count
        {
            var request: AllocatorRequest
            request.size = size
            shared.allocator.alloc(&request)
            Swag.assert(request.address != null)
            let bytes = cast([*] u8) request.address
            bytes[0]        = cast(u8) i
            bytes[size - 1] = cast(u8) round
            addresses[i]    = cast(u64) request.address
        }

        Threading.Thread.yield()
        for i in addresses.count
        {
            let bytes = cast([*] u8) addresses[i]
            if bytes[0] != cast(u8) i or bytes[size - 1] != cast(u8) round do
                discard Swag.atomadd(&shared.errors, 1)
            var request: AllocatorRequest
            request.address = cast(*void) addresses[i]
            shared.allocator.free(&request)
        }

        Swag.releaseAllocatorThreadCache()
    }

    discard Swag.atomadd(&shared.done, 1)
}

// Concurrent trim and statistics must not see a partially initialized page or release a segment being committed.
#test
{
    var allocator: Allocator
    allocator.setup()
    defer allocator.releaseAll()
    var shared = PageCommitShared{allocator: &allocator}
    var threads: [4] Threading.Thread
    for &thread in threads
    {
        discard expect thread.init(&pageCommitWorker, &shared)
        discard expect thread.start()
    }

    while Swag.atomget(&shared.ready) != threads.count do
        Threading.Thread.yield()
    discard Swag.atomxchg(&shared.start, 1)

    while Swag.atomget(&shared.done) != threads.count
    {
        allocator.trim()
        discard allocator.stats()
        Threading.Thread.yield()
    }

    for &thread in threads do
        thread.wait()

    allocator.trim()
    let stats = allocator.stats()
    Swag.assert(shared.errors == 0)
    Swag.assert(stats.countAlloc == 0)
    Swag.assert(stats.countPage == 0)
    Swag.assert(stats.countSegment == 0)
}
