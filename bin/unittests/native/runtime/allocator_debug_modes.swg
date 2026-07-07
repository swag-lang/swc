#global private

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
    req.size = 144
    req.hint = "debug-no-stack"
    itf.alloc(&req)
    @assert(req.address != null)
    @assert(alloc.countAlloc == 1)
    @assert(alloc.firstAlloc != null)

    let header = cast(*AllocatorHeader) (cast([*] u8) req.address - #sizeof(AllocatorHeader))
    @assert(header == alloc.firstAlloc)
    @assert(header.stackCount == 0)

    var assertReq: AllocatorRequest
    assertReq.address = req.address
    itf.assertAllocated(&assertReq)

    itf.free(&req)
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
        reqs[i].size = 32 + cast(u64) i * 23
        itf.alloc(&reqs[i])
        @assert(reqs[i].address != null)
    }

    @assert(alloc.countAlloc == 8)
    @assert(alloc.firstAlloc != null)
    alloc.checkAllMemory()

    for i in 8
    {
        itf.free(&reqs[i])
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
    req.size = 96
    itf.alloc(&req)
    @assert(req.address != null)

    let ptr = cast([*] u8) req.address
    for i in 96 do
        @assert(ptr[i] == Allocator.AllocByte)

    itf.free(&req)
    @assert(req.address == null)
    alloc.freeAll()
}

#test
{
    var alloc: Allocator
    let itf = makeDebugModeAllocator(&alloc, trackAllocations: false, fillMemory: true)

    var untracked: AllocatorRequest
    untracked.size = 80
    itf.alloc(&untracked)
    @assert(untracked.address != null)
    @assert(alloc.countAlloc == 1)
    @assert(alloc.firstAlloc == null)

    alloc.configure(false, true, false, true, true)

    var tracked: AllocatorRequest
    tracked.size = 96
    itf.alloc(&tracked)
    @assert(tracked.address != null)

    let trackedHeader = cast(*AllocatorHeader) (cast([*] u8) tracked.address - #sizeof(AllocatorHeader))
    @assert(alloc.firstAlloc == trackedHeader)
    alloc.checkAllMemory()

    itf.free(&untracked)
    @assert(untracked.address == null)
    @assert(alloc.firstAlloc == trackedHeader)
    alloc.checkAllMemory()

    itf.free(&tracked)
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
        req.size = 512
        itf.alloc(&req)
        @assert(req.address != null)
        @assert(alloc.countOsAlloc >= 2)

        let header = cast(*AllocatorHeader) (cast([*] u8) req.address - #sizeof(AllocatorHeader))
        let rawBlock = cast(*AllocatorRawBlock) (cast([*] u8) header.allocAddr - #sizeof(AllocatorRawBlock))
        @assert(rawBlock.address != null)
        @assert(rawBlock.size >= header.allocSize + #sizeof(AllocatorRawBlock))
        @assert(cast(u64) rawBlock.address % 4096 == 0)

        itf.free(&req)
        @assert(req.address == null)

        var freeAll: AllocatorRequest
        itf.freeAll(&freeAll)
        @assert(alloc.countOsFree == alloc.countOsAlloc)
        @assert(alloc.sizeOsFree == alloc.sizeOsAlloc)
    }
}