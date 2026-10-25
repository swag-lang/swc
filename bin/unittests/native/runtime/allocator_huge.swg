#global private

using Swag

// Huge blocks: a header-path block that committed more than the block cache budget, the live
// header-path bytes bounded by 16 MiB and 256 MiB, may wait in the cache only while the cache is
// empty; the next cached block replaces it, and trim() releases it. Both reserve eight sizes per
// power of two and grow in place inside that reservation.

const HugeBytes = 20'u64 * 1024 * 1024
const MidBytes  = 8'u64 * 1024 * 1024

func hugeAllocator(allocator: *Allocator)->IAllocator
{
    allocator.setup()
    allocator.configure(false, false, false, false, false)
    return Swag.makeInterface(allocator, #typeof(allocator[]), IAllocator)
}

func allocTouched(itf: IAllocator, size: u64)->*void?
{
    var request: AllocatorRequest
    request.size = size
    itf.alloc(&request)
    Swag.assert(request.address != null)
    let bytes = cast([*] u8, request.address)
    bytes[0]        = 1
    bytes[size - 1] = 1
    return request.address
}

func freeOne(itf: IAllocator, address: *void?)
{
    var request: AllocatorRequest
    request.address = address
    itf.free(&request)
}

// With nothing else live the budget is its floor: a block above it waits in the empty cache and
// serves the next request of its size without a system call, a block cached after it replaces it,
// and trim() gives the cache back.
#test
{
    var allocator: Allocator
    let itf = hugeAllocator(&allocator)
    defer allocator.releaseAll()

    let before = allocator.stats().sizeCommitted
    Swag.assert(allocator.blockCacheBudget() == AllocatorBlockCacheMinBytes)
    Swag.assert(HugeBytes > AllocatorBlockCacheMinBytes and MidBytes < AllocatorBlockCacheMinBytes)

    let huge = allocTouched(itf, HugeBytes)
    Swag.assert(allocator.stats().sizeCommitted >= before + HugeBytes)
    freeOne(itf, huge)
    Swag.assert(allocator.cachedBlockCount == 1)
    Swag.assert(allocator.stats().sizeCommitted >= before + HugeBytes)

    let commits = allocator.stats().countOsCommit
    let again   = allocTouched(itf, HugeBytes)
    Swag.assert(again == huge)
    Swag.assert(allocator.stats().countOsCommit == commits)
    freeOne(itf, again)
    Swag.assert(allocator.cachedBlockCount == 1)

    let mid = allocTouched(itf, MidBytes)
    freeOne(itf, mid)
    Swag.assert(allocator.cachedBlockCount == 1)
    Swag.assert(allocator.cachedBlocks[0].reserved < HugeBytes)
    Swag.assert(allocator.stats().sizeCommitted < before + HugeBytes)

    allocator.trim()
    Swag.assert(allocator.cachedBlockCount == 0)
    Swag.assert(allocator.stats().sizeCommitted == before)
}

// A huge block grows in place while its rounded reservation has room, committing only the pages
// the new size reaches, and moves with its contents once it does not.
#test
{
    var allocator: Allocator
    let itf = hugeAllocator(&allocator)
    defer allocator.releaseAll()

    var request: AllocatorRequest
    request.size = HugeBytes
    itf.alloc(&request)
    let original = unwrap request.address
    let header   = allocator.headerOf(cast(u64, original))
    Swag.assert(header.allocSize >= HugeBytes + 1024 * 1024)
    Swag.assert(header.commitSize < header.allocSize)
    cast([*] u8, original)[HugeBytes - 1] = 7

    let committed = allocator.stats().sizeCommitted
    request.oldSize = HugeBytes
    request.size    = HugeBytes + 1024 * 1024
    itf.realloc(&request)
    Swag.assert(request.address == original)
    Swag.assert(allocator.stats().sizeCommitted >= committed + 1024 * 1024)
    cast([*] u8, original)[request.size - 1] = 9

    request.oldSize = request.size
    request.size    = HugeBytes + 12 * 1024 * 1024
    itf.realloc(&request)
    Swag.assert(request.address != null and request.address != original)
    let moved = cast([*] u8, request.address)
    Swag.assert(moved[HugeBytes - 1] == 7 and moved[HugeBytes + 1024 * 1024 - 1] == 9)
    Swag.assert(allocator.stats().countAlloc == 1)
    itf.free(&request)
}
