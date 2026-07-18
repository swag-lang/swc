#global private

using Swag

func makeContextCaptureAllocator(alloc: *Allocator)->IAllocator
{
    alloc.setup()
    alloc.configure(false, false, true, false, true)
    return @mkinterface(alloc, #typeof(dref alloc), IAllocator)
}

func contextCaptureAlloc(size: u64, alignment: u32 = 0)->AllocatorRequest
{
    var req: AllocatorRequest
    req.size = size
    req.alignment = alignment
    @getcontext().allocator.alloc(&req)
    return req
}

func contextCaptureFree(req: *AllocatorRequest)
{
    @getcontext().allocator.free(req)
    @assert(req.address == null)
}

#test
{
    if @jit() do
        return

    let alloc = defaultAllocator()
    let beforeCount = alloc.countAlloc
    let beforeSize = alloc.sizeAlloc

    var req = contextCaptureAlloc(80)
    @assert(req.address != null)

    let ptr = cast([*] u8) req.address
    for i in 80 do
        ptr[i] = cast(u8) (i + 9)

    req.oldSize = 80
    req.size = 4096
    @getcontext().allocator.realloc(&req)
    @assert(req.address != null)

    let grown = cast([*] u8) req.address
    for i in 80 do
        @assert(grown[i] == cast(u8) (i + 9))

    contextCaptureFree(&req)
    @assert(alloc.countAlloc == beforeCount)
    @assert(alloc.sizeAlloc == beforeSize)
}

#test
{
    if @jit() do
        return

    let alloc = defaultAllocator()
    let beforeCount = alloc.countAlloc

    var reqs: [8] AllocatorRequest
    for i in 8
    {
        reqs[i] = contextCaptureAlloc(31 + cast(u64) i * 37, i % 3 == 0 ? 64 : 0)
        @assert(reqs[i].address != null)
    }

    @assert(alloc.countAlloc == beforeCount + 8)

    for i in 8 do
        contextCaptureFree(&reqs[i])

    @assert(alloc.countAlloc == beforeCount)
}

#test
{
    var alloc: Allocator
    let itf = makeContextCaptureAllocator(&alloc)

    var req: AllocatorRequest
    req.size = 112
    req.hint = "after-context-debug"
    itf.alloc(&req)
    @assert(req.address != null)

    let header = cast(*AllocatorHeader) (cast([*] u8) req.address - #sizeof(AllocatorHeader))
    @assert(header.magic == Allocator.MagicAlloc)
    @assert(header.stackCount <= @countof(header.stack))

    itf.free(&req)
    @assert(req.address == null)
    alloc.releaseAll()
}