#global private

using Swag

// Idle memory: an emptied page stays committed under the process-wide budget and any class reuses
// it without a system call; a purge check gives it back once the delay has passed; a block freed
// into a page whose owner is idle waits for that owner. The bounds are the constants at the top of
// allocator.pages.swg and allocator.swg: the idle budget, the purge delay and the block cache.

func idleAllocator(allocator: *Allocator)->IAllocator
{
    allocator.setup()
    allocator.configure(false, false, false, false, false)
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

const HeldCount = 2100

// Fills the first two pages of the 64-byte class and one block past them, so that the third page
// is the current one and freeing everything keeps the first as the class's spare and retires the
// second. Returns the second page.
func fillFirstPages(itf: IAllocator, held: *[HeldCount] (*void?))->*AllocatorPage
{
    // The first page of a segment holds fewer blocks than the next, so each page is filled by
    // its own capacity; the block past a full page opens the next one.
    held[][0] = allocOne(itf, 64)
    var count = 1'u64
    let first = allocatorPageOf(cast(u64, held[][0]))!
    for first.capacityBytes() / first.blockSize
    {
        held[][count] = allocOne(itf, 64)
        count         += 1
    }

    let second = allocatorPageOf(cast(u64, held[][count - 1]))!
    Swag.assert(second != first)
    for second.capacityBytes() / second.blockSize
    {
        Swag.assert(count < HeldCount)
        held[][count] = allocOne(itf, 64)
        count         += 1
    }

    Swag.assert(allocatorPageOf(cast(u64, held[][count - 1])) != second)
    return second
}

// An emptied page stays committed and idle, and the next page any class needs takes it back
// without a system call.
#test
{
    var allocator: Allocator
    let itf = idleAllocator(&allocator)
    defer allocator.releaseAll()

    var held: [HeldCount] (*void?)
    let page    = fillFirstPages(itf, &held)
    let segment = allocatorSegmentOf(page)
    let bit     = 1'u64 << (page.unitIndex >> segment.unitShift)
    let filled  = allocator.stats()
    Swag.assert(filled.countPage == 3)

    for block in held where block do
        freeOne(itf, block)

    // The current page and the class's spare stay; the other emptied page is idle.
    let emptied = allocator.stats()
    Swag.assert(emptied.countPage == 2)
    Swag.assert(emptied.countOsDecommit == filled.countOsDecommit)
    Swag.assert(atomicGet(&segment.idleMask) & bit)
    Swag.assert(allocatorIdleBytes() >= page.capacityBytes())

    let other = allocOne(itf, 200)
    Swag.assert(allocatorPageOf(cast(u64, other)) == page)
    Swag.assert(allocator.stats().countOsCommit == emptied.countOsCommit)
    Swag.assert((atomicGet(&segment.idleMask) & bit) == 0)
    freeOne(itf, other)
}

// Once idle memory has outlived the purge delay, the next purge check decommits it. The first
// check arms the deadline and a check before it does nothing.
#test
{
    var allocator: Allocator
    let itf = idleAllocator(&allocator)
    defer allocator.releaseAll()

    var held: [HeldCount] (*void?)
    let page    = fillFirstPages(itf, &held)
    let segment = allocatorSegmentOf(page)
    let bit     = 1'u64 << (page.unitIndex >> segment.unitShift)
    for block in held where block do
        freeOne(itf, block)
    Swag.assert(atomicGet(&segment.idleMask) & bit)

    allocator.purgeDeadline = 0
    allocator.maybePurge()
    Swag.assert(allocator.purgeDeadline != 0)

    let decommits = allocator.stats().countOsDecommit
    allocator.maybePurge()
    Swag.assert(allocator.stats().countOsDecommit == decommits)
    Swag.assert(atomicGet(&segment.idleMask) & bit)

    allocator.purgeDeadline = 1
    allocator.maybePurge()
    Swag.assert(allocator.stats().countOsDecommit > decommits)
    Swag.assert((atomicGet(&segment.idleMask) & bit) == 0)
    Swag.assert(allocator.purgeDeadline == 0)
}

#static if #os == Swag.TargetOs.Windows
{
    namespace Th
    {
        alias HANDLE = *void
        alias DWORD  = u32
        alias SIZE_T = u64
        #[Swag.CallingConvention(.C)]
        alias LPTHREAD_START_ROUTINE = func(*void)->DWORD

        const INFINITE = 0xFFFF_FFFF'u32

        #[Swag.Foreign("kernel32", callconv: Swag.CallConv.C)]
        {
            func CreateThread(lpThreadAttributes: *void?, dwStackSize: SIZE_T, lpStartAddress: LPTHREAD_START_ROUTINE, lpParameter: *void, dwCreationFlags: DWORD, lpThreadId: *DWORD)->HANDLE
            func WaitForSingleObject(hHandle: HANDLE, dwMilliseconds: DWORD)->DWORD
            func CloseHandle(handle: HANDLE)
        }
    }

    struct IdleOwner
    {
        itf:       IAllocator?
        blocks:    [8] (*void?)
        allocated: s32
        release:   s32
    }

    // Allocates a few blocks, then stays idle until told to retire its heap.
    #[Swag.CallingConvention(.C)]
    func idleOwnerThread(param: *void)->Th.DWORD
    {
        let owner = cast(*IdleOwner, param)
        for i in owner.blocks.count do
            owner.blocks[i] = allocOne(owner.itf!, 64)
        discard Swag.atomxchg(&owner.allocated, 1)
        while Swag.atomcmpxchg(&owner.release, 0, 0) == 0 {}

        releaseAllocatorThreadCache()
        return 0
    }

    // Blocks freed by another thread wait on their page's remote list: the statistics already count
    // them as free, but the page stays for its idle owner, whom no other thread's trim can stand in
    // for, until that owner allocates, trims, or retires.
    #test
    {
        var allocator: Allocator
        let itf = idleAllocator(&allocator)
        defer allocator.releaseAll()

        var owner: IdleOwner
        owner.itf = itf
        var tid: Th.DWORD
        let thread = Th.CreateThread(null, 0, &idleOwnerThread, &owner, 0, &tid)
        Swag.assert(thread != null)
        while Swag.atomcmpxchg(&owner.allocated, 0, 0) == 0 {}
        Swag.assert(allocator.stats().countAlloc == owner.blocks.count)

        for block in owner.blocks do
            freeOne(itf, block)
        let page = allocatorPageOf(cast(u64, owner.blocks[0]))!
        Swag.assert(page.remoteCount() == owner.blocks.count)
        Swag.assert(allocator.stats().countAlloc == 0)
        Swag.assert(allocator.stats().countPage == 1)

        allocator.trim()
        Swag.assert(allocator.stats().countPage == 1)

        discard Swag.atomxchg(&owner.release, 1)
        discard Th.WaitForSingleObject(thread, Th.INFINITE)
        Th.CloseHandle(thread)
        Swag.assert(allocator.stats().countPage == 0)
    }
}
