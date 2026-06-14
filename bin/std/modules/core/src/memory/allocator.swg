#global public
#global namespace Memory
using Swag

const FastAllocatorClassCount   = 28'u32
const FastAllocatorInvalidClass = 0xFFFF_FFFF'u32

struct FastAllocatorHeader
{
    loc:           SourceCodeLocation
    allocAddr:     [*] void
    allocSize:     u64
    userSize:      u64
    blockSize:     u64
    hint:          string
    prev:          *FastAllocatorHeader
    next:          *FastAllocatorHeader
    prevFree:      *FastAllocatorHeader
    nextFree:      *FastAllocatorHeader
    stack:         [16] *void
    stackCount:    u32
    allocId:       u32
    classIndex:    u32
    alignment:     u32
    magic:         u32
    ownerHeap:     *void
}

struct FastAllocatorFooter
{
    magic: u32
}

struct FastAllocatorClass
{
    firstFree:    *FastAllocatorHeader
    cachedBytes:  u64
    cachedCount:  u32
}

struct FastAllocatorThreadClass
{
    firstFree:    *FastAllocatorHeader
    remoteFree:   *FastAllocatorHeader
    cachedBytes:  u64
    cachedCount:  u32
}

struct FastAllocatorThreadHeap
{
    allocator:    *void
    nextRetired:  *FastAllocatorThreadHeap
    threadId:     u64
    classes:      [FastAllocatorClassCount] FastAllocatorThreadClass
    cachedBytes:  u64
    cachedCount:  u32
    activeCount:  u32
    retired:      u32
}

#[Swag.Tls]
fileprivate var g_FastAllocatorThreadHeap: *FastAllocatorThreadHeap

struct FastAllocator
{
    allocator:       IAllocator
    mutex:           MutexRW
    classes:         [FastAllocatorClassCount] FastAllocatorClass
    firstAlloc:      *FastAllocatorHeader
    firstFree:       *FastAllocatorHeader
    lastFree:        *FastAllocatorHeader
    firstRetiredHeap: *FastAllocatorThreadHeap
    sizeAlloc:       u64
    sizeFree:        u64
    sizeCached:      u64
    countAlloc:      u32
    countFree:       u32
    nextId:          u32

    maxCachedSize:       u64 = 64 * 1024
    maxCachedBytes:      u64 = 8 * 1024 * 1024
    maxFreeSize:         u64 = 16 * 1024 * 1024
    showMaxLeaks:        u32 = 100
    breakOnAllocId:      u32
    captureAllocStack        = true
    detectLeaks              = true
    trackAllocations         = false
    fillAlloc                = true
    fillFree                 = true
    electricMode             = false
}

fileprivate var g_DefaultFastAllocator: FastAllocator

fileprivate func atomicLoadHeader(slot: **FastAllocatorHeader)->*FastAllocatorHeader
{
    return cast(*FastAllocatorHeader) @atomcmpxchg(cast(*u64) slot, 0'u64, 0'u64)
}

fileprivate func atomicExchangeHeader(slot: **FastAllocatorHeader, value: *FastAllocatorHeader)->*FastAllocatorHeader
{
    return cast(*FastAllocatorHeader) @atomxchg(cast(*u64) slot, cast(u64) value)
}

fileprivate func atomicCompareExchangeHeader(slot: **FastAllocatorHeader, compareTo, exchangeWith: *FastAllocatorHeader)->*FastAllocatorHeader
{
    return cast(*FastAllocatorHeader) @atomcmpxchg(cast(*u64) slot, cast(u64) compareTo, cast(u64) exchangeWith)
}

fileprivate func currentThreadId()->u64
{
    #if WINDOWS do
        return Env.Process.getThreadId()
    #else do
        return 1
}

impl FastAllocator
{
    const MagicAlloc = 0xC0DEF00D
    const MagicFree  = 0xFEE1DEAD
    const AllocByte  = 0xAB
    const FreeByte   = 0xFB

