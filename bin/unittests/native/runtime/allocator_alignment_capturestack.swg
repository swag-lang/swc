#global private

using Swag

func makeAlignmentCaptureAllocator(alloc: *Allocator, captureStack: bool = false)->IAllocator
{
    alloc.setup()
    alloc.configure(false, false, captureStack, false, true)
    return @mkinterface(alloc, #typeof(dref alloc), IAllocator)
}

#test
{
    var alloc: Allocator
    let itf = makeAlignmentCaptureAllocator(&alloc)

    var req: AllocatorRequest
    req.mode = .Alloc
    req.size = 257
    req.alignment = 128
    itf.req(&req)
    @assert(req.address != null)
    @assert(cast(u64) req.address % 128 == 0)

    req.mode = .Free
    itf.req(&req)
    @assert(req.address == null)
    alloc.freeAll()
}

#test
{
    var alignedAlloc: Allocator
    let alignedItf = makeAlignmentCaptureAllocator(&alignedAlloc)

    var aligned: AllocatorRequest
    aligned.mode = .Alloc
    aligned.size = 257
    aligned.alignment = 128
    alignedItf.req(&aligned)
    @assert(aligned.address != null)
    @assert(cast(u64) aligned.address % 128 == 0)

    aligned.mode = .Free
    alignedItf.req(&aligned)
    @assert(aligned.address == null)
    alignedAlloc.freeAll()

    var captureAlloc: Allocator
    let captureItf = makeAlignmentCaptureAllocator(&captureAlloc, captureStack: true)

    var captured: AllocatorRequest
    captured.mode = .Alloc
    captured.size = 112
    captured.hint = "alignment-then-capture"
    captureItf.req(&captured)
    @assert(captured.address != null)

    let header = cast(*AllocatorHeader) (cast([*] u8) captured.address - #sizeof(AllocatorHeader))
    @assert(header.magic == Allocator.MagicAlloc)
    @assert(header.stackCount <= @countof(header.stack))

    captured.mode = .Free
    captureItf.req(&captured)
    @assert(captured.address == null)
    captureAlloc.freeAll()
}

#test
{
    var alloc: Allocator
    let itf = makeAlignmentCaptureAllocator(&alloc, captureStack: true)

    var reqs: [6] AllocatorRequest
    for i in 6
    {
        reqs[i].mode = .Alloc
        reqs[i].size = 64 + cast(u64) i * 41
        reqs[i].alignment = 128
        itf.req(&reqs[i])
        @assert(reqs[i].address != null)
        @assert(cast(u64) reqs[i].address % 128 == 0)
    }

    for i in 6
    {
        reqs[i].mode = .Free
        itf.req(&reqs[i])
        @assert(reqs[i].address == null)
    }

    alloc.freeAll()
}
