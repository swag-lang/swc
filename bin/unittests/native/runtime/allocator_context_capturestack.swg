#global if #hastag("Swag.AllocatorDiagnostics")
#global private

using Swag

func makeContextCaptureAllocator(alloc: *Allocator)->IAllocator
{
    alloc.setup()
    alloc.configure(false, false, true, false, true)
    return Swag.makeInterface(alloc, #typeof(alloc[]), IAllocator)
}

func contextCaptureAlloc(size: u64, alignment: u32 = 0)->AllocatorRequest
{
    var req: AllocatorRequest
    req.size      = size
    req.alignment = alignment
    let allocItf = unwrap Swag.getContext().allocator
    allocItf.alloc(&req)
    return req
}

func contextCaptureFree(req: *AllocatorRequest)
{
    let allocItf = unwrap Swag.getContext().allocator
    allocItf.free(req)
    Swag.assert(req.address == null)
}

#test
{
    if Swag.jit() do
        return

    let alloc       = defaultAllocator()
    let beforeCount = alloc.stats().countAlloc
    let beforeSize  = alloc.stats().sizeAlloc

    var req = contextCaptureAlloc(80)
    Swag.require(req.address != null)

    let ptr = cast([*] u8, req.address)
    for i in 80 do
        ptr[i] = cast(u8, (i + 9))

    req.oldSize = 80
    req.size    = 4096
    let allocItf = unwrap Swag.getContext().allocator
    allocItf.realloc(&req)
    Swag.require(req.address != null)

    let grown = cast([*] u8, req.address)
    for i in 80 do
        Swag.require(grown[i] == cast(u8, (i + 9)))

    contextCaptureFree(&req)
    Swag.require(alloc.stats().countAlloc == beforeCount)
    Swag.require(alloc.stats().sizeAlloc == beforeSize)
}

#test
{
    if Swag.jit() do
        return

    let alloc       = defaultAllocator()
    let beforeCount = alloc.stats().countAlloc

    var reqs: [8] AllocatorRequest
    for i in 8
    {
        reqs[i] = contextCaptureAlloc(31 + cast(u64, i) * 37, i % 3 == 0 ? 64 : 0)
        Swag.require(reqs[i].address != null)
    }

    Swag.require(alloc.stats().countAlloc == beforeCount + 8)

    for i in 8 do
        contextCaptureFree(&reqs[i])

    Swag.require(alloc.stats().countAlloc == beforeCount)
}

#test
{
    var alloc: Allocator
    let itf = makeContextCaptureAllocator(&alloc)

    var req: AllocatorRequest
    req.size = 112
    req.hint = "after-context-debug"
    itf.alloc(&req)
    Swag.require(req.address != null)

    let header   = cast(*AllocatorHeader, (cast([*] u8, req.address) - #sizeof(AllocatorHeader)))
    let tracking = unwrap header.tracking
    Swag.require(header.magic == Allocator.MagicAlloc)
    Swag.require(tracking.stackCount <= tracking.stack.count)

    itf.free(&req)
    Swag.require(req.address == null)
    alloc.releaseAll()
}
