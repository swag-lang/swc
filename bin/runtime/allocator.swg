#global namespace Swag

// The runtime allocator.
//
// Two paths, chosen by the request and never mixed up at free time because a block's address says
// which one produced it:
//
//   - The page path serves every request up to 64 KiB with an ordinary alignment. Blocks are carved
//     from segment pages (see allocator.pages.swg), carry no header, and are recovered on free by
//     masking the address down to its page. The whole path is free of locks and, on the owning
//     thread, free of atomics.
//   - The header path serves larger blocks, over-aligned blocks, and every allocation made while a
//     diagnostic mode is on. It keeps a header, a footer, and optional tracking, which is what
//     leak reports, electric mode, and the double-free diagnostic need.

const AllocatorClassCount   = 45'u32
const AllocatorInvalidClass = 0xFFFF_FFFF'u32

// Classes 0 to 32 are carved from 64 KiB pages, the rest from 512 KiB pages, so that every class
// holds at least eight blocks per page.
const AllocatorMediumFirstClass = 33'u32
const AllocatorMaxClassSize     = 65536'u64

// Blocks of class 1 and above are a multiple of 16 bytes and start on a 16-byte boundary, so the
// page path already satisfies any alignment up to that. Anything stricter takes the header path.
const AllocatorPagePathAlignment = 16'u32

private const AllocatorInvalidFlsId = 0xFFFF_FFFF'u64

struct AllocatorTracking
{
    loc:        SourceCodeLocation
    hint:       #null string
    stack:      [16] *void = undefined
    stackCount: u32
    allocId:    u32
}

// Carried only by header-path blocks. A page-path block has none of this: its size and owner are
// recovered from the page table.
struct AllocatorHeader
{
    allocAddr: #null [*] void
    allocSize: u64
    userSize:  u64
    blockSize: u64
    prev:      #null *AllocatorHeader
    next:      #null *AllocatorHeader
    tracking:  #null *AllocatorTracking
    alignment: u32
    isTracked: bool

    // An electric block ends flush against a reserved guard page, so it carries no footer: a write
    // one byte past the request faults instead of waiting for the free to notice a broken pattern.
    isElectric: bool
    magic:      u32
}

struct AllocatorFooter
{
    magic: u32
}

// An exact snapshot of what the allocator holds. Producing it walks the segment and heap lists, so
// the fast paths keep no counter and pay nothing for statistics that nobody is reading.
struct AllocatorStats
{
    // Blocks handed to callers and not yet returned, and the bytes their size classes reserve.
    countAlloc: u64
    sizeAlloc:  u64

    // Blocks sitting on a page free list, and the committed page bytes not currently handed out.
    countFree:  u64
    sizeCached: u64

    // Pages and segments this allocator holds.
    countPage:    u64
    countSegment: u64

    // Bytes committed from the operating system, and the calls that moved them. Both are process
    // wide, because segments are drawn from reservations shared by every allocator.
    sizeCommitted:   u64
    countOsCommit:   u64
    countOsDecommit: u64
    countOsReserve:  u64
}

struct AllocatorThreadClass
{
    // The page the fast path serves from, plus every other page this heap owns for the class.
    page:  #null *AllocatorPage
    first: #null *AllocatorPage
    last:  #null *AllocatorPage
}

struct AllocatorThreadHeap
{
    allocator: #null *void
    nextHeap:  #null *AllocatorThreadHeap
    prevHeap:  #null *AllocatorThreadHeap
    threadId:  u64
    retired:   u32
    classes:   [AllocatorClassCount] AllocatorThreadClass
}

// Fiber-local storage gives both real per-thread isolation and a destructor that runs on a thread
// the runtime never started, which is what lets an OS-owned callback thread give its pages back.
private var g_AllocatorThreadHeapFlsId = AllocatorInvalidFlsId

struct Allocator
{
    // Guards the diagnostic quarantine and the tracked-allocation list.
    mutex: MutexRW

    // Guards the segment list, the thread-heap list, and the abandoned pages.
    segmentMutex: MutexRW

    firstSegment:   #null *AllocatorSegment
    firstHeap:      #null *AllocatorThreadHeap
    firstAbandoned: #null *AllocatorPage

    // Header-path bookkeeping. Live blocks are always counted; the tracked list and the quarantine
    // exist only while a diagnostic mode is on.
    firstAlloc:      #null *AllocatorHeader
    firstQuarantine: #null *AllocatorHeader
    lastQuarantine:  #null *AllocatorHeader
    headerCount:     u64
    headerBytes:     u64
    quarantineBytes: u64
    quarantineCount: u64

    nextId:       u32
    installMagic: u32 = 0

    // Bounds the diagnostic quarantine, which holds freed blocks so a later double free or use
    // after free is reported instead of faulting on unmapped memory.
    maxQuarantineBytes: u64
    showMaxLeaks:       u32
    breakOnAllocId:     u32
    captureAllocStack:  bool
    detectLeaks:        bool
    trackAllocations:   bool
    fillAlloc:          bool
    fillFree:           bool
    electricMode:       bool
}

