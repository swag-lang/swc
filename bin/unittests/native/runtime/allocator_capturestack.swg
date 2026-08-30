#global private

using Swag

func makeCaptureAllocator(alloc: *Allocator)->IAllocator
{
    alloc.setup()
    alloc.configure(false, true, true, false, true)
    return Swag.makeInterface(alloc, #typeof(alloc[]), IAllocator)
}

#test
{
    var alloc: Allocator
    let itf = makeCaptureAllocator(&alloc)
    Swag.assert(alloc.captureAllocStack)
    Swag.assert(alloc.detectLeaks)
    Swag.assert(!alloc.trackAllocations)
    Swag.assert(alloc.fillAlloc)

    var req: AllocatorRequest
    itf.freeAll(&req)
    Swag.assert(req.address == null)
    alloc.releaseAll()
}

#test
{
    var alloc: Allocator
    let itf = makeCaptureAllocator(&alloc)

    var req: AllocatorRequest
    req.size = 0
    itf.alloc(&req)
    Swag.assert(req.address == null)
    alloc.releaseAll()
}

#test
{
    var alloc: Allocator
    let itf = makeCaptureAllocator(&alloc)

    var req: AllocatorRequest
    req.size = 1
    itf.alloc(&req)
    Swag.assert(req.address != null)

    itf.free(&req)
    Swag.assert(req.address == null)
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
    Swag.assert(req.address != null)

    let header   = cast(*AllocatorHeader) (cast([*] u8) req.address! - #sizeof(AllocatorHeader))
    let tracking = header.tracking!
    Swag.assert(header.magic == Allocator.MagicAlloc)
    Swag.assert(tracking.stackCount <= tracking.stack.count)

    itf.free(&req)
    Swag.assert(req.address == null)
    alloc.releaseAll()
}
