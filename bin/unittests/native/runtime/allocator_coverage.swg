#global private

using Swag

func makeAllocator(alloc: *Allocator, electricMode: bool = false, detectLeaks: bool = false, captureStack: bool = false, trackAllocations: bool = false, fillMemory: bool = false)->IAllocator
{
    alloc.setup()
    alloc.configure(electricMode, detectLeaks, captureStack, trackAllocations, fillMemory)
    return @mkinterface(alloc, #typeof(dref alloc), IAllocator)
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
        @assert(sz > prev)
        prev = sz

        // The exact class size maps back to that class...
        @assert(Allocator.sizeClass(sz) == cast(u32) i)
    }

    // ...and one byte past a class spills into the next one.
    for i in AllocatorClassCount - 1
    {
        let sz = Allocator.classSize(cast(u32) i)
        @assert(Allocator.sizeClass(sz + 1) == cast(u32) i + 1)
    }

    @assert(Allocator.sizeClass(1) == 0)
    @assert(Allocator.classSize(AllocatorClassCount - 1) == AllocatorMaxClassSize)

    // Anything bigger than the largest class has no class and takes the header path.
    @assert(Allocator.sizeClass(AllocatorMaxClassSize + 1) == AllocatorInvalidClass)

    // Every class above the first is a multiple of 16, which is what lets the page path
    // satisfy a 16-byte alignment with no extra work.
    for i in 1 until AllocatorClassCount do
        @assert(Allocator.classSize(cast(u32) i) % 16 == 0)

    // Splitting each power of two into four bounds the step at a fifth of the class it lands in,
    // which is the most of a block a request can leave unused.
    for i in 9 until AllocatorClassCount
    {
        let sz     = Allocator.classSize(cast(u32) i)
        let prevSz = Allocator.classSize(cast(u32) i - 1)
        @assert(sz - prevSz <= sz / 5)
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
        @assert(addresses[i] != null)
    }

    let live = alloc.stats()
    @assert(live.countAlloc == Count)
    @assert(live.sizeAlloc == Count * 32)
    @assert(live.countPage < 64)
    @assert(live.countSegment <= 2)

    for i in Count do
        freeOne(itf, addresses[i])

    @assert(alloc.stats().countAlloc == 0)

    alloc.releaseAll()
    let after = alloc.stats()
    @assert(after.countPage == 0)
    @assert(after.countSegment == 0)
}

