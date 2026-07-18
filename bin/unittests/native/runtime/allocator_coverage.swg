#global private

using Swag

func makeAllocator(alloc: *Allocator, electricMode: bool = false, detectLeaks: bool = false, captureStack: bool = false, trackAllocations: bool = false, fillMemory: bool = false)->IAllocator
{
    alloc.setup()
    alloc.configure(electricMode, detectLeaks, captureStack, trackAllocations, fillMemory)
    return @mkinterface(alloc, #typeof(dref alloc), IAllocator)
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

    // Anything bigger than the largest class has no class (handled raw).
    let biggest = Allocator.classSize(AllocatorClassCount - 1)
    @assert(Allocator.sizeClass(biggest + 1) == AllocatorInvalidClass)
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
// Allocate one block in every size class and check the header is shaped as
// expected (class index, block size, natural alignment).
// ----------------------------------------------------------------------------
#test
{
    var alloc: Allocator
    let itf = makeAllocator(&alloc)

    for i in AllocatorClassCount
    {
        let expected = Allocator.classSize(cast(u32) i)

        var req: AllocatorRequest
        req.size = expected
        itf.alloc(&req)
        @assert(req.address != null)
        @assert(cast(u64) req.address % cast(u64) #sizeof(*void) == 0)

        let header = cast(*AllocatorHeader) (cast([*] u8) req.address - #sizeof(AllocatorHeader))
        @assert(header.classIndex == cast(u32) i)
        @assert(header.blockSize == expected)

        req.size = expected
        itf.free(&req)
        @assert(req.address == null)
    }

    alloc.releaseAll()
}

// ----------------------------------------------------------------------------
// A block too big for any class is uncached: it carries the invalid class and
// is returned straight to the OS on free (never parked in the cache).
// ----------------------------------------------------------------------------
#test
{
    var alloc: Allocator
    let itf = makeAllocator(&alloc)

    let big = Allocator.classSize(AllocatorClassCount - 1) + 4096

    var req: AllocatorRequest
    req.size = big
    itf.alloc(&req)
    @assert(req.address != null)

    let header = cast(*AllocatorHeader) (cast([*] u8) req.address - #sizeof(AllocatorHeader))
    @assert(header.classIndex == AllocatorInvalidClass)
    @assert(header.blockSize == big)

    req.size = big
    itf.free(&req)
    @assert(req.address == null)
    @assert(alloc.countFree == 0)
    @assert(alloc.sizeCached == 0)

    alloc.releaseAll()
}

// ----------------------------------------------------------------------------
// trimThreadHeap(): with a small per-heap cache budget, freeing many blocks
// keeps the thread-local cache bounded (excess goes back to the OS).
// ----------------------------------------------------------------------------
#test
{
    var alloc: Allocator
    let itf = makeAllocator(&alloc)
    alloc.maxCachedBytes = 4096

    const Count = 128
    var reqs: [Count] AllocatorRequest
    for i in Count
    {
        reqs[i].size = 64
        itf.alloc(&reqs[i])
        @assert(reqs[i].address != null)
    }
    for i in Count
    {
        reqs[i].size = 64
        itf.free(&reqs[i])
    }

    // 128 * 64 = 8192 bytes freed, but the cache is trimmed to the budget.
    @assert(alloc.sizeCached <= alloc.maxCachedBytes + 64)

    alloc.releaseAll()
    @assert(alloc.sizeCached == 0)
}

// ----------------------------------------------------------------------------
// Diagnostic trim(): in tracking mode, free memory is bounded by maxFreeSize;
// the oldest blocks are released back to the OS.
// ----------------------------------------------------------------------------
#test
{
    var alloc: Allocator
    let itf = makeAllocator(&alloc, trackAllocations: true)
    alloc.maxFreeSize   = 2048
    alloc.maxCachedBytes = 1024

    const Count = 64
    var reqs: [Count] AllocatorRequest
    for i in Count
    {
        reqs[i].size = 128
        itf.alloc(&reqs[i])
        @assert(reqs[i].address != null)
    }
    for i in Count
    {
        reqs[i].size = 128
        itf.free(&reqs[i])
    }

    @assert(alloc.sizeFree <= alloc.maxFreeSize + 128)
    alloc.checkAllMemory()
    alloc.releaseAll()
}

// ----------------------------------------------------------------------------
// Diagnostic cached reuse: a freed block of a class is handed back out for the
// next same-class allocation (acquireCached + unlinkFree cached branch).
// ----------------------------------------------------------------------------
#test
{
    var alloc: Allocator
    let itf = makeAllocator(&alloc, trackAllocations: true)

    var a: AllocatorRequest
    a.size = 100
    itf.alloc(&a)
    let addr = a.address
    @assert(addr != null)

    a.size = 100
    itf.free(&a)
    @assert(alloc.countFree == 1)
    @assert(alloc.sizeCached > 0)

    // 110 lands in the same class (<= 128) and reuses the cached header.
    var b: AllocatorRequest
    b.size = 110
    itf.alloc(&b)
    @assert(b.address == addr)
    @assert(alloc.countFree == 0)
    @assert(alloc.sizeCached == 0)

    b.size = 110
    itf.free(&b)
    alloc.releaseAll()
}

// ----------------------------------------------------------------------------
// reallocate(): a null address behaves like an allocation, and a request for a
// stronger alignment than was granted forces a move (data preserved).
// ----------------------------------------------------------------------------
#test
{
    var alloc: Allocator
    let itf = makeAllocator(&alloc)

    var req: AllocatorRequest
    req.address = null
    req.size = 64
    itf.realloc(&req)
    @assert(req.address != null)

    let p = cast([*] u8) req.address
    for i in 64 do
        p[i] = cast(u8) (i + 1)

    req.oldSize = 64
    req.size = 64
    req.alignment = 128
    itf.realloc(&req)
    @assert(req.address != null)
    @assert(cast(u64) req.address % 128 == 0)

    let moved = cast([*] u8) req.address
    for i in 64 do
        @assert(moved[i] == cast(u8) (i + 1))

    req.size = 64
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
// freeAll() on the fast path drains the thread cache and balances every OS
// allocation with a matching OS free.
// ----------------------------------------------------------------------------
#test
{
    var alloc: Allocator
    let itf = makeAllocator(&alloc)

    var reqs: [16] AllocatorRequest
    for i in 16
    {
        reqs[i].size = 48
        itf.alloc(&reqs[i])
        @assert(reqs[i].address != null)
    }
    for i in 16
    {
        reqs[i].size = 48
        itf.free(&reqs[i])
    }
    @assert(alloc.countFree > 0)
    @assert(alloc.sizeCached > 0)

    alloc.releaseAll()
    @assert(alloc.countAlloc == 0)
    @assert(alloc.countFree == 0)
    @assert(alloc.sizeCached == 0)
    @assert(alloc.sizeFree == 0)
    @assert(alloc.countOsFree == alloc.countOsAlloc)
    @assert(alloc.sizeOsFree == alloc.sizeOsAlloc)
}

#if #os == Swag.TargetOs.Windows
{
    namespace Th
    {
        alias HANDLE = *void
        alias DWORD  = u32
        alias SIZE_T = u64
        alias LPTHREAD_START_ROUTINE = func(*void)->DWORD

        const INFINITE = 0xFFFF_FFFF'u32

        #[Swag.Foreign("kernel32")]
        {
            func CreateThread(lpThreadAttributes: #null *void, dwStackSize: SIZE_T, lpStartAddress: LPTHREAD_START_ROUTINE, lpParameter: *void, dwCreationFlags: DWORD, lpThreadId: *DWORD)->HANDLE;
            func WaitForSingleObject(hHandle: HANDLE, dwMilliseconds: DWORD)->DWORD;
            func CloseHandle(handle: HANDLE);
        }
    }

    struct AllocRetirePayload
    {
        allocator: IAllocator
        out:       **void
        size:      u64
        done:      *s32
    }

    // Allocate a block, then retire this thread's heap while the block stays
    // live (activeCount > 0), and exit. The block is now owned by a retired heap.
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

    // Regression for the cross-thread free / heap-reclaim ordering: a block owned
    // by an already-retired heap is freed from another thread, then the heap is
    // reclaimed. decActive() must be the last touch of the owner heap, otherwise
    // the heap could be reclaimed out from under the remote free.
    #test
    {
        var alloc: Allocator
        let itf = makeAllocator(&alloc)

        var blockAddr: *void = null
        var done:      s32 = 0
        var payload:   AllocRetirePayload
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
        @assert(alloc.countAlloc == 1)
        @assert(alloc.firstRetiredHeap != null)

        var freeReq: AllocatorRequest
        freeReq.address = blockAddr
        freeReq.size    = 64
        itf.free(&freeReq)
        @assert(freeReq.address == null)
        @assert(alloc.countAlloc == 0)

        alloc.releaseRetiredHeaps()
        @assert(alloc.firstRetiredHeap == null)

        alloc.releaseAll()
    }

    const StressCount = 32

    struct StressShared
    {
        itf:       IAllocator
        alloc:     *Allocator
        slots:     [StressCount] *void
        index:     s32
        freerDone: s32
    }

    func stressAllocRetireThread(param: *void)->Th.DWORD
    {
        let s = cast(*StressShared) param
        let slot = @atomadd(&s.index, 1)

        var req: AllocatorRequest
        req.size = 64
        s.itf.alloc(&req)
        s.slots[slot] = req.address

        releaseAllocatorThreadCache()
        return 0
    }

    func stressFreerThread(param: *void)->Th.DWORD
    {
        let s = cast(*StressShared) param
        for i in StressCount
        {
            var req: AllocatorRequest
            req.address = s.slots[i]
            req.size    = 64
            s.itf.free(&req)
        }
        @atomadd(&s.freerDone, 1)
        return 0
    }

    func stressReclaimThread(param: *void)->Th.DWORD
    {
        let s = cast(*StressShared) param
        while @atomcmpxchg(&s.freerDone, 0, 0) == 0 do
            s.alloc.releaseRetiredHeaps()
        return 0
    }

    // Concurrency stress: many threads allocate then retire their heaps (joined,
    // so no retire races a reclaim). Then one thread frees every block remotely
    // while another concurrently reclaims retired heaps. This is the exact race
    // the decActive() ordering fix guards: a remote free touching an owner heap
    // that the reclaimer may be freeing.
    #test
    {
        if @jit() do
            return

        var alloc: Allocator
        let itf = makeAllocator(&alloc)

        var shared: StressShared
        shared.itf   = itf
        shared.alloc = &alloc

        var handles: [StressCount] Th.HANDLE
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
        @assert(alloc.countAlloc == StressCount)

        var freerTid:   Th.DWORD
        var reclaimTid: Th.DWORD
        let freer   = Th.CreateThread(null, 0, &stressFreerThread, &shared, 0, &freerTid)
        let reclaim = Th.CreateThread(null, 0, &stressReclaimThread, &shared, 0, &reclaimTid)
        @assert(freer != null)
        @assert(reclaim != null)

        discard Th.WaitForSingleObject(freer, Th.INFINITE)
        discard Th.WaitForSingleObject(reclaim, Th.INFINITE)
        Th.CloseHandle(freer)
        Th.CloseHandle(reclaim)

        @assert(alloc.countAlloc == 0)
        alloc.releaseRetiredHeaps()
        @assert(alloc.firstRetiredHeap == null)

        alloc.releaseAll()
    }
}