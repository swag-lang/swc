#global private

using Swag

// The host refusing a reservation or a commit must fail the request cleanly: no half-built page,
// segment, or heap record, masks and lists consistent, and the same request served once the host
// cooperates again. The seam in allocator.testing.swg refuses the calling thread's calls on demand.

func failureAllocator(allocator: *Allocator, electric = false)->IAllocator
{
    allocator.setup()
    allocator.configure(electric, false, false, false, false)
    return Swag.makeInterface(allocator, #typeof(allocator[]), IAllocator)
}

func allocOne(itf: IAllocator, size: u64)->*void?
{
    var request: AllocatorRequest
    request.size = size
    itf.alloc(&request)
    return request.address
}

func freeOne(itf: IAllocator, address: *void?)
{
    var request: AllocatorRequest
    request.address = address
    itf.free(&request)
}

// A page bit marks exactly the pages carrying blocks, an idle bit only a free page, and no bit lies
// outside the pages the segment can hand out.
func checkSegments(allocator: *Allocator)
{
    var segment = allocator.firstSegment
    while segment
    {
        let pageMask = atomicGet(&segment.pageMask)
        let idleMask = atomicGet(&segment.idleMask)
        Swag.assert((pageMask & idleMask) == 0)
        Swag.assert((pageMask & ~segment.usableMask) == 0)
        Swag.assert((idleMask & ~segment.usableMask) == 0)
        for i in segment.pageCount
        {
            let carrying = (pageMask & (1'u64 << i)) != 0
            Swag.assert(carrying == (segment.pages[i].state != AllocatorPageState.Free))
        }

        segment = segment.nextSegment
    }
}

// Serves and frees one block, then checks that the allocator is whole and gives everything back.
func checkRecovers(allocator: *Allocator, itf: IAllocator)
{
    let again = allocOne(itf, 64)
    Swag.assert(again != null)
    Swag.assert(allocator.stats().countAlloc == 1)
    checkSegments(allocator)
    freeOne(itf, again)
    Swag.assert(allocator.stats().countAlloc == 0)
    Swag.assert(allocator.firstAbandoned == null)

    allocator.releaseAll()
    let after = allocator.stats()
    Swag.assert(after.countSegment == 0 and after.countPage == 0 and after.countAlloc == 0)
}

// The first page allocation of a fresh allocator reserves and commits a heap record, commits a
// segment header, and commits a page; a pooled segment skips the header. Refusing every commit from
// the n-th one on fails the request whichever step it stops at, and the allocator stays whole.
#test
{
    for after in 0 until 4
    {
        var allocator: Allocator
        let itf = failureAllocator(&allocator)
        allocatorFailOsCommit(after, sticky: true)
        let address = allocOne(itf, 64)
        let refused = g_AllocatorOsFailures.commit.failures
        allocatorClearOsFailures()

        checkSegments(&allocator)
        if refused != 0
        {
            Swag.assert(address == null)
            Swag.assert(allocator.stats().countAlloc == 0)
            Swag.assert(allocator.stats().countPage == 0)
        }
        else
        {
            Swag.assert(address != null)
            freeOne(itf, address)
        }

        checkRecovers(&allocator, itf)
    }
}

// Refusing exactly one commit lets the allocator fall back where it can: a refused page commit
// in a segment with free pages is answered from another segment, while a refused heap record or
// segment header fails the request. Either way nothing half-built remains.
#test
{
    for after in 0 until 4
    {
        var allocator: Allocator
        let itf = failureAllocator(&allocator)
        allocatorFailOsCommit(after)
        let address = allocOne(itf, 64)
        allocatorClearOsFailures()

        checkSegments(&allocator)
        if address
        {
            Swag.assert(allocator.stats().countAlloc == 1)
            freeOne(itf, address)
        }
        else
        {
            Swag.assert(allocator.stats().countAlloc == 0)
        }

        checkRecovers(&allocator, itf)
    }
}

// A refused heap record reservation leaves the thread without a heap and the request unserved;
// the next request installs the heap.
#test
{
    var allocator: Allocator
    let itf = failureAllocator(&allocator)
    allocatorFailOsReserve()
    Swag.assert(allocOne(itf, 64) == null)
    Swag.assert(g_AllocatorOsFailures.reserve.failures == 1)
    allocatorClearOsFailures()
    Swag.assert(allocator.firstHeap == null)
    Swag.assert(allocator.stats().countAlloc == 0)
    checkRecovers(&allocator, itf)
}

// When the current page is exhausted, a refused page commit releases the page bit it had claimed
// and the request is served from another segment, or fails when every commit is refused.
#test
{
    var allocator: Allocator
    let itf = failureAllocator(&allocator)
    let first = allocOne(itf, 64)!
    let page  = allocatorPageOf(cast(u64, first))!
    let fill  = cast(u64, page.capacityBytes() / page.blockSize) - 1
    var held: [1024] (*void?)
    Swag.assert(fill <= held.count)
    for i in fill do
        held[i] = allocOne(itf, 64)
    Swag.assert(allocator.stats().countPage == 1)
    let segment = allocatorSegmentOf(page)

    allocatorFailOsCommit(sticky: true)
    Swag.assert(allocOne(itf, 64) == null)
    Swag.assert(g_AllocatorOsFailures.commit.failures >= 1)
    allocatorClearOsFailures()
    Swag.assert(allocator.stats().countPage == 1)
    Swag.assert(Swag.bitCountNz(atomicGet(&segment.pageMask)) == 1)
    checkSegments(&allocator)

    allocatorFailOsCommit()
    let served = allocOne(itf, 64)
    allocatorClearOsFailures()
    Swag.assert(served != null)
    Swag.assert(allocatorSegmentOf(allocatorPageOf(cast(u64, served))!) != segment)
    checkSegments(&allocator)

    freeOne(itf, served)
    for i in fill do
        freeOne(itf, held[i])
    freeOne(itf, first)
    checkRecovers(&allocator, itf)
}

// With every arena reported full, a segment needs a new reservation. Refused, no segment comes and
// no arena is added; granted, one arena is added and the segment comes from it.
#test
{
    defer allocatorClearOsFailures()
    let owner = defaultAllocator()

    // Take every pooled segment of the shape first, so the acquisitions under test must create one.
    var held: [256] (*AllocatorSegment?)
    let pooled = allocatorPooledSegmentCount(AllocatorSmallUnitShift)
    Swag.assert(pooled <= held.count)
    for i in pooled
    {
        held[i] = allocatorAcquireSegment(owner, AllocatorSmallUnitShift)
        Swag.assert(held[i] != null)
    }
    Swag.assert(allocatorPooledSegmentCount(AllocatorSmallUnitShift) == 0)

    let reserves = atomicGet(&g_AllocatorOsReserveCount)
    allocatorFillArenas()
    allocatorFailOsReserve()
    Swag.assert(allocatorAcquireSegment(owner, AllocatorSmallUnitShift) == null)
    Swag.assert(g_AllocatorOsFailures.reserve.failures == 1)
    Swag.assert(atomicGet(&g_AllocatorOsReserveCount) == reserves)

    allocatorClearOsFailures()
    allocatorFillArenas()
    let fresh = allocatorAcquireSegment(owner, AllocatorSmallUnitShift)
    Swag.assert(fresh != null)
    Swag.assert(atomicGet(&g_AllocatorOsReserveCount) == reserves + 1)
    allocatorClearOsFailures()

    allocatorReleaseSegment(fresh)
    for i in pooled do
        allocatorReleaseSegment(held[i]!)
}

// A header-path block whose reservation or commit is refused is not allocated, commits nothing,
// and enters no list.
#test
{
    for electric in [false, true]
    {
        var allocator: Allocator
        let itf = failureAllocator(&allocator, electric)
        let before = allocator.stats()

        allocatorFailOsReserve()
        Swag.assert(allocOne(itf, 200_000) == null)
        allocatorFailOsCommit()
        Swag.assert(allocOne(itf, 200_000) == null)
        Swag.assert(g_AllocatorOsFailures.reserve.failures == 1 and g_AllocatorOsFailures.commit.failures == 1)
        allocatorClearOsFailures()

        let after = allocator.stats()
        Swag.assert(after.countAlloc == 0)
        Swag.assert(after.sizeCommitted == before.sizeCommitted)
        Swag.assert(after.countOsCommit == before.countOsCommit)
        Swag.assert(allocator.firstAlloc == null)
        for i in AllocatorHeaderShardCount do
            Swag.assert(allocator.shards[i].first == null)
        Swag.assert(allocator.cachedBlockCount == 0)

        let block = allocOne(itf, 200_000)
        Swag.assert(block != null)
        freeOne(itf, block)
        allocator.releaseAll()
        Swag.assert(allocator.stats().sizeCommitted == before.sizeCommitted)
    }
}

// A reallocation that cannot commit the next pages of its reservation moves the data instead.
#test
{
    var allocator: Allocator
    let itf = failureAllocator(&allocator)

    var request: AllocatorRequest
    request.size = 66000
    itf.alloc(&request)
    let original = request.address!
    let bytes    = cast([*] u8, original)
    for i in 66000 do
        bytes[i] = cast #wrap (u8, i)

    allocatorFailOsCommit()
    request.oldSize = 66000
    request.size    = 72000
    itf.realloc(&request)
    Swag.assert(g_AllocatorOsFailures.commit.failures == 1)
    allocatorClearOsFailures()

    Swag.assert(request.address != null and request.address != original)
    let moved = cast([*] u8, request.address)
    for i in 66000 do
        Swag.assert(moved[i] == cast #wrap (u8, i))
    Swag.assert(allocator.stats().countAlloc == 1)
    Swag.assert(allocator.cachedBlockCount == 1)

    itf.free(&request)
    allocator.releaseAll()
}

// A cached block that committed less than the request needs goes back to the cache when the
// missing pages are refused, and the request is served from a new reservation.
#test
{
    var allocator: Allocator
    let itf = failureAllocator(&allocator)

    let first  = allocOne(itf, 66000)!
    let region = allocator.headerOf(cast(u64, first)).allocAddr
    freeOne(itf, first)
    Swag.assert(allocator.cachedBlockCount == 1)
    Swag.assert(allocator.cachedBlocks[0].address == cast(u64, region))
    Swag.assert(allocator.cachedBlocks[0].committed < allocator.cachedBlocks[0].reserved)

    allocatorFailOsCommit()
    let second = allocOne(itf, 72000)
    Swag.assert(g_AllocatorOsFailures.commit.failures == 1)
    allocatorClearOsFailures()

    Swag.assert(second != null and second != first)
    Swag.assert(allocator.cachedBlockCount == 1)
    Swag.assert(allocator.cachedBlocks[0].address == cast(u64, region))
    Swag.assert(allocator.stats().countAlloc == 1)

    freeOne(itf, second)
    allocator.releaseAll()
}
