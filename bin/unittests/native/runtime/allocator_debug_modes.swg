#global if #hastag("Swag.AllocatorDiagnostics")
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
    Swag.memset(cast([*] void, &alloc), 0xCD, #sizeof(Allocator))

    alloc.setup()
    Swag.require(alloc.installed())
    Swag.require(alloc.firstAlloc == null)
    Swag.require(alloc.firstQuarantine == null)
    Swag.require(alloc.lastQuarantine == null)
    Swag.require(alloc.firstSegment == null)
    Swag.require(alloc.firstHeap == null)
    Swag.require(alloc.firstAbandoned == null)

    let stats = alloc.stats()
    Swag.require(stats.countAlloc == 0)
    Swag.require(stats.countFree == 0)
    Swag.require(stats.sizeAlloc == 0)
    Swag.require(stats.sizeCached == 0)
    Swag.require(stats.countPage == 0)
    Swag.require(stats.countSegment == 0)

    Swag.require(alloc.maxQuarantineBytes == 16 * 1024 * 1024)
    Swag.require(alloc.showMaxLeaks == 100)
    Swag.require(alloc.detectLeaks)
    Swag.require(not alloc.trackAllocations)
}

#test
{
    var alloc: Allocator
    let itf = makeDebugModeAllocator(&alloc)

    var req: AllocatorRequest
    req.size = 144
    req.hint = "debug-no-stack"
    itf.alloc(&req)
    Swag.require(req.address != null)
    Swag.require(alloc.stats().countAlloc == 1)
    Swag.require(alloc.firstAlloc != null)

    let header   = cast(*AllocatorHeader, (cast([*] u8, req.address) - #sizeof(AllocatorHeader)))
    let tracking = unwrap header.tracking
    Swag.require(header == alloc.firstAlloc)
    Swag.require(tracking.stackCount == 0)

    var assertReq: AllocatorRequest
    assertReq.address = req.address
    itf.assertAllocated(&assertReq)

    itf.free(&req)
    Swag.require(req.address == null)
    Swag.require(alloc.stats().countAlloc == 0)
    Swag.require(alloc.stats().countFree == 1)
    Swag.require(alloc.firstQuarantine == header)

    let freed = alloc.userAddress(header)
    for i in 144 do
        Swag.require(freed[i] == Allocator.FreeByte)

    alloc.releaseAll()
    Swag.require(alloc.stats().countFree == 0)
}

#test
{
    var alloc: Allocator
    let itf = makeDebugModeAllocator(&alloc, electricMode: true)

    var first: AllocatorRequest
    first.size = 64
    itf.alloc(&first)
    Swag.require(first.address != null)
    let firstAddress = first.address

    itf.free(&first)
    Swag.require(first.address == null)

    var second: AllocatorRequest
    second.size = 64
    itf.alloc(&second)
    Swag.require(second.address != null)
    Swag.require(second.address != firstAddress)

    var freeAll: AllocatorRequest
    itf.freeAll(&freeAll)
    Swag.require(alloc.stats().countAlloc == 0)
    Swag.require(alloc.stats().countFree == 0)
}

#test
{
    var alloc: Allocator
    let itf = makeDebugModeAllocator(&alloc, trackAllocations: true, fillMemory: false)

    var reqs: [8] AllocatorRequest
    for i in 8
    {
        reqs[i].size = 32 + cast(u64, i) * 23
        itf.alloc(&reqs[i])
        Swag.require(reqs[i].address != null)
    }

    Swag.require(alloc.stats().countAlloc == 8)
    Swag.require(alloc.firstAlloc != null)
    alloc.checkAllMemory()

    for i in 8
    {
        itf.free(&reqs[i])
        Swag.require(reqs[i].address == null)
    }

    Swag.require(alloc.stats().countAlloc == 0)
    Swag.require(alloc.stats().countFree == 8)
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
    Swag.require(req.address != null)

    let ptr = cast([*] u8, req.address)
    for i in 96 do
        Swag.require(ptr[i] == Allocator.AllocByte)

    itf.free(&req)
    Swag.require(req.address == null)
    alloc.releaseAll()
}

#test
{
    var alloc: Allocator
    let itf = makeDebugModeAllocator(&alloc, trackAllocations: false, fillMemory: true)

    var untracked: AllocatorRequest
    untracked.size = 80
    itf.alloc(&untracked)
    Swag.require(untracked.address != null)
    Swag.require(alloc.stats().countAlloc == 1)
    Swag.require(alloc.firstAlloc == null)

    alloc.configure(false, true, false, true, true)

    var tracked: AllocatorRequest
    tracked.size = 96
    itf.alloc(&tracked)
    Swag.require(tracked.address != null)

    let trackedHeader = cast(*AllocatorHeader, (cast([*] u8, tracked.address) - #sizeof(AllocatorHeader)))
    Swag.require(alloc.firstAlloc == trackedHeader)
    alloc.checkAllMemory()

    itf.free(&untracked)
    Swag.require(untracked.address == null)
    Swag.require(alloc.firstAlloc == trackedHeader)
    alloc.checkAllMemory()

    itf.free(&tracked)
    Swag.require(tracked.address == null)
    Swag.require(alloc.firstAlloc == null)

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
        Swag.require(req.address != null)

        // A diagnostic block is its own operating-system region, which is what lets its tracking
        // record sit in front of it and its bounds be checked exactly.
        let header = cast(*AllocatorHeader, (cast([*] u8, req.address) - #sizeof(AllocatorHeader)))
        Swag.require(header.allocAddr != null)
        Swag.require(header.allocSize % 4096 == 0)
        Swag.require(cast(u64, header.allocAddr) % 4096 == 0)
        Swag.require(header.tracking == cast(*AllocatorTracking, header.allocAddr))
        Swag.require(allocatorPageOf(cast(u64, req.address)) == null)

        itf.free(&req)
        Swag.require(req.address == null)

        var freeAll: AllocatorRequest
        itf.freeAll(&freeAll)
        Swag.require(alloc.stats().countAlloc == 0)
        Swag.require(alloc.stats().countFree == 0)
    }
}
