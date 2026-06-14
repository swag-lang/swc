#global fileprivate

using Swag

func makeDebugModeAllocator(alloc: *Allocator, electricMode: bool = false, trackAllocations: bool = true, fillMemory: bool = true)->IAllocator
{
    alloc.setup()
    alloc.configure(electricMode, true, false, trackAllocations, fillMemory)
    return @mkinterface(alloc, #typeof(dref alloc), IAllocator)
}

#test
{
    var alloc: Allocator
    @memset(cast([*] void) &alloc, 0xCD, #sizeof(Allocator))

    alloc.setup()
    @assert(alloc.installed())
    @assert(alloc.firstAlloc == null)
    @assert(alloc.firstFree == null)
    @assert(alloc.lastFree == null)
    @assert(alloc.firstRetiredHeap == null)
    @assert(alloc.countAlloc == 0)
    @assert(alloc.countFree == 0)
    @assert(alloc.countOsAlloc == 0)
    @assert(alloc.countOsFree == 0)
    @assert(alloc.sizeAlloc == 0)
    @assert(alloc.sizeFree == 0)
    @assert(alloc.sizeOsAlloc == 0)
    @assert(alloc.sizeOsFree == 0)
    @assert(alloc.maxCachedSize == 64 * 1024)
    @assert(alloc.maxCachedBytes == 8 * 1024 * 1024)
    @assert(alloc.maxFreeSize == 16 * 1024 * 1024)
    @assert(alloc.showMaxLeaks == 100)
    @assert(alloc.detectLeaks)
    @assert(!alloc.trackAllocations)
}

#test
{
    var alloc: Allocator
    let itf = makeDebugModeAllocator(&alloc)

    var req: AllocatorRequest
    req.mode = .Alloc
    req.size = 144
    req.hint = "debug-no-stack"
    itf.req(&req)
    @assert(req.address != null)
    @assert(alloc.countAlloc == 1)
    @assert(alloc.firstAlloc != null)

    let header = cast(*AllocatorHeader) (cast([*] u8) req.address - #sizeof(AllocatorHeader))
    @assert(header == alloc.firstAlloc)
    @assert(header.stackCount == 0)

    var assertReq: AllocatorRequest
    assertReq.mode = .AssertIsAllocated
    assertReq.address = req.address
    itf.req(&assertReq)

    req.mode = .Free
    itf.req(&req)
    @assert(req.address == null)
    @assert(alloc.countAlloc == 0)
    @assert(alloc.countFree == 1)
    @assert(alloc.firstFree == header)

    let freed = alloc.userAddress(header)
    for i in 144 do
        @assert(freed[i] == Allocator.FreeByte)

    alloc.freeAll()
    @assert(alloc.countFree == 0)
}

#test
{
    var alloc: Allocator
    let itf = makeDebugModeAllocator(&alloc, electricMode: true)

    var first: AllocatorRequest
    first.mode = .Alloc
    first.size = 64
    itf.req(&first)
    @assert(first.address != null)
    let firstAddress = first.address

    first.mode = .Free
    itf.req(&first)
    @assert(first.address == null)

    var second: AllocatorRequest
    second.mode = .Alloc
    second.size = 64
    itf.req(&second)
    @assert(second.address != null)
    @assert(second.address != firstAddress)

    var freeAll: AllocatorRequest
    freeAll.mode = .FreeAll
    itf.req(&freeAll)
    @assert(alloc.countAlloc == 0)
    @assert(alloc.countFree == 0)
}

#test
{
    var alloc: Allocator
    let itf = makeDebugModeAllocator(&alloc, trackAllocations: true, fillMemory: false)

    var reqs: [8] AllocatorRequest
    for i in 8
    {
        reqs[i].mode = .Alloc
        reqs[i].size = 32 + cast(u64) i * 23
        itf.req(&reqs[i])
        @assert(reqs[i].address != null)
    }

    @assert(alloc.countAlloc == 8)
    @assert(alloc.firstAlloc != null)
    alloc.checkAllMemory()

    for i in 8
    {
        reqs[i].mode = .Free
        itf.req(&reqs[i])
        @assert(reqs[i].address == null)
    }

    @assert(alloc.countAlloc == 0)
    @assert(alloc.countFree == 8)
    alloc.checkAllMemory()
    alloc.freeAll()
}

#test
{
    var alloc: Allocator
    let itf = makeDebugModeAllocator(&alloc, trackAllocations: false, fillMemory: true)

    var req: AllocatorRequest
    req.mode = .Alloc
    req.size = 96
    itf.req(&req)
    @assert(req.address != null)

    let ptr = cast([*] u8) req.address
    for i in 96 do
        @assert(ptr[i] == Allocator.AllocByte)

    req.mode = .Free
    itf.req(&req)
    @assert(req.address == null)
    alloc.freeAll()
}

#test
{
    var alloc: Allocator
    let itf = makeDebugModeAllocator(&alloc, trackAllocations: false, fillMemory: true)

    var untracked: AllocatorRequest
    untracked.mode = .Alloc
    untracked.size = 80
    itf.req(&untracked)
    @assert(untracked.address != null)
    @assert(alloc.countAlloc == 1)
    @assert(alloc.firstAlloc == null)

    alloc.configure(false, true, false, true, true)

    var tracked: AllocatorRequest
    tracked.mode = .Alloc
    tracked.size = 96
    itf.req(&tracked)
    @assert(tracked.address != null)

    let trackedHeader = cast(*AllocatorHeader) (cast([*] u8) tracked.address - #sizeof(AllocatorHeader))
    @assert(alloc.firstAlloc == trackedHeader)
    alloc.checkAllMemory()

    untracked.mode = .Free
    itf.req(&untracked)
    @assert(untracked.address == null)
    @assert(alloc.firstAlloc == trackedHeader)
    alloc.checkAllMemory()

    tracked.mode = .Free
    itf.req(&tracked)
    @assert(tracked.address == null)
    @assert(alloc.firstAlloc == null)

    alloc.freeAll()
}

#if #os == Swag.TargetOs.Windows
{
    #test
    {
        var alloc: Allocator
        let itf = makeDebugModeAllocator(&alloc, trackAllocations: true, fillMemory: false)

        var req: AllocatorRequest
        req.mode = .Alloc
        req.size = 512
        itf.req(&req)
        @assert(req.address != null)
        @assert(alloc.countOsAlloc >= 2)

        let header = cast(*AllocatorHeader) (cast([*] u8) req.address - #sizeof(AllocatorHeader))
        let rawBlock = cast(*AllocatorRawBlock) (cast([*] u8) header.allocAddr - #sizeof(AllocatorRawBlock))
        @assert(rawBlock.address != null)
        @assert(rawBlock.size >= header.allocSize + #sizeof(AllocatorRawBlock))
        @assert(cast(u64) rawBlock.address % 4096 == 0)

        req.mode = .Free
        itf.req(&req)
        @assert(req.address == null)

        var freeAll: AllocatorRequest
        freeAll.mode = .FreeAll
        itf.req(&freeAll)
        @assert(alloc.countOsFree == alloc.countOsAlloc)
        @assert(alloc.sizeOsFree == alloc.sizeOsAlloc)
    }
}
