#global private

using Swag

// Best-fit cache lookup must keep finding the right block after arbitrary removals,
// reject blocks over twice the request, and work again after trimming the cache.
#test
{
    var allocator: Allocator
    allocator.setup()
    defer allocator.releaseAll()
    let itf: IAllocator = &allocator
    const Sizes = [100_000'u64, 200_000, 350_000, 700_000]
    var requests:  [Sizes.count] AllocatorRequest
    var addresses: [Sizes.count] u64

    for 2
    {
        for i in Sizes.count
        {
            requests[i].size = Sizes[i]
            itf.alloc(&requests[i])
            Swag.assert(requests[i].address != null)
            addresses[i] = cast(u64, requests[i].address)
        }
        for &request in requests do
            itf.free(request)

        // A wrapped undersized block must not fit, even when the reuse limit saturates.
        for size in [1'u64 << 63, Swag.U64.Max - 1, Swag.U64.Max]
        {
            var reserved, committed: u64
            let block = allocator.popCachedBlock(size, &reserved, &committed)
            Swag.assert(block == null)
        }

        for i in [1'u64, 3, 0, 2]
        {
            requests[i].size = i == 3 ? 600_000 : Sizes[i]
            itf.alloc(&requests[i])
            Swag.assert(cast(u64, requests[i].address) == addresses[i])
            cast([*] u8, requests[i].address!)[requests[i].size - 1] = 29
        }
        for &request in requests do
            itf.free(request)
        allocator.trim()
    }

    var request: AllocatorRequest
    request.size = 2_000_000
    itf.alloc(&request)
    Swag.assert(request.address != null)
    let largeAddress = cast(u64, request.address)
    itf.free(&request)

    request.size = 100_000
    itf.alloc(&request)
    Swag.assert(request.address != null and cast(u64, request.address) != largeAddress)
    itf.free(&request)
    Swag.assert(allocator.stats().countAlloc == 0)
    Swag.assert(allocator.stats().sizeAlloc == 0)
}
