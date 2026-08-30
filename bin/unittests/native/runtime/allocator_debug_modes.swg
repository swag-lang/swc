#global private

using Swag

func makeDebugModeAllocator(alloc: *Allocator, electricMode: bool = false, trackAllocations: bool = true, fillMemory: bool = true)->IAllocator
{
    alloc.setup()
    alloc.configure(electricMode, true, false, trackAllocations, fillMemory)
    return Swag.makeInterface(alloc, #typeof(alloc[]), IAllocator)
}

#test
{
    var alloc: Allocator
    Swag.memset(cast([*] void) &alloc, 0xCD, #sizeof(Allocator))

    alloc.setup()
    Swag.assert(alloc.installed())
    Swag.assert(alloc.firstAlloc == null)
    Swag.assert(alloc.firstQuarantine == null)
    Swag.assert(alloc.lastQuarantine == null)
    Swag.assert(alloc.firstSegment == null)
    Swag.assert(alloc.firstHeap == null)
    Swag.assert(alloc.firstAbandoned == null)

    let stats = alloc.stats()
    Swag.assert(stats.countAlloc == 0)
    Swag.assert(stats.countFree == 0)
    Swag.assert(stats.sizeAlloc == 0)
    Swag.assert(stats.sizeCached == 0)
    Swag.assert(stats.countPage == 0)
    Swag.assert(stats.countSegment == 0)

    Swag.assert(alloc.maxQuarantineBytes == 16 * 1024 * 1024)
    Swag.assert(alloc.showMaxLeaks == 100)
    Swag.assert(alloc.detectLeaks)
    Swag.assert(!alloc.trackAllocations)
}

#test
{
    var alloc: Allocator
    let itf = makeDebugModeAllocator(&alloc)

    var req: AllocatorRequest
    req.size = 144
    req.hint = "debug-no-stack"
    itf.alloc(&req)
    Swag.assert(req.address != null)
    Swag.assert(alloc.stats().countAlloc == 1)
    Swag.assert(alloc.firstAlloc != null)

    let header   = cast(*AllocatorHeader) (cast([*] u8) req.address! - #sizeof(AllocatorHeader))
    let tracking = header.tracking!
    Swag.assert(header == alloc.firstAlloc)
    Swag.assert(tracking.stackCount == 0)

    var assertReq: AllocatorRequest
    assertReq.address = req.address
    itf.assertAllocated(&assertReq)

    itf.free(&req)
    Swag.assert(req.address == null)
    Swag.assert(alloc.stats().countAlloc == 0)
    Swag.assert(alloc.stats().countFree == 1)
    Swag.assert(alloc.firstQuarantine == header)

    let freed = alloc.userAddress(header)
    for i in 144 do
        Swag.assert(freed[i] == Allocator.FreeByte)

    alloc.releaseAll()
    Swag.assert(alloc.stats().countFree == 0)
}

#test
{
    var alloc: Allocator
    let itf = makeDebugModeAllocator(&alloc, electricMode: true)

    var first: AllocatorRequest
    first.size = 64
    itf.alloc(&first)
    Swag.assert(first.address != null)
    let firstAddress = first.address

    itf.free(&first)
    Swag.assert(first.address == null)

    var second: AllocatorRequest
    second.size = 64
    itf.alloc(&second)
    Swag.assert(second.address != null)
    Swag.assert(second.address != firstAddress)

    var freeAll: AllocatorRequest
    itf.freeAll(&freeAll)
    Swag.assert(alloc.stats().countAlloc == 0)
    Swag.assert(alloc.stats().countFree == 0)
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
        Swag.assert(reqs[i].address != null)
    }

    Swag.assert(alloc.stats().countAlloc == 8)
    Swag.assert(alloc.firstAlloc != null)
    alloc.checkAllMemory()

    for i in 8
    {
        itf.free(&reqs[i])
        Swag.assert(reqs[i].address == null)
    }

    Swag.assert(alloc.stats().countAlloc == 0)
    Swag.assert(alloc.stats().countFree == 8)
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
    Swag.assert(req.address != null)

    let ptr = cast([*] u8) req.address!
    for i in 96 do
        Swag.assert(ptr[i] == Allocator.AllocByte)

    itf.free(&req)
    Swag.assert(req.address == null)
    alloc.releaseAll()
}

#test
{
    var alloc: Allocator
    let itf = makeDebugModeAllocator(&alloc, trackAllocations: false, fillMemory: true)

    var untracked: AllocatorRequest
    untracked.size = 80
    itf.alloc(&untracked)
    Swag.assert(untracked.address != null)
    Swag.assert(alloc.stats().countAlloc == 1)
    Swag.assert(alloc.firstAlloc == null)

    alloc.configure(false, true, false, true, true)

    var tracked: AllocatorRequest
    tracked.size = 96
    itf.alloc(&tracked)
    Swag.assert(tracked.address != null)

    let trackedHeader = cast(*AllocatorHeader) (cast([*] u8) tracked.address! - #sizeof(AllocatorHeader))
    Swag.assert(alloc.firstAlloc == trackedHeader)
    alloc.checkAllMemory()

    itf.free(&untracked)
    Swag.assert(untracked.address == null)
    Swag.assert(alloc.firstAlloc == trackedHeader)
    alloc.checkAllMemory()

    itf.free(&tracked)
    Swag.assert(tracked.address == null)
    Swag.assert(alloc.firstAlloc == null)

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
        Swag.assert(req.address != null)

        // A diagnostic block is its own operating-system region, which is what lets its tracking
        // record sit in front of it and its bounds be checked exactly.
        let header = cast(*AllocatorHeader) (cast([*] u8) req.address! - #sizeof(AllocatorHeader))
        Swag.assert(header.allocAddr != null)
        Swag.assert(header.allocSize % 4096 == 0)
        Swag.assert(cast(u64) header.allocAddr % 4096 == 0)
        Swag.assert(header.tracking == cast(*AllocatorTracking) header.allocAddr)
        Swag.assert(allocatorPageOf(cast(u64) req.address!) == null)

        itf.free(&req)
        Swag.assert(req.address == null)

        var freeAll: AllocatorRequest
        itf.freeAll(&freeAll)
        Swag.assert(alloc.stats().countAlloc == 0)
        Swag.assert(alloc.stats().countFree == 0)
    }
}
