#global private

using Swag

// Cross an arena boundary without committing the payload of a gibibyte of blocks.
// Each held segment commits only its header; both page sizes exercise the lookup index.
#test
{
    const Count = AllocatorArenaSize / AllocatorSegmentSize + 1
    var segments: [Count] (*AllocatorSegment?)
    var owner = 0'u64
    defer
    {
        for segment in segments
        {
            if segment do
                allocatorReleaseSegment(segment)
        }
    }

    for i in Count
    {
        let shift   = i & 1 ? AllocatorSmallUnitShift : AllocatorMediumUnitShift
        let segment = allocatorAcquireSegment(&owner, shift)!
        segments[i] = segment
        let base = cast(u64, segment)
        Swag.assert(allocatorPageOf(base + AllocatorSegmentHeaderBytes) == &segment.pages[0])
        Swag.assert(allocatorPageOf(base + AllocatorSegmentSize - 1) == &segment.pages[segment.pageCount - 1])
        for unit in AllocatorUnitsPerSegment do
            Swag.assert(allocatorPageOf(base + cast(u64, unit) * AllocatorPageSize) == &segment.pages[unit >> shift])
    }

    Swag.assert(allocatorPageOf(0) == null)
    Swag.assert(allocatorPageOf(cast(u64, &owner)) == null)

    var allocator: Allocator
    allocator.setup()
    defer allocator.releaseAll()
    let itf: IAllocator = &allocator
    for size in [24'u64, 60000]
    {
        var request: AllocatorRequest
        request.size = size
        itf.alloc(&request)
        Swag.assert(request.address != null)
        let block = cast([*] u8, request.address)
        block[0]        = 17
        block[size - 1] = 29
        Swag.assert(block[0] == 17 and block[size - 1] == 29)
        itf.free(&request)
        Swag.assert(request.address == null)
    }
}
