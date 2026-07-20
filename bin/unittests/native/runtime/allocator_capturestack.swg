#global private

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
    itf.freeAll(&req)
    @assert(req.address == null)
    alloc.releaseAll()
}

#test
{
    var alloc: Allocator
    let itf = makeCaptureAllocator(&alloc)

    var req: AllocatorRequest
    req.size = 0
    itf.alloc(&req)
    @assert(req.address == null)
    alloc.releaseAll()
}

#test
{
    var alloc: Allocator
    let itf = makeCaptureAllocator(&alloc)

    var req: AllocatorRequest
    req.size = 1
    itf.alloc(&req)
    @assert(req.address != null)

    itf.free(&req)
    @assert(req.address == null)
    alloc.releaseAll()
}

#test
{
    var alloc: Allocator
    let itf = makeCaptureAllocator(&alloc)

    var req: AllocatorRequest
    req.size = 112
    req.hint = "capture-stack-minimal"
    itf.alloc(&req)
    @assert(req.address != null)

    let header = cast(*AllocatorHeader) (cast([*] u8) (assume req.address) - #sizeof(AllocatorHeader))
    @assert(header.magic == Allocator.MagicAlloc)
    @assert(header.stackCount <= @countof(header.stack))

    itf.free(&req)
    @assert(req.address == null)
    alloc.releaseAll()
}