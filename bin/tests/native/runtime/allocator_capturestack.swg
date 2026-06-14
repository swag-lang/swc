#global fileprivate

using Swag

func makeCaptureAllocator(alloc: *Allocator)->IAllocator
{
    alloc.setup()
    alloc.configure(false, true, true, false, true)
    return @mkinterface(alloc, #typeof(dref alloc), IAllocator)
}

#test
{
    var alloc: Allocator
    let itf = makeCaptureAllocator(&alloc)
    @assert(alloc.captureAllocStack)
    @assert(alloc.detectLeaks)
    @assert(!alloc.trackAllocations)
    @assert(alloc.fillAlloc)

    var req: AllocatorRequest
    req.mode = .FreeAll
    itf.req(&req)
    @assert(req.address == null)
    alloc.freeAll()
}

#test
{
    var alloc: Allocator
    let itf = makeCaptureAllocator(&alloc)

    var req: AllocatorRequest
    req.mode = .Alloc
    req.size = 0
    itf.req(&req)
    @assert(req.address == null)
    alloc.freeAll()
}

#test
{
    var alloc: Allocator
    let itf = makeCaptureAllocator(&alloc)

    var req: AllocatorRequest
    req.mode = .Alloc
    req.size = 1
    itf.req(&req)
    @assert(req.address != null)

    req.mode = .Free
    itf.req(&req)
    @assert(req.address == null)
    alloc.freeAll()
}

#test
{
    var alloc: Allocator
    let itf = makeCaptureAllocator(&alloc)

    var req: AllocatorRequest
    req.mode = .Alloc
    req.size = 112
    req.hint = "capture-stack-minimal"
    itf.req(&req)
    @assert(req.address != null)

    let header = cast(*AllocatorHeader) (cast([*] u8) req.address - #sizeof(AllocatorHeader))
    @assert(header.magic == Allocator.MagicAlloc)
    @assert(header.stackCount <= @countof(header.stack))

    req.mode = .Free
    itf.req(&req)
    @assert(req.address == null)
    alloc.freeAll()
}