// ----------------------------------------------------------------------------
// memAlign() rounds up to the requested power-of-two, defaulting to pointer
// size when the alignment is 0.
// ----------------------------------------------------------------------------
#test
{
    @assert(Allocator.memAlign(0, 8) == 0)
    @assert(Allocator.memAlign(1, 8) == 8)
    @assert(Allocator.memAlign(8, 8) == 8)
    @assert(Allocator.memAlign(9, 8) == 16)
    @assert(Allocator.memAlign(13, 16) == 16)
    @assert(Allocator.memAlign(16, 16) == 16)
    @assert(Allocator.memAlign(17, 16) == 32)
    @assert(Allocator.memAlign(100, 64) == 128)
    @assert(Allocator.memAlign(1, 0) == cast(u64) #sizeof(*void))
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
        @assert(address != null)
        @assert(cast(u64) address % 16 == 0 or i == 0)

        let page = allocatorPageOf(cast(u64) address!)!
        @assert(page.classIndex == cast(u32) i)
        @assert(page.blockSize == expected)
        @assert(page.isBlockAddress(cast(u64) address!))
        @assert(page.state == AllocatorPageState.Owned)

        // Medium classes take a page eight units wide so that they still hold several blocks.
        let expectedShift = i >= AllocatorMediumFirstClass ? AllocatorMediumUnitShift : AllocatorSmallUnitShift
        @assert(allocatorSegmentOf(page).unitShift == expectedShift)
        @assert(page.capacityBytes() / page.blockSize >= 4)

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
    @assert(address != null)
    @assert(allocatorPageOf(cast(u64) address!) == null)

    let header = cast(*AllocatorHeader) (cast([*] u8) address! - #sizeof(AllocatorHeader))
    @assert(header.blockSize == big)
    @assert(header.magic == Allocator.MagicAlloc)
    @assert(alloc.stats().countAlloc == 1)

    freeOne(itf, address)
    let after = alloc.stats()
    @assert(after.countAlloc == 0)
    @assert(after.countPage == 0)
    @assert(after.sizeCached == 0)

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
    @assert(page.isBlockAddress(cast(u64) address))
    @assert(!page.isBlockAddress(cast(u64) address + 1))
    @assert(!page.isBlockAddress(cast(u64) address + 8))
    @assert(!page.isBlockAddress(cast(u64) address + page.blockSize - 8))
    @assert(page.isBlockAddress(cast(u64) address + page.blockSize))
    @assert(!page.isBlockAddress(page.areaStart - 8))
    @assert(!page.isBlockAddress(page.areaEnd))

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

    @assert(!page.holdsFreeBlock(cast(u64) live))
    @assert(!page.holdsFreeBlock(cast(u64) gone))

    freeOne(itf, gone)
    @assert(page.holdsFreeBlock(cast(u64) gone))
    @assert(!page.holdsFreeBlock(cast(u64) live))
    @assert(page.isBlockAddress(cast(u64) gone))

    // Handing it back out takes it off the list again.
    let again = allocOne(itf, 96)!
    @assert(again == gone)
    @assert(!page.holdsFreeBlock(cast(u64) again))

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
    @assert(page.key % 2 == 1)

    freeOne(itf, first)
    freeOne(itf, second)

    // 'second' is now the head and its stored link must decode to 'first'.
    @assert(page.decode(page.freeList) == cast(u64) second)
    let storedLink = dref cast(*u64) second
    @assert(storedLink != cast(u64) first)
    @assert(page.decode(storedLink) == cast(u64) first)

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
        @assert(addresses[i] != null)
    }

    let live = alloc.stats()
    @assert(live.countPage >= 8)

    for i in Count do
        freeOne(itf, addresses[i])

    alloc.trim()
    let trimmed = alloc.stats()
    @assert(trimmed.countAlloc == 0)
    @assert(trimmed.countPage <= 1)

    alloc.releaseAll()
    @assert(alloc.stats().countSegment == 0)
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
        @assert(addresses[i] != null)
    }

    for i in Count do
        freeOne(itf, addresses[i])

    @assert(alloc.quarantineBytes <= alloc.maxQuarantineBytes)
    @assert(alloc.firstQuarantine != null)
    alloc.checkAllMemory()
    alloc.releaseAll()
    @assert(alloc.firstQuarantine == null)
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
    @assert(first != null)
    freeOne(itf, first)

    // 110 lands in the same class as 100, so the block is handed straight back.
    let second = allocOne(itf, 110)
    @assert(second == first)

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
    @assert(req.address != null)

    let p = cast([*] u8) req.address!
    for i in 64 do
        p[i] = cast(u8) (i + 1)

    // 64 and 80 share no class, but 60 and 64 do, so only the second call moves.
    let stable = req.address
    req.size = 60
    itf.realloc(&req)
    @assert(req.address == stable)

    req.size      = 64
    req.alignment = 128
    itf.realloc(&req)
    @assert(req.address != null)
    @assert(cast(u64) req.address % 128 == 0)

    let moved = cast([*] u8) req.address!
    for i in 60 do
        @assert(moved[i] == cast(u8) (i + 1))

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
    @assert(req.address != null)

    let seed = cast([*] u8) req.address!
    for i in 24 do
        seed[i] = cast(u8) (i * 3 + 7)

    var size = 24'u64
    while size < 300_000
    {
        size     *= 3
        req.size = size
        itf.realloc(&req)
        @assert(req.address != null)

        let grown = cast([*] u8) req.address!
        for i in 24 do
            @assert(grown[i] == cast(u8) (i * 3 + 7))
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
        @assert(addresses[i] != null)
    }
    for i in 16 do
        freeOne(itf, addresses[i])

    let cached = alloc.stats()
    @assert(cached.countFree > 0)
    @assert(cached.sizeCached > 0)

    var freeAll: AllocatorRequest
    itf.freeAll(&freeAll)

    let after = alloc.stats()
    @assert(after.countAlloc == 0)
    @assert(after.countFree == 0)
    @assert(after.sizeCached == 0)
    @assert(after.sizeAlloc == 0)
    @assert(after.countSegment == 0)
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

        #[Swag.Foreign("kernel32")]
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

    // Allocates a block, then gives this thread's heap back while the block is still live, so the
    // page it came from is left abandoned rather than released.
    func allocAndRetireThread(param: *void)->Th.DWORD
    {
        let p = cast(*AllocRetirePayload) param

        var req: AllocatorRequest
        req.size = p.size
        p.allocator.alloc(&req)
        dref p.out = req.address

        releaseAllocatorThreadCache()
        @atomadd(p.done, 1)
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
        var payload:   AllocRetirePayload = undefined
        payload.allocator = itf
        payload.out       = &blockAddr
        payload.size      = 64
        payload.done      = &done

        var tid: Th.DWORD
        let h = Th.CreateThread(null, 0, &allocAndRetireThread, &payload, 0, &tid)
        @assert(h != null)
        discard Th.WaitForSingleObject(h, Th.INFINITE)
        Th.CloseHandle(h)

        @assert(@atomcmpxchg(&done, 0, 0) == 1)
        @assert(blockAddr != null)
        @assert(alloc.stats().countAlloc == 1)
        @assert(alloc.firstAbandoned != null)

        let page = allocatorPageOf(cast(u64) blockAddr!)!
        @assert(page.state == AllocatorPageState.Abandoned)
        @assert(page.ownerHeap == null)

        freeOne(itf, blockAddr)
        @assert(alloc.stats().countAlloc == 0)

        // The page is only known to be empty once someone collects what was freed remotely.
        alloc.trim()
        @assert(alloc.firstAbandoned == null)
        @assert(alloc.stats().countPage == 0)

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
        var payload:   AllocRetirePayload = undefined
        payload.allocator = itf
        payload.out       = &blockAddr
        payload.size      = 64
        payload.done      = &done

        var tid: Th.DWORD
        let h = Th.CreateThread(null, 0, &allocAndRetireThread, &payload, 0, &tid)
        discard Th.WaitForSingleObject(h, Th.INFINITE)
        Th.CloseHandle(h)
        @assert(blockAddr != null)
        @assert(alloc.firstAbandoned != null)

        let abandoned = allocatorPageOf(cast(u64) blockAddr!)!
        let adopted   = allocOne(itf, 64)!
        @assert(allocatorPageOf(cast(u64) adopted) == abandoned)
        @assert(abandoned.state == AllocatorPageState.Owned)
        @assert(alloc.firstAbandoned == null)

        freeOne(itf, blockAddr)
        freeOne(itf, adopted)
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

        @atomadd(&shared.ready, 1)
        while @atomcmpxchg(&shared.start, 0, 0) == 0 {}

        for i in PageThreadAllocCount
        {
            addresses[i] = allocOne(itf, 32)
            @assert(addresses[i] != null)
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

        var handles: [PageThreadCount] Th.HANDLE = undefined
        for i in PageThreadCount
        {
            var tid: Th.DWORD
            handles[i] = Th.CreateThread(null, 0, &pageThread, &shared, 0, &tid)
            @assert(handles[i] != null)
        }

        while @atomcmpxchg(&shared.ready, 0, 0) != PageThreadCount {}
        discard @atomxchg(&shared.start, 1)

        for i in PageThreadCount
        {
            discard Th.WaitForSingleObject(handles[i], Th.INFINITE)
            Th.CloseHandle(handles[i])
        }

        let after = alloc.stats()
        @assert(after.countAlloc == 0)
        @assert(after.countPage == 0)
        @assert(after.countSegment <= 2)
        @assert(alloc.firstAbandoned == null)

        alloc.releaseAll()
        @assert(alloc.stats().countSegment == 0)
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
        let slot = @atomadd(&s.index, 1)

        s.slots[slot] = allocOne(s.itf!, 64)

        releaseAllocatorThreadCache()
        return 0
    }

    func stressFreerThread(param: *void)->Th.DWORD
    {
        let s = cast(*StressShared) param
        for i in StressCount do
            freeOne(s.itf!, s.slots[i])
        @atomadd(&s.freerDone, 1)
        return 0
    }

    func stressTrimThread(param: *void)->Th.DWORD
    {
        let s = cast(*StressShared) param
        while @atomcmpxchg(&s.freerDone, 0, 0) == 0 do
            s.alloc!.trim()
        return 0
    }

    // Concurrency stress: many threads allocate and then abandon their pages, one thread frees
    // every block remotely, and another sweeps the abandoned list at the same time. Both sides
    // only ever touch page metadata, which no heap owns and nothing frees while blocks are live.
    #test
    {
        if @jit() do
            return

        var alloc: Allocator
        let itf = makeAllocator(&alloc)

        var shared: StressShared
        shared.itf   = itf
        shared.alloc = &alloc

        var handles: [StressCount] Th.HANDLE = undefined
        for i in StressCount
        {
            var tid: Th.DWORD
            handles[i] = Th.CreateThread(null, 0, &stressAllocRetireThread, &shared, 0, &tid)
            @assert(handles[i] != null)
        }
        for i in StressCount
        {
            discard Th.WaitForSingleObject(handles[i], Th.INFINITE)
            Th.CloseHandle(handles[i])
        }
        @assert(alloc.stats().countAlloc == StressCount)

        var freerTid: Th.DWORD
        var trimTid:  Th.DWORD
        let freer = Th.CreateThread(null, 0, &stressFreerThread, &shared, 0, &freerTid)
        let trim  = Th.CreateThread(null, 0, &stressTrimThread, &shared, 0, &trimTid)
        @assert(freer != null)
        @assert(trim != null)

        discard Th.WaitForSingleObject(freer, Th.INFINITE)
        discard Th.WaitForSingleObject(trim, Th.INFINITE)
        Th.CloseHandle(freer)
        Th.CloseHandle(trim)

        alloc.trim()
        @assert(alloc.stats().countAlloc == 0)
        @assert(alloc.firstAbandoned == null)

        alloc.releaseAll()
    }
}