private var g_DefaultAllocator: Allocator

private func retireAllocatorThreadHeap(value: #null *void)
{
    if !value do
        return

    let heap      = cast(*AllocatorThreadHeap) value
    let allocator = cast(#null *Allocator) heap.allocator
    if allocator and allocator.installed() do
        allocator.retireThreadHeap(heap)
}

private func allocatorThreadHeapFlsId()->u64
{
    let id = atomicGet(&g_AllocatorThreadHeapFlsId)
    if id != AllocatorInvalidFlsId do
        return id

    let candidate = __hostThreadStorageAlloc(&retireAllocatorThreadHeap)
    @assert(candidate != 0)

    let previous = @atomcmpxchg(&g_AllocatorThreadHeapFlsId, AllocatorInvalidFlsId, candidate)
    if previous != AllocatorInvalidFlsId
    {
        __hostThreadStorageFree(candidate)
        return previous
    }

    return candidate
}

func currentAllocatorThreadHeap()->#null *AllocatorThreadHeap
{
    return cast(#null *AllocatorThreadHeap) __hostThreadStorageGet(allocatorThreadHeapFlsId())
}

private func setCurrentAllocatorThreadHeap(heap: #null *AllocatorThreadHeap)
{
    @assert(__hostThreadStorageSet(allocatorThreadHeapFlsId(), heap))
}

private func currentThreadId()->u64
{
    return __hostCurrentThreadId()
}

impl Allocator
{
    const MagicAlloc     = 0xC0DEF00D
    const MagicFree      = 0xFEE1DEAD
    const AllocByte      = 0xAB
    const FreeByte       = 0xFB
    const InstalledMagic = 0xA110CA7E

    // Class 0 is 8 bytes, classes 1 to 8 step by 16 up to 128, and every class above that splits a
    // power of two into four. The widest step is a fifth of the class it lands in, which is the
    // bound on how much of a page-path block a request can leave unused.
    func classSize(index: u32)->u64
    {
        if index == 0 do
            return 8
        if index <= 8 do
            return cast(u64) index * 16

        let bucket = 7 + (index - 9) / 4
        let step   = (index - 9) % 4
        return cast(u64) (5 + step) << (bucket - 2)
    }

    // The inverse of 'classSize', in a handful of instructions and with no table walk.
    func sizeClass(size: u64)->u32
    {
        if size <= 8 do
            return 0
        if size <= 128 do
            return cast(u32) ((size + 15) >> 4)
        if size > AllocatorMaxClassSize do
            return AllocatorInvalidClass

        let value  = size - 1
        let bucket = 63 - cast(u32) @bitcountlz(value)
        let step   = cast(u32) ((value >> (bucket - 2)) & 3)
        return 9 + (bucket - 7) * 4 + step
    }

    func classUnitShift(index: u32)->u32
    {
        return index >= AllocatorMediumFirstClass ? AllocatorMediumUnitShift : AllocatorSmallUnitShift
    }

    func memAlign(value: u64, alignment: u32)->u64
    {
        let toAlign = cast(u64) (alignment != 0 ? alignment : cast(u32) #sizeof(*void)) - 1
        return (value + toAlign) & ~toAlign
    }

    func printDisplaySize(value: u64)
    {
        var size = value
        if size < 1024
        {
            @print(size, " bytes")
            return
        }

        size /= 1024
        if size < 1024
        {
            @print(size, " Kb")
            return
        }

        size /= 1024
        if size < 1024
        {
            @print(size, " Mb")
            return
        }

        size /= 1024
        @print(size, " Gb")
    }

    mtd setup()
    {
        @init(me, 1)
        .installMagic = InstalledMagic
        .configure(false, true, false, false, false)
    }

    mtd configure(electricMode: bool, detectLeaks: bool, captureStack: bool, trackAllocations: bool, fillMemory: bool)
    {
        .maxQuarantineBytes = 16 * 1024 * 1024
        .showMaxLeaks       = 100
        .breakOnAllocId     = 0
        .captureAllocStack  = captureStack
        .detectLeaks        = detectLeaks
        .trackAllocations   = trackAllocations
        .fillAlloc          = fillMemory
        .fillFree           = fillMemory
        .electricMode       = electricMode
    }

    mtd installed()->bool
    {
        return .installMagic == InstalledMagic
    }

    mtd diagnosticMode()->bool
    {
        return .trackAllocations or .captureAllocStack or .electricMode or .breakOnAllocId != 0
    }

    // ###################################################################################
    // Operating system blocks, used by the header path and by the thread-heap records
    // ###################################################################################

    mtd osAlloc(size: u64)->#null [*] u8
    {
        let rounded = memAlign(size, cast(u32) AllocatorCommitGranularity)
        let address = __hostPageReserve(rounded)
        if !address do
            return null
        if !__hostPageCommit(address, rounded)
        {
            __hostPageRelease(address, rounded)
            return null
        }

        atomicAddU64(&g_AllocatorCommittedBytes, rounded)
        atomicAddU64(&g_AllocatorOsCommitCount, 1)
        return address
    }

    // Reserves one extra page past the block and leaves it uncommitted. Electric mode places the
    // user data flush against it, so an overflow of a single byte faults at the instruction that
    // writes it rather than at the next consistency check.
    mtd osAllocGuarded(commitBytes: u64)->#null [*] u8
    {
        let reservedBytes = commitBytes + AllocatorCommitGranularity
        let address       = __hostPageReserve(reservedBytes)
        if !address do
            return null
        if !__hostPageCommit(address, commitBytes)
        {
            __hostPageRelease(address, reservedBytes)
            return null
        }

        atomicAddU64(&g_AllocatorCommittedBytes, commitBytes)
        atomicAddU64(&g_AllocatorOsCommitCount, 1)
        return address
    }

    mtd osFree(address: #null *void, size: u64)
    {
        if !address do
            return

        __hostPageRelease(address, size)

        atomicSubU64(&g_AllocatorCommittedBytes, size)
        atomicAddU64(&g_AllocatorOsDecommitCount, 1)
    }

    // ###################################################################################
    // Thread heaps
    // ###################################################################################

    mtd allocateThreadHeap()->#null *AllocatorThreadHeap
    {
        let address = .osAlloc(#sizeof(AllocatorThreadHeap))
        if !address do
            return null

        @memset(address, 0, #sizeof(AllocatorThreadHeap))
        let heap = cast(*AllocatorThreadHeap) address
        heap.allocator = me
        heap.threadId  = currentThreadId()

        .segmentMutex.lock()
        heap.nextHeap = .firstHeap
        if .firstHeap do
            .firstHeap.prevHeap = heap
        .firstHeap = heap
        .segmentMutex.unlock()

        return heap
    }

    mtd threadHeap()->#null *AllocatorThreadHeap
    {
        // 'retired' is only ever set from the owning thread, so reading it needs no barrier here.
        let heap = currentAllocatorThreadHeap()
        if heap and heap.allocator == me and heap.retired == 0 do
            return heap

        // The slot holds another allocator's heap, which happens when a program installs a second
        // allocator on a thread that already allocated. Give the old one back before replacing it.
        if heap
        {
            setCurrentAllocatorThreadHeap(null)
            let oldAllocator = cast(#null *Allocator) heap.allocator
            if oldAllocator do
                oldAllocator.retireThreadHeap(heap)
        }

        let newHeap = .allocateThreadHeap()
        if !newHeap do
            return null

        setCurrentAllocatorThreadHeap(newHeap)
        return newHeap
    }

    // Gives every page the heap still owns back: emptied ones to their segment, the rest to the
    // abandoned list where any thread can adopt them. The page table outlives the heap, so a
    // remote free racing with this only ever lands on storage that is still mapped.
    mtd retireThreadHeap(heap: *AllocatorThreadHeap)
    {
        if @atomxchg(&heap.retired, 1) != 0 do
            return

        .segmentMutex.lock()

        for i in AllocatorClassCount
        {
            let cls  = &heap.classes[i]
            var scan = cls.first
            while scan
            {
                let next = scan.nextPage
                scan.collectRemote()
                if scan.used == 0 do
                    allocatorSegmentOf(scan).releasePage(scan)
                else
                {
                    scan.ownerHeap  = null
                    scan.state      = .Abandoned
                    scan.prevPage   = null
                    scan.nextPage   = .firstAbandoned
                    .firstAbandoned = scan
                }

                scan = next
            }

            cls.page  = null
            cls.first = null
            cls.last  = null
        }

        .unlinkHeap(heap)
        .segmentMutex.unlock()

        .osFree(heap, #sizeof(AllocatorThreadHeap))
    }

    // Unlinks a heap from the allocator's list. The caller holds the segment mutex.
    mtd unlinkHeap(heap: *AllocatorThreadHeap)
    {
        if heap.prevHeap do
            heap.prevHeap.nextHeap = heap.nextHeap
        else do
            .firstHeap = heap.nextHeap

        if heap.nextHeap do
            heap.nextHeap.prevHeap = heap.prevHeap

        heap.prevHeap = null
        heap.nextHeap = null
    }

    // ###################################################################################
    // Page path
    // ###################################################################################

    mtd linkPage(heap: *AllocatorThreadHeap, page: *AllocatorPage)
    {
        let cls = &heap.classes[page.classIndex]
        page.prevPage = cls.last
        page.nextPage = null
        if cls.last do
            cls.last.nextPage = page
        else do
            cls.first = page
        cls.last = page
    }

    mtd unlinkPage(heap: *AllocatorThreadHeap, page: *AllocatorPage)
    {
        let cls = &heap.classes[page.classIndex]
        if page.prevPage do
            page.prevPage.nextPage = page.nextPage
        else do
            cls.first = page.nextPage

        if page.nextPage do
            page.nextPage.prevPage = page.prevPage
        else do
            cls.last = page.prevPage

        if cls.page == page do
            cls.page = null
        page.prevPage = null
        page.nextPage = null
    }

    // Adopts an abandoned page of the class, or carves a new one out of a segment. The caller must
    // not hold the segment mutex.
    mtd acquirePageForClass(heap: *AllocatorThreadHeap, classIndex: u32)->#null *AllocatorPage
    {
        let blockSize = cast(u32) classSize(classIndex)
        let unitShift = classUnitShift(classIndex)

        .segmentMutex.lock()
        defer .segmentMutex.unlock()

        var prev: #null *AllocatorPage
        var scan: #null *AllocatorPage = .firstAbandoned
        while scan
        {
            let next = scan.nextPage
            if scan.classIndex == classIndex
            {
                if !prev do
                    .firstAbandoned = next
                else do
                    prev.nextPage = next

                scan.prevPage  = null
                scan.nextPage  = null
                scan.state     = .Owned
                scan.ownerHeap = heap
                scan.collectRemote()
                .linkPage(heap, scan)
                return scan
            }

            prev = scan
            scan = next
        }

        var segment: #null *AllocatorSegment = .firstSegment
        while segment
        {
            if segment.unitShift == unitShift
            {
                let page = segment.acquirePage(classIndex, blockSize)
                if page
                {
                    page.ownerHeap = heap
                    .linkPage(heap, page)
                    return page
                }
            }

            segment = segment.nextSegment
        }

        let fresh = allocatorAcquireSegment(me, unitShift)
        if !fresh do
            return null

        fresh.nextSegment = .firstSegment
        if .firstSegment do
            .firstSegment.prevSegment = fresh
        .firstSegment = fresh

        let page = fresh.acquirePage(classIndex, blockSize)
        if !page do
            return null

        page.ownerHeap = heap
        .linkPage(heap, page)
        return page
    }

    // Runs when the current page has nothing left: collects what other threads freed, then looks
    // through the heap's other pages, then asks for a new one.
    mtd acquireBlockSlow(heap: *AllocatorThreadHeap, classIndex: u32)->u64
    {
        let cls = &heap.classes[classIndex]

        if cls.page
        {
            cls.page.collectRemote()
            let block = cls.page.acquireBlock()
            if block != 0 do
                return block
        }

        var scan = cls.first
        while scan
        {
            let next = scan.nextPage
            if scan != cls.page
            {
                scan.collectRemote()
                let block = scan.acquireBlock()
                if block != 0
                {
                    cls.page = scan
                    return block
                }
            }

            scan = next
        }

        let page = .acquirePageForClass(heap, classIndex)
        if !page do
            return 0

        cls.page = page
        return page.acquireBlock()
    }

    #[Swag.Inline]
    mtd acquireBlock(heap: *AllocatorThreadHeap, classIndex: u32)->u64
    {
        let page = heap.classes[classIndex].page
        if page
        {
            let block = page.acquireBlock()
            if block != 0 do
                return block
        }

        return .acquireBlockSlow(heap, classIndex)
    }

    // Decommits a page whose last block just came back. The page the fast path is serving from is
    // kept, so an allocate/free pair on a single block never touches the operating system.
    mtd retirePage(heap: *AllocatorThreadHeap, page: *AllocatorPage)
    {
        let cls = &heap.classes[page.classIndex]
        if cls.page == page do
            return

        .unlinkPage(heap, page)
        allocatorSegmentOf(page).releasePage(page)
    }

    // ###################################################################################
    // Header path
    // ###################################################################################

    mtd headerOf(address: u64)->*AllocatorHeader
    {
        return cast(*AllocatorHeader) (address - #sizeof(AllocatorHeader))
    }

    mtd userAddress(header: *AllocatorHeader)->[*] u8
    {
        return cast([*] u8) header + #sizeof(AllocatorHeader)
    }

    mtd footer(header: *AllocatorHeader)->*AllocatorFooter
    {
        return cast(*AllocatorFooter) (.userAddress(header) + header.userSize)
    }

    // An electric block has no footer: the byte after its last one belongs to the guard page.
    mtd footerMagic(header: *AllocatorHeader)->u32
    {
        return header.isElectric ? header.magic : .footer(header).magic
    }

    mtd setFooterMagic(header: *AllocatorHeader, value: u32)
    {
        if !header.isElectric do
            .footer(header).magic = value
    }

    mtd checkFree(header: *AllocatorHeader)
    {
        if header.magic != MagicFree or .footerMagic(header) != MagicFree do
            @panic("memory block corruption", #curlocation)
    }

    mtd checkAllocated(header: *AllocatorHeader, callerLoc = #callerlocation)
    {
        let footMagic = .footerMagic(header)
        if (header.magic != MagicAlloc and header.magic != MagicFree) or
           (footMagic != MagicAlloc and footMagic != MagicFree) do
            @panic("memory block corruption", callerLoc)

        if header.magic == MagicFree
        {
            var loc      = callerLoc
            let tracking = header.tracking
            if tracking and tracking.loc.fileName do
                loc = tracking.loc
            @panic("memory block is freed twice", loc)
        }
    }

    mtd linkAllocated(header: *AllocatorHeader)
    {
        header.prev = null
        header.next = .firstAlloc
        if header.next do
            header.next.prev = header
        .firstAlloc = header
    }

    mtd unlinkAllocated(header: *AllocatorHeader)
    {
        if !header.prev do
            .firstAlloc = header.next
        else do
            header.prev.next = header.next

        if header.next do
            header.next.prev = header.prev

        header.prev = null
        header.next = null
    }

    // Holds a freed block instead of unmapping it, so that a second free or a read through the
    // stale pointer is reported rather than turned into an access violation.
    mtd quarantine(header: *AllocatorHeader)
    {
        header.prev = .lastQuarantine
        header.next = null
        if .lastQuarantine do
            .lastQuarantine.next = header
        else do
            .firstQuarantine = header
        .lastQuarantine  = header
        .quarantineBytes += header.allocSize
        .quarantineCount += 1

        // Electric mode never evicts: an address it handed out is never handed out again, so a
        // pointer kept past its free can never reach a different, live allocation.
        while !.electricMode and .firstQuarantine and .quarantineBytes > .maxQuarantineBytes
        {
            let oldest = .firstQuarantine!
            .checkFree(oldest)
            .firstQuarantine = oldest.next
            if .firstQuarantine do
                .firstQuarantine.prev = null
            else do
                .lastQuarantine = null
            @assert(.quarantineBytes >= oldest.allocSize)
            .quarantineBytes -= oldest.allocSize
            .quarantineCount -= 1
            .osFree(oldest.allocAddr, oldest.allocSize)
        }
    }

    mtd allocateHeaderBlock(request: *AllocatorRequest, classIndex: u32)
    {
        let alignment    = @max(request.alignment, AllocatorPagePathAlignment)
        let trackingSize = .diagnosticMode() ? cast(u64) #sizeof(AllocatorTracking) : 0'u64
        let prefix       = memAlign(trackingSize + #sizeof(AllocatorHeader), alignment)
        let blockSize    = classIndex == AllocatorInvalidClass ? request.size : classSize(classIndex)

        var allocSize: u64
        var base:      #null [*] u8
        var userAddr:  u64

        if .electricMode
        {
            // The request ends exactly where the committed range does, so the reserved page beyond
            // it turns the first byte of an overflow into an access violation.
            allocSize = memAlign(prefix + alignment + request.size, cast(u32) AllocatorCommitGranularity)
            base      = .osAllocGuarded(allocSize)
            if base do
                userAddr = (cast(u64) base + allocSize - request.size) & ~(cast(u64) alignment - 1)
        }
        else
        {
            allocSize = memAlign(prefix + alignment + blockSize + #sizeof(AllocatorFooter), cast(u32) AllocatorCommitGranularity)
            base      = .osAlloc(allocSize)
            if base do
                userAddr = memAlign(cast(u64) base + prefix, alignment)
        }

        if !base
        {
            request.address = null
            return
        }

        let header = .headerOf(userAddr)
        header.allocAddr  = cast([*] void) base
        header.allocSize  = allocSize
        header.userSize   = request.size
        header.blockSize  = blockSize
        header.tracking   = .diagnosticMode() ? cast(*AllocatorTracking) base : null
        header.alignment  = alignment
        header.isTracked  = .trackAllocations
        header.isElectric = .electricMode
        header.magic      = MagicAlloc
        header.prev       = null
        header.next       = null

        .setFooterMagic(header, MagicAlloc)

        if .fillAlloc do
            @memset(cast(*void) userAddr, AllocByte, request.size)

        let tracking = header.tracking
        if tracking
        {
            tracking.loc        = request.callerLoc
            tracking.hint       = request.hint
            tracking.stackCount = .captureAllocStack ? __captureStack(2, @mkslice(&tracking.stack[0], @countof(tracking.stack))) : 0
            tracking.allocId    = @atomadd(&.nextId, 1) + 1
            if tracking.allocId == .breakOnAllocId do
                @assert(false)
        }

        atomicAddU64(&.headerCount, 1)
        atomicAddU64(&.headerBytes, blockSize)
        if header.isTracked do
            .linkAllocated(header)

        request.address = cast(*void) userAddr
    }

    mtd freeHeaderBlock(address: u64, callerLoc: SourceCodeLocation)
    {
        let header = .headerOf(address)
        .checkAllocated(header, callerLoc)

        if header.isTracked do
            .unlinkAllocated(header)

        atomicSubU64(&.headerCount, 1)
        atomicSubU64(&.headerBytes, header.blockSize)

        if .fillFree do
            @memset(cast(*void) address, FreeByte, header.userSize)

        header.magic = MagicFree
        .setFooterMagic(header, MagicFree)
        if header.tracking do
            header.tracking.loc = callerLoc

        if .diagnosticMode() do
            .quarantine(header)
        else do
            .osFree(header.allocAddr, header.allocSize)
    }

    // ###################################################################################
    // Public operations
    // ###################################################################################

    // A page-path block needs no header, so a request only leaves that path when it asks for more
    // than a page can carve, for a stricter alignment, or while a diagnostic mode is recording.
    mtd usesHeaderPath(request: *AllocatorRequest, classIndex: u32)->bool
    {
        if .diagnosticMode() do
            return true
        if classIndex == AllocatorInvalidClass do
            return true
        return request.alignment > AllocatorPagePathAlignment
    }

    mtd allocate(request: *AllocatorRequest)
    {
        // A zero-size reallocation with a live address never reaches this point:
        // 'reallocate' frees it before delegating.
        if request.size == 0
        {
            request.address = null
            return
        }

        var classIndex = sizeClass(request.size)

        // The 8-byte class is the only one that is not 16-byte aligned.
        if classIndex == 0 and request.alignment > 8 do
            classIndex = 1

        if .usesHeaderPath(request, classIndex)
        {
            .allocateHeaderBlock(request, classIndex)
            return
        }

        let heap = .threadHeap()
        if !heap
        {
            request.address = null
            return
        }

        let block = .acquireBlock(heap, classIndex)
        if block == 0
        {
            request.address = null
            return
        }

        // Fill the whole block, not only the request: the page path keeps no user size, so a later
        // reallocation inside the same class must find the pattern everywhere it can now reach.
        if .fillAlloc do
            @memset(cast(*void) block, AllocByte, classSize(classIndex))

        request.address = cast(*void) block
    }

    mtd reallocate(request: *AllocatorRequest)
    {
        if !request.address
        {
            .allocate(request)
            return
        }

        if request.size == 0
        {
            .freeBlock(request)
            return
        }

        let oldAddress = cast(u64) request.address!
        let oldPage    = allocatorPageOf(oldAddress)

        var oldBlockSize: u64
        if oldPage
        {
            .checkPageAddress(oldPage, oldAddress, request.callerLoc)
            oldBlockSize = oldPage.blockSize
        }
        else
        {
            let oldHeader = .headerOf(oldAddress)
            .checkAllocated(oldHeader, request.callerLoc)
            oldBlockSize = oldHeader.blockSize

            // Growing inside the block the header already covers only moves the footer.
            if request.size <= oldHeader.blockSize and request.alignment <= oldHeader.alignment and !oldHeader.isElectric
            {
                let oldSize = oldHeader.userSize
                .setFooterMagic(oldHeader, 0)
                oldHeader.userSize = request.size
                .setFooterMagic(oldHeader, MagicAlloc)

                if .fillAlloc and oldSize < request.size do
                    @memset(.userAddress(oldHeader) + oldSize, AllocByte, request.size - oldSize)

                return
            }
        }

        // A page block keeps its address whenever the request still fits its class, which is what
        // makes a growing buffer stop calling the operating system.
        if oldPage and request.size <= oldBlockSize and request.alignment <= AllocatorPagePathAlignment and !.diagnosticMode()
        {
            request.address = cast(*void) oldAddress
            return
        }

        var allocReq = dref request
        allocReq.address = null
        .allocate(&allocReq)
        if !allocReq.address
        {
            request.address = null
            return
        }

        @memcpy(allocReq.address, cast(*void) oldAddress, @min(oldBlockSize, request.size))

        var freeReq = dref request
        freeReq.address = cast(*void) oldAddress
        .freeBlock(&freeReq)

        request.address = allocReq.address
    }

    // Rejects an address that no live block of the page starts, which covers a stale pointer, an
    // interior pointer, and a pointer into a page that has already gone back to its segment.
    mtd checkPageAddress(page: *AllocatorPage, address: u64, callerLoc: SourceCodeLocation)
    {
        if page.state == AllocatorPageState.Free do
            @panic("memory block is not allocated", callerLoc)
        if !page.isBlockAddress(address) do
            @panic("memory block address is not the start of an allocation", callerLoc)
    }

    mtd freeBlock(request: *AllocatorRequest)
    {
        if !request.address do
            return

        let address = cast(u64) request.address!
        request.address = null

        let page = allocatorPageOf(address)
        if !page
        {
            .freeHeaderBlock(address, request.callerLoc)
            return
        }

        .checkPageAddress(page, address, request.callerLoc)

        if .fillFree do
            @memset(cast(*void) address, FreeByte, page.blockSize)

        // Only the owning thread may touch the page's own free list; anyone else hands the block
        // over through the page's atomic list, which the owner drains when it runs dry.
        let heap = currentAllocatorThreadHeap()
        if heap and page.ownerHeap == heap
        {
            if page.freeList == page.encode(address) do
                @panic("memory block is freed twice", request.callerLoc)

            page.releaseBlock(address)
            if page.used == 0 do
                .retirePage(heap, page)
        }
        else do
            page.pushRemote(address)
    }

    mtd assertIsAllocated(addr: #null *void, callerLoc = #callerlocation)
    {
        if !addr do
            return

        let address = cast(u64) addr!
        let page    = allocatorPageOf(address)
        if page
        {
            .checkPageAddress(page, address, callerLoc)

            // Being a block of the page is not enough: a freed block still looks like one. Walking
            // the free list is what separates the two, and only a caller that asked for the check
            // pays for it.
            if page.holdsFreeBlock(address) do
                @panic("memory block is not allocated", callerLoc)
            return
        }

        .checkAllocated(.headerOf(address), callerLoc)
    }

    // ###################################################################################
    // Statistics and teardown
    // ###################################################################################

    // Walks the pages this allocator holds. Exact when the caller is the only thread allocating.
    mtd stats()->AllocatorStats
    {
        var result: retval

        .segmentMutex.lock()
        defer .segmentMutex.unlock()

        var segment: #null *AllocatorSegment = .firstSegment
        while segment
        {
            result.countSegment += 1
            for i in segment.pageCount
            {
                let page = &segment.pages[i]
                if page.state == AllocatorPageState.Free do
                    continue

                let live = page.liveCount()
                result.countPage  += 1
                result.countAlloc += live
                result.sizeAlloc  += cast(u64) live * page.blockSize
                result.countFree  += (page.carved - page.areaStart) / page.blockSize - live
                result.sizeCached += page.capacityBytes() - cast(u64) live * page.blockSize
            }

            segment = segment.nextSegment
        }

        result.countAlloc += atomicGet(&.headerCount)
        result.sizeAlloc  += atomicGet(&.headerBytes)
        result.countFree  += .quarantineCount
        result.sizeCached += .quarantineBytes

        result.sizeCommitted   = atomicGet(&g_AllocatorCommittedBytes)
        result.countOsCommit   = atomicGet(&g_AllocatorOsCommitCount)
        result.countOsDecommit = atomicGet(&g_AllocatorOsDecommitCount)
        result.countOsReserve  = atomicGet(&g_AllocatorOsReserveCount)
        return result
    }

    // Gives idle memory back: every page with no live block is decommitted, and every segment left
    // without a page returns to the shared pool.
    mtd trim()
    {
        let heap = currentAllocatorThreadHeap()
        if heap and heap.allocator == me
        {
            for i in AllocatorClassCount
            {
                let cls  = &heap.classes[i]
                var scan = cls.first
                while scan
                {
                    let next = scan.nextPage
                    scan.collectRemote()
                    if scan.used == 0 and scan != cls.page
                    {
                        .unlinkPage(heap, scan)
                        allocatorSegmentOf(scan).releasePage(scan)
                    }

                    scan = next
                }
            }
        }

        .segmentMutex.lock()
        defer .segmentMutex.unlock()

        var prevAbandoned: #null *AllocatorPage
        var abandoned:     #null *AllocatorPage = .firstAbandoned
        while abandoned
        {
            let next = abandoned.nextPage
            abandoned.collectRemote()
            if abandoned.used == 0
            {
                if !prevAbandoned do
                    .firstAbandoned = next
                else do
                    prevAbandoned.nextPage = next
                allocatorSegmentOf(abandoned).releasePage(abandoned)
            }
            else do
                prevAbandoned = abandoned

            abandoned = next
        }

        .releaseEmptySegments()
    }

    // Returns every segment without a live page. The caller holds the segment mutex.
    mtd releaseEmptySegments()
    {
        var segment: #null *AllocatorSegment = .firstSegment
        while segment
        {
            let next = segment.nextSegment
            if segment.isEmpty()
            {
                if segment.prevSegment do
                    segment.prevSegment.nextSegment = next
                else do
                    .firstSegment = next
                if next do
                    next.prevSegment = segment.prevSegment
                allocatorReleaseSegment(segment)
            }

            segment = next
        }
    }

    mtd releaseAll()
    {
        let heap = currentAllocatorThreadHeap()
        if heap and heap.allocator == me
        {
            setCurrentAllocatorThreadHeap(null)
            .retireThreadHeap(heap)
        }

        .segmentMutex.lock()

        // Any heap still registered belongs to a thread that never came back. Its pages go with it.
        while .firstHeap
        {
            let other = .firstHeap!
            .unlinkHeap(other)
            .osFree(other, #sizeof(AllocatorThreadHeap))
        }

        var segment: #null *AllocatorSegment = .firstSegment
        while segment
        {
            let next = segment.nextSegment
            for i in segment.pageCount
            {
                let page = &segment.pages[i]
                if page.state != AllocatorPageState.Free
                {
                    page.used = 0
                    segment.releasePage(page)
                }
            }

            allocatorReleaseSegment(segment)
            segment = next
        }

        .firstSegment   = null
        .firstAbandoned = null
        .segmentMutex.unlock()

        while .firstQuarantine
        {
            let header = .firstQuarantine!
            .firstQuarantine = header.next
            .osFree(header.allocAddr, header.allocSize)
        }

        .lastQuarantine  = null
        .quarantineBytes = 0
        .quarantineCount = 0

        while .firstAlloc
        {
            let header = .firstAlloc!
            .unlinkAllocated(header)
            .osFree(header.allocAddr, header.allocSize)
        }

        atomicSubU64(&.headerCount, atomicGet(&.headerCount))
        atomicSubU64(&.headerBytes, atomicGet(&.headerBytes))
    }

    mtd checkAllMemory()
    {
        var header = .firstAlloc
        while header
        {
            .checkAllocated(header)
            header = header.next
        }

        header = .firstQuarantine
        while header
        {
            .checkFree(header)
            header = header.next
        }
    }

    mtd printLeaks()
    {
        if !.detectLeaks do
            return

        let snapshot = .stats()
        let live     = snapshot.countAlloc
        if live == 0 do
            return

        @print("\nSwag allocator: memory remains allocated\n")
        @print("---------------------------------------\n")
        @print(live)
        if live == 1 do
            @print(" allocation, totaling ")
        else do
            @print(" allocations, totaling ")

        printDisplaySize(snapshot.sizeAlloc)
        @print("\n")
        @print("---------------------------------------\n")

        var scan = .firstAlloc
        var cpt  = 0
        while scan
        {
            .checkAllocated(scan)
            let tracking = scan.tracking!

            @print("\x1b[91m")
            @print("allocation #", tracking.allocId, ": size ")
            printDisplaySize(scan.userSize)
            if tracking.hint do
                @print(", hint ", tracking.hint)
            @print("\n")
            @print("\x1b[36m")
            @print("source: ")
            @print(tracking.loc.fileName, ":", tracking.loc.lineStart, "\n")
            if tracking.stackCount do
                __logStackTrace(@mkslice(&tracking.stack[0], tracking.stackCount), &tracking.loc, false)
            @print("---------------------------------------\n")

            scan = scan.next
            cpt  += 1
            if .showMaxLeaks and cpt >= .showMaxLeaks
            {
                @print("\x1b[91m")
                @print("remaining allocation details omitted\n")
                @print("\x1b[97m")
                break
            }
        }
    }

    mtd release()
    {
        if !.installed() do
            return

        .mutex.lock()
        .printLeaks()
        .releaseAll()
        .mutex.unlock()

        @init(me, 1)
    }

    mtd opDrop()
    {
        if !.installed() do
            return

        if me == defaultAllocator() do
            return

        .mutex.lock()
        defer .mutex.unlock()

        .printLeaks()
        .releaseAll()
    }
}

impl IAllocator for Allocator
{
    // The diagnostic modes (leak tracking, electric mode, ...) mutate shared state:
    // every operation takes the mutex when one of them is active.
    #[Swag.Inline]
    mtd lockDiagnostic()->bool
    {
        @assert(.installed())
        let useDiagnosticLock = .diagnosticMode()
        if useDiagnosticLock do
            .mutex.lock()
        return useDiagnosticLock
    }

    #[Swag.Inline]
    mtd unlockDiagnostic(locked: bool)
    {
        if locked do
            .mutex.unlock()
    }

    mtd impl alloc(request: *AllocatorRequest)
    {
        let locked = .lockDiagnostic()
        defer .unlockDiagnostic(locked)
        request.address = null
        .allocate(request)
    }

    mtd impl realloc(request: *AllocatorRequest)
    {
        let locked = .lockDiagnostic()
        defer .unlockDiagnostic(locked)
        .reallocate(request)
    }

    mtd impl free(request: *AllocatorRequest)
    {
        let locked = .lockDiagnostic()
        defer .unlockDiagnostic(locked)
        .freeBlock(request)
    }

    mtd impl freeAll(request: *AllocatorRequest)
    {
        let locked = .lockDiagnostic()
        defer .unlockDiagnostic(locked)
        .releaseAll()
        request.address = null
    }

    mtd impl assertAllocated(request: *AllocatorRequest)
    {
        let locked = .lockDiagnostic()
        defer .unlockDiagnostic(locked)
        .assertIsAllocated(request.address, request.callerLoc)
    }
}

func defaultAllocator()->*Allocator
{
    return &g_DefaultAllocator
}

// Gives the calling thread's pages back without waiting for the thread to exit.
func releaseAllocatorThreadCache()
{
    let heap = currentAllocatorThreadHeap()
    if !heap do
        return

    setCurrentAllocatorThreadHeap(null)

    let alloc = cast(#null *Allocator) heap.allocator
    if alloc do
        alloc.retireThreadHeap(heap)
}

func installAllocator(electricMode: bool = false, detectLeaks: bool = true, captureStack: bool = false, trackAllocations: bool = false, fillMemory: bool = false, installInContext: bool = true)->*Allocator
{
    let cxt = @getcontext()

    let alloc = &g_DefaultAllocator
    if !alloc.installed() do
        alloc.setup()
    alloc.configure(electricMode, detectLeaks, captureStack, trackAllocations, fillMemory)

    if installInContext
    {
        cxt.allocator        = @mkinterface(alloc, #typeof(dref alloc), IAllocator)
        cxt.defaultAllocator = cxt.allocator
    }

    return alloc
}