    func classSize(index: u32)->u64
    {
        switch index
        {
        case 0:
            return 8
        case 1:
            return 16
        case 2:
            return 24
        case 3:
            return 32
        case 4:
            return 48
        case 5:
            return 64
        case 6:
            return 80
        case 7:
            return 96
        case 8:
            return 128
        case 9:
            return 160
        case 10:
            return 192
        case 11:
            return 256
        case 12:
            return 320
        case 13:
            return 384
        case 14:
            return 512
        case 15:
            return 768
        case 16:
            return 1024
        case 17:
            return 1536
        case 18:
            return 2048
        case 19:
            return 3072
        case 20:
            return 4096
        case 21:
            return 6144
        case 22:
            return 8192
        case 23:
            return 12288
        case 24:
            return 16384
        case 25:
            return 24576
        case 26:
            return 32768
        case 27:
            return 65536
        }

        return 0
    }

    func sizeClass(size: u64)->u32
    {
        for i in FastAllocatorClassCount
        {
            if size <= classSize(i) do
                return i
        }

        return FastAllocatorInvalidClass
    }

    func memAlign(value: u64, alignment: u32)->u64
    {
        let toAlign = cast(u64) (alignment orelse cast(u32) #sizeof(*void)) - 1
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

    mtd setup(allocator: IAllocator)
    {
        @assert(allocator != null)
        .allocator = allocator
    }

    mtd installed()->bool
    {
        return .allocator != null
    }

    mtd allocateThreadHeap()->*FastAllocatorThreadHeap
    {
        var req: AllocatorRequest
        req.mode = .Alloc
        req.size = #sizeof(FastAllocatorThreadHeap)
        .allocator.req(&req)
        @assert(req.address != null)

        @memset(req.address, 0, #sizeof(FastAllocatorThreadHeap))
        let heap = cast(*FastAllocatorThreadHeap) req.address
        heap.allocator = me
        heap.threadId = currentThreadId()
        return heap
    }

    mtd retireThreadHeap(heap: *FastAllocatorThreadHeap)
    {
        if !heap do
            return
        if Atomic.exchange(&heap.retired, 1) != 0 do
            return

        .releaseThreadHeap(heap)

        .mutex.lock()
        heap.nextRetired = .firstRetiredHeap
        .firstRetiredHeap = heap
        .mutex.unlock()
    }

    mtd threadHeap()->*FastAllocatorThreadHeap
    {
        let heap = g_FastAllocatorThreadHeap
        let tid = currentThreadId()
        if heap and heap.allocator == me and heap.threadId == tid do
            return heap

        if heap and heap.threadId == tid
        {
            g_FastAllocatorThreadHeap = null
            let oldAllocator = cast(*FastAllocator) heap.allocator
            if oldAllocator do
                oldAllocator.retireThreadHeap(heap)
        }

        g_FastAllocatorThreadHeap = .allocateThreadHeap()
        return g_FastAllocatorThreadHeap
    }

    mtd fastPathEnabled(request: *AllocatorRequest, classIndex: u32)->bool
    {
        if .diagnosticMode() do
            return false
        if classIndex == FastAllocatorInvalidClass do
            return false
        if request.alignment > #sizeof(*void) do
            return false
        return true
    }

    mtd diagnosticMode()->bool
    {
        return .trackAllocations or .electricMode
    }

    mtd statAdd(value: *u64, delta: u64)
    {
        discard Atomic.add(value, delta)
    }

    mtd statAdd(value: *u32, delta: u32)
    {
        discard Atomic.add(value, delta)
    }

    mtd statSub(value: *u64, delta: u64)
    {
        while true
        {
            let oldValue = Atomic.get(value)
            @assert(oldValue >= delta)
            if Atomic.compareExchange(value, oldValue, oldValue - delta) == oldValue do
                return
        }
    }

    mtd statSub(value: *u32, delta: u32)
    {
        while true
        {
            let oldValue = Atomic.get(value)
            @assert(oldValue >= delta)
            if Atomic.compareExchange(value, oldValue, oldValue - delta) == oldValue do
                return
        }
    }

    mtd decActive(heap: *FastAllocatorThreadHeap)->u32
    {
        while true
        {
            let oldValue = Atomic.get(&heap.activeCount)
            @assert(oldValue > 0)
            if Atomic.compareExchange(&heap.activeCount, oldValue, oldValue - 1) == oldValue do
                return oldValue
        }
    }

    mtd shouldCache(header: *FastAllocatorHeader)->bool
    {
        if .electricMode do
            return false
        if header.classIndex == FastAllocatorInvalidClass do
            return false
        if header.alignment > #sizeof(*void) do
            return false
        if header.blockSize > .maxCachedSize do
            return false
        return true
    }

    mtd pushThreadLocal(heap: *FastAllocatorThreadHeap, header: *FastAllocatorHeader)
    {
        let cls = &heap.classes[header.classIndex]
        header.prevFree = null
        header.nextFree = cls.firstFree
        cls.firstFree = header
        cls.cachedBytes += header.blockSize
        cls.cachedCount += 1
        heap.cachedBytes += header.blockSize
        heap.cachedCount += 1
        .statAdd(&.sizeCached, header.blockSize)
        .statAdd(&.sizeFree, header.userSize)
        .statAdd(&.countFree, 1)
    }

    mtd releaseRetiredRemote(heap: *FastAllocatorThreadHeap, classIndex: u32)
    {
        let cls = &heap.classes[classIndex]
        var list = atomicExchangeHeader(&cls.remoteFree, null)
        while list
        {
            let next = list.nextFree
            .releaseUncached(list)
            list = next
        }
    }

    mtd pushThreadRemote(heap: *FastAllocatorThreadHeap, header: *FastAllocatorHeader)->bool
    {
        let cls = &heap.classes[header.classIndex]
        while true
        {
            if Atomic.get(&heap.retired) != 0 do
                return false

            let oldHead = atomicLoadHeader(&cls.remoteFree)
            header.prevFree = null
            header.nextFree = oldHead
            if atomicCompareExchangeHeader(&cls.remoteFree, oldHead, header) == oldHead
            {
                if Atomic.get(&heap.retired) != 0 do
                    .releaseRetiredRemote(heap, header.classIndex)
                return true
            }
        }
    }

    mtd drainThreadRemote(heap: *FastAllocatorThreadHeap, classIndex: u32)
    {
        let cls = &heap.classes[classIndex]
        var list = atomicExchangeHeader(&cls.remoteFree, null)
        while list
        {
            let next = list.nextFree
            .pushThreadLocal(heap, list)
            list = next
        }
    }

    mtd releaseThreadCached(heap: *FastAllocatorThreadHeap, classIndex: u32)
    {
        let cls = &heap.classes[classIndex]
        let header = cls.firstFree
        if !header do
            return

        .checkFree(header)
        cls.firstFree = header.nextFree
        @assert(cls.cachedCount > 0)
        @assert(cls.cachedBytes >= header.blockSize)
        @assert(heap.cachedCount > 0)
        @assert(heap.cachedBytes >= header.blockSize)
        cls.cachedCount -= 1
        cls.cachedBytes -= header.blockSize
        heap.cachedCount -= 1
        heap.cachedBytes -= header.blockSize
        .statSub(&.sizeCached, header.blockSize)
        .statSub(&.sizeFree, header.userSize)
        .statSub(&.countFree, 1)

        var req: AllocatorRequest
        req.mode    = .Free
        req.address = header.allocAddr
        req.size    = header.allocSize
        .allocator.req(&req)
    }

    mtd trimThreadHeap(heap: *FastAllocatorThreadHeap)
    {
        while heap.cachedBytes > .maxCachedBytes
        {
            var released = false
            for i in FastAllocatorClassCount
            {
                if heap.classes[i].firstFree
                {
                    .releaseThreadCached(heap, i)
                    released = true
                    break
                }
            }

            if !released do
                return
        }
    }

    mtd releaseThreadHeap(heap: *FastAllocatorThreadHeap)
    {
        for i in FastAllocatorClassCount
        {
            .drainThreadRemote(heap, i)
            while heap.classes[i].firstFree do
                .releaseThreadCached(heap, i)
        }
    }

    mtd releaseThreadHeapRecord(heap: *FastAllocatorThreadHeap)
    {
        var req: AllocatorRequest
        req.mode = .Free
        req.address = heap
        req.size = #sizeof(FastAllocatorThreadHeap)
        .allocator.req(&req)
    }

    mtd releaseRetiredHeaps()
    {
        var prev: *FastAllocatorThreadHeap
        var heap = .firstRetiredHeap
        while heap
        {
            let next = heap.nextRetired
            if Atomic.get(&heap.activeCount) == 0
            {
                if !prev do
                    .firstRetiredHeap = next
                else do
                    prev.nextRetired = next
                .releaseThreadHeapRecord(heap)
            }
            else do
                prev = heap
            heap = next
        }
    }

    mtd acquireThreadCached(heap: *FastAllocatorThreadHeap, classIndex: u32, size: u64)->*FastAllocatorHeader
    {
        .drainThreadRemote(heap, classIndex)

        let cls = &heap.classes[classIndex]
        let header = cls.firstFree
        if !header do
            return null

        .checkFree(header)
        cls.firstFree = header.nextFree
        @assert(cls.cachedCount > 0)
        @assert(cls.cachedBytes >= header.blockSize)
        @assert(heap.cachedCount > 0)
        @assert(heap.cachedBytes >= header.blockSize)
        cls.cachedCount -= 1
        cls.cachedBytes -= header.blockSize
        heap.cachedCount -= 1
        heap.cachedBytes -= header.blockSize
        .statSub(&.sizeCached, header.blockSize)
        .statSub(&.sizeFree, header.userSize)
        .statSub(&.countFree, 1)

        header.prevFree, header.nextFree = null
        header.userSize = size
        return header
    }

    mtd userAddress(header: *FastAllocatorHeader)->[*] u8
    {
        return cast([*] u8) header + #sizeof(FastAllocatorHeader)
    }

    mtd footer(header: *FastAllocatorHeader)->*FastAllocatorFooter
    {
        return cast(*FastAllocatorFooter) (.userAddress(header) + header.userSize)
    }

    mtd checkFree(header: *FastAllocatorHeader)
    {
        let foot = .footer(header)
        if header.magic != MagicFree or foot.magic != MagicFree
        {
            @panic("memory block corruption", #curlocation)
        }
    }

    mtd checkAllocated(header: *FastAllocatorHeader, callerLoc = #callerlocation)
    {
        let foot = .footer(header)
        if (header.magic != MagicAlloc and header.magic != MagicFree) or
           (foot.magic != MagicAlloc and foot.magic != MagicFree)
        {
            @panic("memory block corruption", callerLoc)
        }

        if header.magic == MagicFree
        {
            let loc = header.loc.fileName ? header.loc : callerLoc
            @panic("memory block double free", loc)
        }
    }

    mtd assertIsAllocated(addr: *void, callerLoc = #callerlocation)
    {
        if !addr do
            return

        let header = cast(*FastAllocatorHeader) (cast([*] u8) addr - #sizeof(FastAllocatorHeader))
        .checkAllocated(header, callerLoc)
    }

    mtd unlinkAllocated(header: *FastAllocatorHeader)
    {
        if !header.prev do
            .firstAlloc = header.next
        else do
            header.prev.next = header.next

        if header.next do
            header.next.prev = header.prev

        header.prev, header.next = null
    }

    mtd linkAllocated(header: *FastAllocatorHeader)
    {
        header.prev = null
        header.next = .firstAlloc
        if header.next do
            header.next.prev = header
        .firstAlloc = header
    }

    mtd unlinkFree(header: *FastAllocatorHeader)
    {
        if !header.prev do
            .firstFree = header.next
        else do
            header.prev.next = header.next

        if header.next do
            header.next.prev = header.prev
        else do
            .lastFree = header.prev

        let isCached = header.classIndex != FastAllocatorInvalidClass and (header.prevFree or header.nextFree or .classes[header.classIndex].firstFree == header)
        if isCached
        {
            let cls = &.classes[header.classIndex]
            if !header.prevFree do
                cls.firstFree = header.nextFree
            else do
                header.prevFree.nextFree = header.nextFree

            if header.nextFree do
                header.nextFree.prevFree = header.prevFree

            @assert(cls.cachedCount > 0)
            @assert(cls.cachedBytes >= header.blockSize)
            cls.cachedCount -= 1
            cls.cachedBytes -= header.blockSize
            @assert(.sizeCached >= header.blockSize)
            .statSub(&.sizeCached, header.blockSize)
        }

        @assert(.countFree > 0)
        @assert(.sizeFree >= header.userSize)
        .statSub(&.countFree, 1)
        .statSub(&.sizeFree, header.userSize)
        header.prev, header.next = null
        header.prevFree, header.nextFree = null
    }

    mtd linkFree(header: *FastAllocatorHeader)
    {
        header.prev = null
        header.next = .firstFree
        if .firstFree do
            .firstFree.prev = header
        .firstFree = header
        if !.lastFree do
            .lastFree = header

        .statAdd(&.countFree, 1)
        .statAdd(&.sizeFree, header.userSize)

        if .shouldCache(header)
        {
            let cls = &.classes[header.classIndex]
            header.prevFree = null
            header.nextFree = cls.firstFree
            if cls.firstFree do
                cls.firstFree.prevFree = header
            cls.firstFree = header
            cls.cachedCount += 1
            cls.cachedBytes += header.blockSize
            .statAdd(&.sizeCached, header.blockSize)
        }
    }

    mtd releaseBlock(header: *FastAllocatorHeader)
    {
        .checkFree(header)
        .unlinkFree(header)

        .releaseUncached(header)
    }

    mtd releaseUncached(header: *FastAllocatorHeader)
    {
        .checkFree(header)

        let freeAddr = header.allocAddr
        let freeSize = header.allocSize

        @memset(header, FreeByte, #sizeof(FastAllocatorHeader))

        var req: AllocatorRequest
        req.mode    = .Free
        req.address = freeAddr
        req.size    = freeSize
        .allocator.req(&req)
    }

    mtd releaseOldest()
    {
        if .lastFree do
            .releaseBlock(.lastFree)
    }

    mtd trim()
    {
        while .lastFree and (.sizeCached > .maxCachedBytes or (.maxFreeSize and .sizeFree > .maxFreeSize)) do
            .releaseOldest()
    }

    mtd acquireCached(classIndex: u32, size: u64)->*FastAllocatorHeader
    {
        if .electricMode or classIndex == FastAllocatorInvalidClass do
            return null

        let cls = &.classes[classIndex]
        let header = cls.firstFree
        if !header do
            return null

        .checkFree(header)
        .unlinkFree(header)
        header.userSize = size
        return header
    }

    mtd allocateBlock(request: *AllocatorRequest, blockSize: u64, classIndex: u32)->*FastAllocatorHeader
    {
        let alignment = request.alignment orelse cast(u32) #sizeof(*void)
        let toAddAlign = memAlign(#sizeof(FastAllocatorHeader), alignment)

        var req = dref request
        req.mode = .Alloc
        req.size = toAddAlign + blockSize + #sizeof(FastAllocatorFooter)
        req.address = null
        .allocator.req(&req)
        if !req.address do
            return null

        var userAddr = cast([*] u8) req.address
        userAddr += toAddAlign

        let header = cast(*FastAllocatorHeader) (userAddr - #sizeof(FastAllocatorHeader))
        header.allocAddr  = req.address
        header.allocSize  = req.size
        header.blockSize  = blockSize
        header.classIndex = classIndex
        header.alignment  = alignment
        return header
    }

    mtd setupAllocatedHeader(header: *FastAllocatorHeader, request: *AllocatorRequest, heap: *FastAllocatorThreadHeap)
    {
        header.magic      = MagicAlloc
        header.userSize   = request.size
        header.loc        = request.callerLoc
        header.hint       = request.hint
        header.stackCount = 0
        header.ownerHeap  = heap
        header.prevFree, header.nextFree = null
        discard Atomic.add(&heap.activeCount, 1)

        let foot = .footer(header)
        foot.magic = MagicAlloc

        if .fillAlloc do
            @memset(.userAddress(header), AllocByte, request.size)

        header.allocId = Atomic.add(&.nextId, 1) + 1
        if header.allocId == .breakOnAllocId do
            @assert(false)

        .statAdd(&.countAlloc, 1)
        .statAdd(&.sizeAlloc, request.size)
        if .trackAllocations do
            .linkAllocated(header)
        request.address = .userAddress(header)
    }

    mtd allocate(request: *AllocatorRequest)
    {
        if request.size == 0
        {
            if request.mode == .Realloc do
                .free(request)
            request.address = null
            return
        }

        let classIndex = sizeClass(request.size)
        let blockSize  = classIndex == FastAllocatorInvalidClass ? request.size : classSize(classIndex)
        let heap       = .threadHeap()

        var header: *FastAllocatorHeader
        if .fastPathEnabled(request, classIndex) do
            header = .acquireThreadCached(heap, classIndex, request.size)
        else
        {
            if .diagnosticMode() do
                header = .acquireCached(classIndex, request.size)
        }

        if !header do
            header = .allocateBlock(request, blockSize, classIndex)
        if !header
        {
            request.address = null
            return
        }

        .setupAllocatedHeader(header, request, heap)
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
            .free(request)
            return
        }

        let oldAddress = request.address
        let oldHeader  = cast(*FastAllocatorHeader) (cast([*] u8) oldAddress - #sizeof(FastAllocatorHeader))
        .checkAllocated(oldHeader, request.callerLoc)

        if request.size <= oldHeader.blockSize and (request.alignment == 0 or request.alignment <= oldHeader.alignment)
        {
            let oldSize = oldHeader.userSize
            let oldFoot = .footer(oldHeader)
            oldFoot.magic = 0
            oldHeader.userSize = request.size
            let newFoot = .footer(oldHeader)
            newFoot.magic = MagicAlloc

            if .fillAlloc and oldSize < request.size do
                @memset(.userAddress(oldHeader) + oldSize, AllocByte, request.size - oldSize)

            .statSub(&.sizeAlloc, oldSize)
            .statAdd(&.sizeAlloc, request.size)
            request.address = oldAddress
            return
        }

        let copySize = @min(oldHeader.userSize, request.size)

        var allocReq = dref request
        allocReq.mode = .Alloc
        allocReq.address = null
        .allocate(&allocReq)
        if !allocReq.address
        {
            request.address = null
            return
        }

        @memcpy(allocReq.address, oldAddress, copySize)

        var freeReq = dref request
        freeReq.mode = .Free
        freeReq.address = oldAddress
        freeReq.size = oldHeader.userSize
        .free(&freeReq)

        request.address = allocReq.address
    }

    mtd free(request: *AllocatorRequest)
    {
        if !request.address do
            return

        let userAddr = cast([*] u8) request.address
        let header = cast(*FastAllocatorHeader) (userAddr - #sizeof(FastAllocatorHeader))
        .checkAllocated(header, request.callerLoc)
        let foot = .footer(header)
        let ownerHeap = cast(*FastAllocatorThreadHeap) header.ownerHeap

        if .trackAllocations do
            .unlinkAllocated(header)

        .statSub(&.countAlloc, 1)
        .statSub(&.sizeAlloc, header.userSize)
        discard .decActive(ownerHeap)

        if .fillFree do
            @memset(userAddr, FreeByte, header.userSize)

        header.magic = MagicFree
        foot.magic   = MagicFree
        header.loc   = request.callerLoc

        request.address = null

        if .fastPathEnabled(request, header.classIndex)
        {
            let heap = g_FastAllocatorThreadHeap
            if ownerHeap == heap and ownerHeap.threadId == currentThreadId() and Atomic.get(&ownerHeap.retired) == 0
            {
                .pushThreadLocal(heap, header)
                .trimThreadHeap(heap)
            }
            else
            {
                if !.pushThreadRemote(ownerHeap, header) do
                    .releaseUncached(header)
            }
        }
        else
        {
            if .diagnosticMode()
            {
                .linkFree(header)
                .trim()
            }
            else do
                .releaseUncached(header)
        }
    }

    mtd freeAll()
    {
        let heap = g_FastAllocatorThreadHeap
        if heap and heap.allocator == me
        {
            g_FastAllocatorThreadHeap = null
            discard Atomic.exchange(&heap.retired, 1)
            .releaseThreadHeap(heap)
        }

        while .firstFree do
            .releaseBlock(.firstFree)

        while .firstAlloc
        {
            let header = .firstAlloc
            .unlinkAllocated(header)
            discard .decActive(cast(*FastAllocatorThreadHeap) header.ownerHeap)
            .statSub(&.countAlloc, 1)
            .statSub(&.sizeAlloc, header.userSize)

            var req: AllocatorRequest
            req.mode    = .Free
            req.address = header.allocAddr
            req.size    = header.allocSize
            .allocator.req(&req)
        }

        if heap and heap.allocator == me and Atomic.get(&heap.activeCount) == 0 do
            .releaseThreadHeapRecord(heap)
    }

    mtd checkAllMemory()
    {
        var header = .firstAlloc
        while header
        {
            .checkAllocated(header)
            header = header.next
        }

        header = .firstFree
        while header
        {
            .checkFree(header)
            header = header.next
        }
    }

    mtd printLeaks()
    {
        if .countAlloc == 0 or !.detectLeaks do
            return

        var scan = .firstAlloc

        @print("############################################\n")
        @print("Core.Memory.FastAllocator: Memory leaks detected !\n")
        @print("--------------------------------------------\n")
        @print(.countAlloc, " block(s) for a total of ")
        printDisplaySize(.sizeAlloc)
        @print("\n")
        @print("############################################\n")

        var cpt = 0
        while scan
        {
            .checkAllocated(scan)

            @print("--------------------------------------------\n")
            @print("\x1b[91m")
            @print("leak error: id [", scan.allocId, "] size [")
            printDisplaySize(scan.userSize)
            if scan.hint do
                @print("] hint [", scan.hint, "]")
            else do
                @print("]")
            @print("\n")
            @print("\x1b[36m")
            @print("--> ")
            @print(scan.loc.fileName, ":", scan.loc.lineStart + 1, "\n")
            @print("--------------------------------------------\n")

            scan = scan.next
            cpt += 1
            if .showMaxLeaks and cpt >= .showMaxLeaks
            {
                @print("--------------------------------------------\n")
                @print("\x1b[91m")
                @print("... too many leaks (", .countAlloc, ")...\n")
                @print("\x1b[97m")
                break
            }
        }

        @print("############################################\n")
    }

    mtd opDrop()
    {
        .mutex.lock()
        defer .mutex.unlock()

        .printLeaks()
        .freeAll()
        .releaseRetiredHeaps()
    }
}

impl IAllocator for FastAllocator
{
    mtd impl req(request: *AllocatorRequest)
    {
        @assert(.allocator != null)
        let useDiagnosticLock = .diagnosticMode()
        if useDiagnosticLock do
            .mutex.lock()
        defer
        {
            if useDiagnosticLock do
                .mutex.unlock()
        }

        switch request.mode
        {
        case Free:
            .free(request)

        case FreeAll:
            .freeAll()
            request.address = null

        case Realloc:
            .reallocate(request)

        case Alloc:
            request.address = null
            .allocate(request)

        case AssertIsAllocated:
            .assertIsAllocated(request.address, request.callerLoc)
        }
    }
}

func defaultFastAllocator()->*FastAllocator
{
    return &g_DefaultFastAllocator
}

func releaseFastAllocatorThreadCache()
{
    let heap = g_FastAllocatorThreadHeap
    if !heap do
        return
    if heap.threadId != currentThreadId() do
        return

    g_FastAllocatorThreadHeap = null

    let alloc = cast(*FastAllocator) heap.allocator
    if alloc do
        alloc.retireThreadHeap(heap)
}

func installFastAllocator(electricMode: bool = false, detectLeaks: bool = true, captureStack: bool = true, trackAllocations: bool = false)->*FastAllocator
{
    let cxt = @getcontext()
    @assert(cxt.allocator != null)

    let alloc = &g_DefaultFastAllocator
    if !alloc.installed()
    {
        alloc.setup(cxt.allocator)
        alloc.electricMode = electricMode
        alloc.detectLeaks = detectLeaks
        alloc.captureAllocStack = captureStack
        alloc.trackAllocations = trackAllocations
    }

    cxt.allocator = @mkinterface(alloc, #typeof(dref alloc), IAllocator)
    return alloc
}
