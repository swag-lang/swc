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
    req.size      = 257
    req.alignment = 128
    itf.alloc(&req)
    @assert(req.address != null)
    @assert(cast(u64) req.address % 128 == 0)

    itf.free(&req)
    @assert(req.address == null)
    alloc.releaseAll()
}

#test
{
    var alignedAlloc: Allocator
    let alignedItf = makeAlignmentCaptureAllocator(&alignedAlloc)

    var aligned: AllocatorRequest
    aligned.size      = 257
    aligned.alignment = 128
    alignedItf.alloc(&aligned)
    @assert(aligned.address != null)
    @assert(cast(u64) aligned.address % 128 == 0)

    alignedItf.free(&aligned)
    @assert(aligned.address == null)
    alignedAlloc.releaseAll()

    var captureAlloc: Allocator
    let captureItf = makeAlignmentCaptureAllocator(&captureAlloc, captureStack: true)

    var captured: AllocatorRequest
    captured.size = 112
    captured.hint = "alignment-then-capture"
    captureItf.alloc(&captured)
    @assert(captured.address != null)

    let header = cast(*AllocatorHeader) (cast([*] u8) (notnull captured.address) - #sizeof(AllocatorHeader))
    @assert(header.magic == Allocator.MagicAlloc)
    @assert(header.stackCount <= @countof(header.stack))

    captureItf.free(&captured)
    @assert(captured.address == null)
    captureAlloc.releaseAll()
}

#test
{
    var alloc: Allocator
    let itf = makeAlignmentCaptureAllocator(&alloc, captureStack: true)

    var reqs: [6] AllocatorRequest
    for [i] in 6
    {
        reqs[i].size      = 64 + cast(u64) i * 41
        reqs[i].alignment = 128
        itf.alloc(&reqs[i])
        @assert(reqs[i].address != null)
        @assert(cast(u64) reqs[i].address % 128 == 0)
    }

    for [i] in 6
    {
        itf.free(&reqs[i])
        @assert(reqs[i].address == null)
    }

    alloc.releaseAll()
}
