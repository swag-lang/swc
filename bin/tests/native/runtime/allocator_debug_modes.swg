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
