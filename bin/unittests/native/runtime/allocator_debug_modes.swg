#global private

using Swag

func makeDebugModeAllocator(alloc: *Allocator, electricMode: bool = false, trackAllocations: bool = true, fillMemory: bool = true)->IAllocator
{
    alloc.setup()
    alloc.configure(electricMode, true, false, trackAllocations, fillMemory)
    return @mkinterface(alloc, #typeof(alloc[]), IAllocator)
}

#test
{
    var alloc: Allocator
    @memset(cast([*] void) &alloc, 0xCD, #sizeof(Allocator))

    alloc.setup()
    @assert(alloc.installed())
    @assert(alloc.firstAlloc == null)
    @assert(alloc.firstQuarantine == null)
    @assert(alloc.lastQuarantine == null)
    @assert(alloc.firstSegment == null)
    @assert(alloc.firstHeap == null)
    @assert(alloc.firstAbandoned == null)

    let stats = alloc.stats()
    @assert(stats.countAlloc == 0)
    @assert(stats.countFree == 0)
    @assert(stats.sizeAlloc == 0)
    @assert(stats.sizeCached == 0)
    @assert(stats.countPage == 0)
    @assert(stats.countSegment == 0)

    @assert(alloc.maxQuarantineBytes == 16 * 1024 * 1024)
    @assert(alloc.showMaxLeaks == 100)
    @assert(alloc.detectLeaks)
    @assert(!alloc.trackAllocations)
}

#test
{
    var alloc: Allocator
    let itf = makeDebugModeAllocator(&alloc)

    var req: AllocatorRequest
    req.size = 144
    req.hint = "debug-no-stack"
    itf.alloc(&req)
    @assert(req.address != null)
    @assert(alloc.stats().countAlloc == 1)
    @assert(alloc.firstAlloc != null)

    let header   = cast(*AllocatorHeader) (cast([*] u8) req.address! - #sizeof(AllocatorHeader))
    let tracking = header.tracking!
    @assert(header == alloc.firstAlloc)
    @assert(tracking.stackCount == 0)

    var assertReq: AllocatorRequest
    assertReq.address = req.address
    itf.assertAllocated(&assertReq)

    itf.free(&req)
    @assert(req.address == null)
    @assert(alloc.stats().countAlloc == 0)
    @assert(alloc.stats().countFree == 1)
    @assert(alloc.firstQuarantine == header)

    let freed = alloc.userAddress(header)
    for i in 144 do
        @assert(freed[i] == Allocator.FreeByte)

    alloc.releaseAll()
    @assert(alloc.stats().countFree == 0)
}

#test
{
    var alloc: Allocator
    let itf = makeDebugModeAllocator(&alloc, electricMode: true)

    var first: AllocatorRequest
    first.size = 64
    itf.alloc(&first)
    @assert(first.address != null)
    let firstAddress = first.address

    itf.free(&first)
    @assert(first.address == null)

    var second: AllocatorRequest
    second.size = 64
    itf.alloc(&second)
    @assert(second.address != null)
    @assert(second.address != firstAddress)

    var freeAll: AllocatorRequest
    itf.freeAll(&freeAll)
    @assert(alloc.stats().countAlloc == 0)
    @assert(alloc.stats().countFree == 0)
}

#test
{
    var alloc: Allocator
    let itf = makeDebugModeAllocator(&alloc, trackAllocations: true, fillMemory: false)

    var reqs: [8] AllocatorRequest
    for i in 8
    {
        reqs[i].size = 32 + cast(u64) i * 23
        itf.alloc(&reqs[i])
        @assert(reqs[i].address != null)
    }

    @assert(alloc.stats().countAlloc == 8)
    @assert(alloc.firstAlloc != null)
    alloc.checkAllMemory()

    for i in 8
    {
        itf.free(&reqs[i])
        @assert(reqs[i].address == null)
    }

    @assert(alloc.stats().countAlloc == 0)
    @assert(alloc.stats().countFree == 8)
    alloc.checkAllMemory()
    alloc.releaseAll()
}

#test
{
    var alloc: Allocator
    let itf = makeDebugModeAllocator(&alloc, trackAllocations: false, fillMemory: true)

    var req: AllocatorRequest
    req.size = 96
    itf.alloc(&req)
    @assert(req.address != null)

    let ptr = cast([*] u8) req.address!
    for i in 96 do
        @assert(ptr[i] == Allocator.AllocByte)

    itf.free(&req)
    @assert(req.address == null)
    alloc.releaseAll()
}

#test
{
    var alloc: Allocator
    let itf = makeDebugModeAllocator(&alloc, trackAllocations: false, fillMemory: true)

    var untracked: AllocatorRequest
    untracked.size = 80
    itf.alloc(&untracked)
    @assert(untracked.address != null)
    @assert(alloc.stats().countAlloc == 1)
    @assert(alloc.firstAlloc == null)

    alloc.configure(false, true, false, true, true)

    var tracked: AllocatorRequest
    tracked.size = 96
    itf.alloc(&tracked)
    @assert(tracked.address != null)

    let trackedHeader = cast(*AllocatorHeader) (cast([*] u8) tracked.address! - #sizeof(AllocatorHeader))
    @assert(alloc.firstAlloc == trackedHeader)
    alloc.checkAllMemory()

    itf.free(&untracked)
    @assert(untracked.address == null)
    @assert(alloc.firstAlloc == trackedHeader)
    alloc.checkAllMemory()

    itf.free(&tracked)
    @assert(tracked.address == null)
    @assert(alloc.firstAlloc == null)

    alloc.releaseAll()
}

#static if #os == Swag.TargetOs.Windows
{
    #test
    {
        var alloc: Allocator
        let itf = makeDebugModeAllocator(&alloc, trackAllocations: true, fillMemory: false)

        var req: AllocatorRequest
        req.size = 512
        itf.alloc(&req)
        @assert(req.address != null)

        // A diagnostic block is its own operating-system region, which is what lets its tracking
        // record sit in front of it and its bounds be checked exactly.
        let header = cast(*AllocatorHeader) (cast([*] u8) req.address! - #sizeof(AllocatorHeader))
        @assert(header.allocAddr != null)
        @assert(header.allocSize % 4096 == 0)
        @assert(cast(u64) header.allocAddr % 4096 == 0)
        @assert(header.tracking == cast(*AllocatorTracking) header.allocAddr)
        @assert(allocatorPageOf(cast(u64) req.address!) == null)

        itf.free(&req)
        @assert(req.address == null)

        var freeAll: AllocatorRequest
        itf.freeAll(&freeAll)
        @assert(alloc.stats().countAlloc == 0)
        @assert(alloc.stats().countFree == 0)
    }
}
