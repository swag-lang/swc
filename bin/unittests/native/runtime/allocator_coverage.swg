#global private

using Swag

func makeAllocator(alloc: *Allocator, electricMode: bool = false, detectLeaks: bool = false, captureStack: bool = false, trackAllocations: bool = false, fillMemory: bool = false)->IAllocator
{
    alloc.setup()
    alloc.configure(electricMode, detectLeaks, captureStack, trackAllocations, fillMemory)
    return Swag.makeInterface(alloc, #typeof(alloc[]), IAllocator)
}

func allocOne(itf: IAllocator, size: u64, alignment: u32 = 0)->#null *void
{
    var req: AllocatorRequest
    req.size      = size
    req.alignment = alignment
    itf.alloc(&req)
    return req.address
}

func freeOne(itf: IAllocator, address: #null *void)
{
    var req: AllocatorRequest
    req.address = address
    itf.free(&req)
}

// ----------------------------------------------------------------------------
// Pure size-class mapping: classSize() must be strictly increasing and
// sizeClass() must invert it on the boundaries.
// ----------------------------------------------------------------------------
#test
{
    var prev = 0'u64
    for i in AllocatorClassCount
    {
        let sz = Allocator.classSize(cast(u32) i)
        Swag.assert(sz > prev)
        prev = sz

        // The exact class size maps back to that class...
        Swag.assert(Allocator.sizeClass(sz) == cast(u32) i)
    }

    // ...and one byte past a class spills into the next one.
    for i in AllocatorClassCount - 1
    {
        let sz = Allocator.classSize(cast(u32) i)
        Swag.assert(Allocator.sizeClass(sz + 1) == cast(u32) i + 1)
    }

    Swag.assert(Allocator.sizeClass(1) == 0)
    Swag.assert(Allocator.classSize(AllocatorClassCount - 1) == AllocatorMaxClassSize)

    // Anything bigger than the largest class has no class and takes the header path.
    Swag.assert(Allocator.sizeClass(AllocatorMaxClassSize + 1) == AllocatorInvalidClass)

    // Every class above the first is a multiple of 16, which is what lets the page path
    // satisfy a 16-byte alignment with no extra work.
    for i in 1 until AllocatorClassCount do
        Swag.assert(Allocator.classSize(cast(u32) i) % 16 == 0)

    // Splitting each power of two into four bounds the step at a fifth of the class it lands in,
    // which is the most of a block a request can leave unused.
    for i in 9 until AllocatorClassCount
    {
        let sz     = Allocator.classSize(cast(u32) i)
        let prevSz = Allocator.classSize(cast(u32) i - 1)
        Swag.assert(sz - prevSz <= sz / 5)
    }
}

// ----------------------------------------------------------------------------
// Small blocks are carved from segment pages. A large live set must not turn
// into one operating-system region per block.
// ----------------------------------------------------------------------------
#test
{
    var alloc: Allocator
    let itf = makeAllocator(&alloc)

    const Count = 40_000
    var addresses: [Count] #null *void
    for i in Count
    {
        addresses[i] = allocOne(itf, 32)
        Swag.assert(addresses[i] != null)
    }

    let live = alloc.stats()
    Swag.assert(live.countAlloc == Count)
    Swag.assert(live.sizeAlloc == Count * 32)
    Swag.assert(live.countPage < 64)
    Swag.assert(live.countSegment <= 2)

    for i in Count do
        freeOne(itf, addresses[i])

    Swag.assert(alloc.stats().countAlloc == 0)

    alloc.releaseAll()
    let after = alloc.stats()
    Swag.assert(after.countPage == 0)
    Swag.assert(after.countSegment == 0)
}

// ----------------------------------------------------------------------------
// memAlign() rounds up to the requested power-of-two, defaulting to pointer
// size when the alignment is 0.
// ----------------------------------------------------------------------------
#test
{
    Swag.assert(Allocator.memAlign(0, 8) == 0)
    Swag.assert(Allocator.memAlign(1, 8) == 8)
    Swag.assert(Allocator.memAlign(8, 8) == 8)
    Swag.assert(Allocator.memAlign(9, 8) == 16)
    Swag.assert(Allocator.memAlign(13, 16) == 16)
    Swag.assert(Allocator.memAlign(16, 16) == 16)
    Swag.assert(Allocator.memAlign(17, 16) == 32)
    Swag.assert(Allocator.memAlign(100, 64) == 128)
    Swag.assert(Allocator.memAlign(1, 0) == cast(u64) #sizeof(*void))
}

// ----------------------------------------------------------------------------
// One block in every size class: the page recovered from the address must carry
// the class the request mapped to, and the block must start where the page says.
// ----------------------------------------------------------------------------
#test
{
    var alloc: Allocator
    let itf = makeAllocator(&alloc)

    for i in AllocatorClassCount
    {
        let expected = Allocator.classSize(cast(u32) i)
        let address  = allocOne(itf, expected)
        Swag.assert(address != null)
        Swag.assert(cast(u64) address % 16 == 0 or i == 0)

        let page = allocatorPageOf(cast(u64) address!)!
        Swag.assert(page.classIndex == cast(u32) i)
        Swag.assert(page.blockSize == expected)
        Swag.assert(page.isBlockAddress(cast(u64) address!))
        Swag.assert(page.state == AllocatorPageState.Owned)

        // Medium classes take a page eight units wide so that they still hold several blocks.
        let expectedShift = i >= AllocatorMediumFirstClass ? AllocatorMediumUnitShift : AllocatorSmallUnitShift
        Swag.assert(allocatorSegmentOf(page).unitShift == expectedShift)
        Swag.assert(page.capacityBytes() / page.blockSize >= 4)

        freeOne(itf, address)
    }

    alloc.releaseAll()
}

// ----------------------------------------------------------------------------
// A block bigger than any class takes the header path: no page carries it, and
// freeing it hands its memory straight back to the operating system.
// ----------------------------------------------------------------------------
#test
{
    var alloc: Allocator
    let itf = makeAllocator(&alloc)

    let big     = AllocatorMaxClassSize + 4096
    let address = allocOne(itf, big)
    Swag.assert(address != null)
    Swag.assert(allocatorPageOf(cast(u64) address!) == null)

    let header = cast(*AllocatorHeader) (cast([*] u8) address! - #sizeof(AllocatorHeader))
    Swag.assert(header.blockSize == big)
    Swag.assert(header.magic == Allocator.MagicAlloc)
    Swag.assert(alloc.stats().countAlloc == 1)

    freeOne(itf, address)
    let after = alloc.stats()
    Swag.assert(after.countAlloc == 0)
    Swag.assert(after.countPage == 0)
    Swag.assert(after.sizeCached == 0)

    alloc.releaseAll()
}

// ----------------------------------------------------------------------------
// An interior pointer is not a block start, which is what the free path checks
// before it touches any list.
// ----------------------------------------------------------------------------
#test
{
    var alloc: Allocator
    let itf = makeAllocator(&alloc)

    let address = allocOne(itf, 64)!
    let page    = allocatorPageOf(cast(u64) address)!
    Swag.assert(page.isBlockAddress(cast(u64) address))
    Swag.assert(!page.isBlockAddress(cast(u64) address + 1))
    Swag.assert(!page.isBlockAddress(cast(u64) address + 8))
    Swag.assert(!page.isBlockAddress(cast(u64) address + page.blockSize - 8))
    Swag.assert(page.isBlockAddress(cast(u64) address + page.blockSize))
    Swag.assert(!page.isBlockAddress(page.areaStart - 8))
    Swag.assert(!page.isBlockAddress(page.areaEnd))

    freeOne(itf, address)
    alloc.releaseAll()
}

// ----------------------------------------------------------------------------
// A block that came back is still a block of its page, so recognizing it as free
// takes the free lists rather than the address alone.
// ----------------------------------------------------------------------------
#test
{
    var alloc: Allocator
    let itf = makeAllocator(&alloc)

    let live = allocOne(itf, 96)!
    let gone = allocOne(itf, 96)!
    let page = allocatorPageOf(cast(u64) live)!

    Swag.assert(!page.holdsFreeBlock(cast(u64) live))
    Swag.assert(!page.holdsFreeBlock(cast(u64) gone))

    freeOne(itf, gone)
    Swag.assert(page.holdsFreeBlock(cast(u64) gone))
    Swag.assert(!page.holdsFreeBlock(cast(u64) live))
    Swag.assert(page.isBlockAddress(cast(u64) gone))

    // Handing it back out takes it off the list again.
    let again = allocOne(itf, 96)!
    Swag.assert(again == gone)
    Swag.assert(!page.holdsFreeBlock(cast(u64) again))

    freeOne(itf, live)
    freeOne(itf, again)
    alloc.releaseAll()
}

// ----------------------------------------------------------------------------
// A freed block's first word holds an obfuscated link, never the raw address of
// the next free block: a stray write cannot aim the free list at chosen memory.
// ----------------------------------------------------------------------------
#test
{
    var alloc: Allocator
    let itf = makeAllocator(&alloc)

    let first  = allocOne(itf, 64)!
    let second = allocOne(itf, 64)!
    let page   = allocatorPageOf(cast(u64) first)!
    Swag.assert(page.key % 2 == 1)

    freeOne(itf, first)
    freeOne(itf, second)

    // 'second' is now the head and its stored link must decode to 'first'.
    Swag.assert(page.decode(page.freeList) == cast(u64) second)
    let storedLink = second[as u64]
    Swag.assert(storedLink != cast(u64) first)
    Swag.assert(page.decode(storedLink) == cast(u64) first)

    alloc.releaseAll()
}

// ----------------------------------------------------------------------------
// trim() gives idle pages and the segments left without one back, while the page
// the fast path is serving from stays so a hot loop never calls the kernel.
// ----------------------------------------------------------------------------
#test
{
    var alloc: Allocator
    let itf = makeAllocator(&alloc)

    const Count = 8192
    var addresses: [Count] #null *void
    for i in Count
    {
        addresses[i] = allocOne(itf, 64)
        Swag.assert(addresses[i] != null)
    }

    let live = alloc.stats()
    Swag.assert(live.countPage >= 8)

    for i in Count do
        freeOne(itf, addresses[i])

    alloc.trim()
    let trimmed = alloc.stats()
    Swag.assert(trimmed.countAlloc == 0)
    Swag.assert(trimmed.countPage <= 1)

    alloc.releaseAll()
    Swag.assert(alloc.stats().countSegment == 0)
}

// ----------------------------------------------------------------------------
// The diagnostic quarantine keeps freed blocks so a later double free is
// reported, and stays inside its byte budget.
// ----------------------------------------------------------------------------
#test
{
    var alloc: Allocator
    let itf = makeAllocator(&alloc, trackAllocations: true)
    alloc.maxQuarantineBytes = 32 * 1024

    const Count = 64
    var addresses: [Count] #null *void
    for i in Count
    {
        addresses[i] = allocOne(itf, 128)
        Swag.assert(addresses[i] != null)
    }

    for i in Count do
        freeOne(itf, addresses[i])

    Swag.assert(alloc.quarantineBytes <= alloc.maxQuarantineBytes)
    Swag.assert(alloc.firstQuarantine != null)
    alloc.checkAllMemory()
    alloc.releaseAll()
    Swag.assert(alloc.firstQuarantine == null)
}

// ----------------------------------------------------------------------------
// A freed block comes back for the next request of the same class, which is what
// makes an allocate/free loop stay on one page.
// ----------------------------------------------------------------------------
#test
{
    var alloc: Allocator
    let itf = makeAllocator(&alloc)

    let first = allocOne(itf, 100)
    Swag.assert(first != null)
    freeOne(itf, first)

    // 110 lands in the same class as 100, so the block is handed straight back.
    let second = allocOne(itf, 110)
    Swag.assert(second == first)

    freeOne(itf, second)
    alloc.releaseAll()
}

// ----------------------------------------------------------------------------
// reallocate(): a null address behaves like an allocation, a request that still
// fits its class keeps its address, and a stronger alignment forces a move.
// ----------------------------------------------------------------------------
#test
{
    var alloc: Allocator
    let itf = makeAllocator(&alloc)

    var req: AllocatorRequest
    req.address = null
    req.size    = 64
    itf.realloc(&req)
    Swag.assert(req.address != null)

    let p = cast([*] u8) req.address!
    for i in 64 do
        p[i] = cast(u8) (i + 1)

    // 64 and 80 share no class, but 60 and 64 do, so only the second call moves.
    let stable = req.address
    req.size = 60
    itf.realloc(&req)
    Swag.assert(req.address == stable)

    req.size      = 64
    req.alignment = 128
    itf.realloc(&req)
    Swag.assert(req.address != null)
    Swag.assert(cast(u64) req.address % 128 == 0)

    let moved = cast([*] u8) req.address!
    for i in 60 do
        Swag.assert(moved[i] == cast(u8) (i + 1))

    itf.free(&req)
    alloc.releaseAll()
}

// ----------------------------------------------------------------------------
// A growing buffer that outgrows its class keeps its contents across the move.
// ----------------------------------------------------------------------------
#test
{
    var alloc: Allocator
    let itf = makeAllocator(&alloc)

    var req: AllocatorRequest
    req.size = 24
    itf.alloc(&req)
    Swag.assert(req.address != null)

    let seed = cast([*] u8) req.address!
    for i in 24 do
        seed[i] = cast(u8) (i * 3 + 7)

    var size = 24'u64
    while size < 300_000
    {
        size     *= 3
        req.size = size
        itf.realloc(&req)
        Swag.assert(req.address != null)

        let grown = cast([*] u8) req.address!
        for i in 24 do
            Swag.assert(grown[i] == cast(u8) (i * 3 + 7))
    }

    itf.free(&req)
    alloc.releaseAll()
}

// ----------------------------------------------------------------------------
// AssertIsAllocated on a null address is a no-op (must not panic).
// ----------------------------------------------------------------------------
#test
{
    var alloc: Allocator
    let itf = makeAllocator(&alloc, trackAllocations: true)

    var req: AllocatorRequest
    req.address = null
    itf.assertAllocated(&req)

    alloc.releaseAll()
}

// ----------------------------------------------------------------------------
// freeAll() gives every page and every segment back.
// ----------------------------------------------------------------------------
#test
{
    var alloc: Allocator
    let itf = makeAllocator(&alloc)

    var addresses: [16] #null *void
    for i in 16
    {
        addresses[i] = allocOne(itf, 48)
        Swag.assert(addresses[i] != null)
    }
    for i in 16 do
        freeOne(itf, addresses[i])

    let cached = alloc.stats()
    Swag.assert(cached.countFree > 0)
    Swag.assert(cached.sizeCached > 0)

    var freeAll: AllocatorRequest
    itf.freeAll(&freeAll)

    let after = alloc.stats()
    Swag.assert(after.countAlloc == 0)
    Swag.assert(after.countFree == 0)
    Swag.assert(after.sizeCached == 0)
    Swag.assert(after.sizeAlloc == 0)
    Swag.assert(after.countSegment == 0)
}

#static if #os == Swag.TargetOs.Windows
{
    namespace Th
    {
        alias HANDLE                 = *void
        alias DWORD                  = u32
        alias SIZE_T                 = u64
        alias LPTHREAD_START_ROUTINE = func(*void)->DWORD

        const INFINITE = 0xFFFF_FFFF'u32

        #[Swag.Foreign("kernel32", callconv: Swag.CallConv.C)]
        {
            func CreateThread(lpThreadAttributes: #null *void, dwStackSize: SIZE_T, lpStartAddress: LPTHREAD_START_ROUTINE, lpParameter: *void, dwCreationFlags: DWORD, lpThreadId: *DWORD)->HANDLE
            func WaitForSingleObject(hHandle: HANDLE, dwMilliseconds: DWORD)->DWORD
            func CloseHandle(handle: HANDLE)
        }
    }

    struct AllocRetirePayload
    {
        allocator: IAllocator
        out:       *#null *void
        size:      u64
        done:      *s32
    }

    const FullPageRetireCount = 15

    struct FullPageRetirePayload
    {
        allocator: IAllocator
        out:       *[FullPageRetireCount] #null *void
    }

    // Allocates a block, then gives this thread's heap back while the block is still live, so the
    // page it came from is left abandoned rather than released.
    func allocAndRetireThread(param: *void)->Th.DWORD
    {
        let p = cast(*AllocRetirePayload) param

        var req: AllocatorRequest
        req.size = p.size
        p.allocator.alloc(&req)
        p.out[] = req.address

        releaseAllocatorThreadCache()
        Swag.atomadd(p.done, 1)
        return 0
    }

    // Fills two medium pages before retiring their owner. The first page shares its first unit
    // with the segment header and holds seven 64 KiB blocks; the second holds eight.
    func fillPagesAndRetireThread(param: *void)->Th.DWORD
    {
        let p = cast(*FullPageRetirePayload) param
        for i in FullPageRetireCount do
            p.out[][i] = allocOne(p.allocator, AllocatorMaxClassSize)

        releaseAllocatorThreadCache()
        return 0
    }

    // A block whose owning heap is gone must still be freeable from another thread. The page
    // outlives every heap that ever owned it, which is what makes that safe with no reference
    // count on the heap at all.
    #test
    {
        var alloc: Allocator
        let itf = makeAllocator(&alloc)

        var blockAddr: #null *void        = null
        var done:      s32                = 0
        var payload:   AllocRetirePayload
        payload.allocator = itf
        payload.out       = &blockAddr
        payload.size      = 64
        payload.done      = &done

        var tid: Th.DWORD
        let h = Th.CreateThread(null, 0, &allocAndRetireThread, &payload, 0, &tid)
        Swag.assert(h != null)
        discard Th.WaitForSingleObject(h, Th.INFINITE)
        Th.CloseHandle(h)

        Swag.assert(Swag.atomcmpxchg(&done, 0, 0) == 1)
        Swag.assert(blockAddr != null)
        Swag.assert(alloc.stats().countAlloc == 1)
        Swag.assert(alloc.firstAbandoned != null)

        let page = allocatorPageOf(cast(u64) blockAddr!)!
        Swag.assert(page.state == AllocatorPageState.Abandoned)
        Swag.assert(page.ownerHeap == null)

        freeOne(itf, blockAddr)
        Swag.assert(alloc.stats().countAlloc == 0)

        // The page is only known to be empty once someone collects what was freed remotely.
        alloc.trim()
        Swag.assert(alloc.firstAbandoned == null)
        Swag.assert(alloc.stats().countPage == 0)

        alloc.releaseAll()
    }

    // An abandoned page that still holds live blocks is adopted by the next thread that needs one
    // of its class, instead of being stranded until the allocator goes away.
    #test
    {
        var alloc: Allocator
        let itf = makeAllocator(&alloc)

        var blockAddr: #null *void        = null
        var done:      s32                = 0
        var payload:   AllocRetirePayload
        payload.allocator = itf
        payload.out       = &blockAddr
        payload.size      = 64
        payload.done      = &done

        var tid: Th.DWORD
        let h = Th.CreateThread(null, 0, &allocAndRetireThread, &payload, 0, &tid)
        discard Th.WaitForSingleObject(h, Th.INFINITE)
        Th.CloseHandle(h)
        Swag.assert(blockAddr != null)
        Swag.assert(alloc.firstAbandoned != null)

        let abandoned = allocatorPageOf(cast(u64) blockAddr!)!
        let adopted   = allocOne(itf, 64)!
        Swag.assert(allocatorPageOf(cast(u64) adopted) == abandoned)
        Swag.assert(abandoned.state == AllocatorPageState.Owned)
        Swag.assert(alloc.firstAbandoned == null)

        freeOne(itf, blockAddr)
        freeOne(itf, adopted)
        alloc.releaseAll()
    }

    // A completely full abandoned page is retained for its live blocks but cannot satisfy the
    // allocation that found it. Adoption continues until a page with room is available.
    #test
    {
        var alloc: Allocator
        let itf = makeAllocator(&alloc)

        var addresses: [FullPageRetireCount] #null *void
        var payload:   FullPageRetirePayload
        payload.allocator = itf
        payload.out       = &addresses

        var tid: Th.DWORD
        let h = Th.CreateThread(null, 0, &fillPagesAndRetireThread, &payload, 0, &tid)
        Swag.assert(h != null)
        discard Th.WaitForSingleObject(h, Th.INFINITE)
        Th.CloseHandle(h)

        for address in addresses do
            Swag.assert(address != null)
        Swag.assert(alloc.stats().countAlloc == FullPageRetireCount)
        Swag.assert(alloc.firstAbandoned != null)

        let extra = allocOne(itf, AllocatorMaxClassSize)
        Swag.assert(extra != null)
        Swag.assert(alloc.stats().countAlloc == FullPageRetireCount + 1)

        for address in addresses do
            freeOne(itf, address)
        freeOne(itf, extra)
        alloc.releaseAll()
    }

    const PageThreadCount      = 4
    const PageThreadAllocCount = 512

    struct PageThreadShared
    {
        itf:   #null IAllocator
        ready: s32
        start: s32
    }

    func pageThread(param: *void)->Th.DWORD
    {
        let shared = cast(*PageThreadShared) param
        let itf    = shared.itf!
        var addresses: [PageThreadAllocCount] #null *void

        Swag.atomadd(&shared.ready, 1)
        while Swag.atomcmpxchg(&shared.start, 0, 0) == 0 {}

        for i in PageThreadAllocCount
        {
            addresses[i] = allocOne(itf, 32)
            Swag.assert(addresses[i] != null)
        }

        for i in PageThreadAllocCount do
            freeOne(itf, addresses[i])

        // Deliberately omit releaseAllocatorThreadCache(): the FLS destructor
        // must retire this heap when the foreign OS thread exits.
        return 0
    }

    // Concurrent foreign threads keep independent heaps, carve from shared segments, and give
    // everything back through the FLS destructor when they exit.
    #test
    {
        var alloc:  Allocator
        var shared: PageThreadShared
        let itf = makeAllocator(&alloc)
        shared.itf = itf

        var handles: [PageThreadCount] #null Th.HANDLE = cast(#null Th.HANDLE) null
        for i in PageThreadCount
        {
            var tid: Th.DWORD
            handles[i] = Th.CreateThread(null, 0, &pageThread, &shared, 0, &tid)
            Swag.assert(handles[i] != null)
        }

        while Swag.atomcmpxchg(&shared.ready, 0, 0) != PageThreadCount {}
        discard Swag.atomxchg(&shared.start, 1)

        for i in PageThreadCount
        {
            discard Th.WaitForSingleObject(handles[i]!, Th.INFINITE)
            Th.CloseHandle(handles[i]!)
        }

        let after = alloc.stats()
        Swag.assert(after.countAlloc == 0)
        Swag.assert(after.countPage == 0)
        Swag.assert(after.countSegment <= 2)
        Swag.assert(alloc.firstAbandoned == null)

        alloc.releaseAll()
        Swag.assert(alloc.stats().countSegment == 0)
    }

    const StressCount = 32

    struct StressShared
    {
        itf:       #null IAllocator
        alloc:     #null *Allocator
        slots:     [StressCount] #null *void
        index:     s32
        freerDone: s32
    }

    func stressAllocRetireThread(param: *void)->Th.DWORD
    {
        let s    = cast(*StressShared) param
        let slot = Swag.atomadd(&s.index, 1)

        s.slots[slot] = allocOne(s.itf!, 64)

        releaseAllocatorThreadCache()
        return 0
    }

    func stressFreerThread(param: *void)->Th.DWORD
    {
        let s = cast(*StressShared) param
        for i in StressCount do
            freeOne(s.itf!, s.slots[i])
        Swag.atomadd(&s.freerDone, 1)
        return 0
    }

    func stressTrimThread(param: *void)->Th.DWORD
    {
        let s = cast(*StressShared) param
        while Swag.atomcmpxchg(&s.freerDone, 0, 0) == 0 do
            s.alloc!.trim()
        return 0
    }

    // Concurrency stress: many threads allocate and then abandon their pages, one thread frees
    // every block remotely, and another sweeps the abandoned list at the same time. Both sides
    // only ever touch page metadata, which no heap owns and nothing frees while blocks are live.
    #test
    {
        if Swag.jit() do
            return

        var alloc: Allocator
        let itf = makeAllocator(&alloc)

        var shared: StressShared
        shared.itf   = itf
        shared.alloc = &alloc

        var handles: [StressCount] #null Th.HANDLE = cast(#null Th.HANDLE) null
        for i in StressCount
        {
            var tid: Th.DWORD
            handles[i] = Th.CreateThread(null, 0, &stressAllocRetireThread, &shared, 0, &tid)
            Swag.assert(handles[i] != null)
        }
        for i in StressCount
        {
            discard Th.WaitForSingleObject(handles[i]!, Th.INFINITE)
            Th.CloseHandle(handles[i]!)
        }
        Swag.assert(alloc.stats().countAlloc == StressCount)

        var freerTid: Th.DWORD
        var trimTid:  Th.DWORD
        let freer = Th.CreateThread(null, 0, &stressFreerThread, &shared, 0, &freerTid)
        let trim  = Th.CreateThread(null, 0, &stressTrimThread, &shared, 0, &trimTid)
        Swag.assert(freer != null)
        Swag.assert(trim != null)

        discard Th.WaitForSingleObject(freer, Th.INFINITE)
        discard Th.WaitForSingleObject(trim, Th.INFINITE)
        Th.CloseHandle(freer)
        Th.CloseHandle(trim)

        alloc.trim()
        Swag.assert(alloc.stats().countAlloc == 0)
        Swag.assert(alloc.firstAbandoned == null)

        alloc.releaseAll()
    }
}
