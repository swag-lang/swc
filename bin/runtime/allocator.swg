#global namespace Swag

const AllocatorClassCount   = 28'u32
const AllocatorInvalidClass = 0xFFFF_FFFF'u32

struct AllocatorHeader
{
    loc:        SourceCodeLocation
    allocAddr:  #null [*] void
    allocSize:  u64
    userSize:   u64
    blockSize:  u64
    hint:       #null string
    prev:       #null *AllocatorHeader
    next:       #null *AllocatorHeader
    prevFree:   #null *AllocatorHeader
    nextFree:   #null *AllocatorHeader
    stack:      [16] *void = undefined
    stackCount: u32
    allocId:    u32
    classIndex: u32
    alignment:  u32
    isTracked:  bool
    magic:      u32
    ownerHeap:  #null *void
}

struct AllocatorFooter
{
    magic: u32
}

struct AllocatorRawBlock
{
    address: #null [*] void
    size:    u64
}

struct AllocatorClass
{
    firstFree:   #null *AllocatorHeader
    cachedBytes: u64
    cachedCount: u32
}

struct AllocatorThreadClass
{
    firstFree:   #null *AllocatorHeader
    remoteFree:  #null *AllocatorHeader
    cachedBytes: u64
    cachedCount: u32
}

struct AllocatorThreadHeap
{
    allocator:   #null *void
    nextRetired: #null *AllocatorThreadHeap
    threadId:    u64
    classes:     [AllocatorClassCount] AllocatorThreadClass
    cachedBytes: u64
    cachedCount: u32
    activeCount: u32
    retired:     u32
}

#[Swag.Tls]
private var g_AllocatorThreadHeap: #null *AllocatorThreadHeap

struct Allocator
{
    mutex:            MutexRW
    classes:          [AllocatorClassCount] AllocatorClass
    firstAlloc:       #null *AllocatorHeader
    firstFree:        #null *AllocatorHeader
    lastFree:         #null *AllocatorHeader
    firstRetiredHeap: #null *AllocatorThreadHeap
    sizeAlloc:        u64
    sizeFree:         u64
    sizeCached:       u64
    sizeOsAlloc:      u64
    sizeOsFree:       u64
    countAlloc:       u32
    countFree:        u32
    countOsAlloc:     u32
    countOsFree:      u32
    nextId:           u32
    installMagic:     u32 = 0

    maxCachedSize:     u64
    maxCachedBytes:    u64
    maxFreeSize:       u64
    showMaxLeaks:      u32
    breakOnAllocId:    u32
    captureAllocStack: bool
    detectLeaks:       bool
    trackAllocations:  bool
    fillAlloc:         bool
    fillFree:          bool
    electricMode:      bool
}

private var g_DefaultAllocator: Allocator

private func atomicLoadHeader(slot: *#null *AllocatorHeader)->#null *AllocatorHeader
{
    return cast(#null *AllocatorHeader) @atomcmpxchg(cast(*u64) slot, 0'u64, 0'u64)
}

private func atomicExchangeHeader(slot: *#null *AllocatorHeader, value: #null *AllocatorHeader)->#null *AllocatorHeader
{
    return cast(#null *AllocatorHeader) @atomxchg(cast(*u64) slot, cast(u64) value)
}

private func atomicCompareExchangeHeader(slot: *#null *AllocatorHeader, compareTo, exchangeWith: #null *AllocatorHeader)->#null *AllocatorHeader
{
    return cast(#null *AllocatorHeader) @atomcmpxchg(cast(*u64) slot, cast(u64) compareTo, cast(u64) exchangeWith)
}

private func atomicGet(addr: *u32)->u32 => @atomcmpxchg(addr, 0, 0)
private func atomicGet(addr: *u64)->u64 => @atomcmpxchg(addr, 0, 0)

private func currentThreadId()->u64
{
    #if #os == Swag.TargetOs.Windows do
        return __Win32RT.GetCurrentThreadId()
    #else do
        return 1
}

impl Allocator
{
    const MagicAlloc     = 0xC0DEF00D
    const MagicFree      = 0xFEE1DEAD
    const AllocByte      = 0xAB
    const FreeByte       = 0xFB
    const InstalledMagic = 0xA110CA7E

    func classSize(index: u32)->u64
    {
        switch index
        {
        case 0:  return 8
        case 1:  return 16
        case 2:  return 24
        case 3:  return 32
        case 4:  return 48
        case 5:  return 64
        case 6:  return 80
        case 7:  return 96
        case 8:  return 128
        case 9:  return 160
        case 10: return 192
        case 11: return 256
        case 12: return 320
        case 13: return 384
        case 14: return 512
        case 15: return 768
        case 16: return 1024
        case 17: return 1536
        case 18: return 2048
        case 19: return 3072
        case 20: return 4096
        case 21: return 6144
        case 22: return 8192
        case 23: return 12288
        case 24: return 16384
        case 25: return 24576
        case 26: return 32768
        case 27: return 65536
        }

        return 0
    }

    func sizeClass(size: u64)->u32
    {
        for i in AllocatorClassCount
        {
            if size <= classSize(i) do
                return i
        }

        return AllocatorInvalidClass
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

    mtd setup()
    {
        @memset(me, 0, #sizeof(Allocator))
        .installMagic = InstalledMagic
        .configure(false, true, false, false, false)
    }

    mtd configure(electricMode: bool, detectLeaks: bool, captureStack: bool, trackAllocations: bool, fillMemory: bool)
    {
        .maxCachedSize     = 64 * 1024
        .maxCachedBytes    = 8 * 1024 * 1024
        .maxFreeSize       = 16 * 1024 * 1024
        .showMaxLeaks      = 100
        .breakOnAllocId    = 0
        .captureAllocStack = captureStack
        .detectLeaks       = detectLeaks
        .trackAllocations  = trackAllocations
        .fillAlloc         = fillMemory
        .fillFree          = fillMemory
        .electricMode      = electricMode
    }

    mtd installed()->bool
    {
        return .installMagic == InstalledMagic
    }

    mtd osAlloc(size: u64)->#null [*] u8
    {
        #if #os == Swag.TargetOs.Windows do
            return cast(#null [*] u8) __Win32RT.VirtualAlloc(null, size, __Win32RT.MEM_RESERVE | __Win32RT.MEM_COMMIT, __Win32RT.PAGE_READWRITE)
        #else do
            return cast(#null [*] u8) @alloc(size)
    }

    mtd osFree(address: #null *void)
    {
        if !address do
            return

        #if #os == Swag.TargetOs.Windows do
            discard __Win32RT.VirtualFree(address, 0, __Win32RT.MEM_RELEASE)
        #else do
            @free(cast(#null [*] void) address)
    }

    mtd rawAlloc(size: u64, alignment: u32 = 0)->#null [*] u8
    {
        let align = cast(u64) (alignment orelse cast(u32) #sizeof(*void))
        let bytes = size + align - 1 + #sizeof(AllocatorRawBlock)
        let raw = .osAlloc(bytes)
        if !raw do
            return null

        var user = raw + #sizeof(AllocatorRawBlock)
        user = cast([*] u8) ((cast(u64) user + align - 1) & ~(align - 1))

        let rawBlock = cast(*AllocatorRawBlock) (user - #sizeof(AllocatorRawBlock))
        rawBlock.address = cast([*] void) raw
        rawBlock.size    = bytes
        .statAdd(&.countOsAlloc, 1)
        .statAdd(&.sizeOsAlloc, bytes)
        return user
    }

    mtd rawFree(address: #null *void)
    {
        if !address do
            return

        let rawBlock = cast(*AllocatorRawBlock) (cast([*] u8) address - #sizeof(AllocatorRawBlock))
        .statAdd(&.countOsFree, 1)
        .statAdd(&.sizeOsFree, rawBlock.size)
        .osFree(rawBlock.address)
    }

    mtd allocateThreadHeap()->*AllocatorThreadHeap
    {
        let address = notnull .rawAlloc(#sizeof(AllocatorThreadHeap))
        @memset(address, 0, #sizeof(AllocatorThreadHeap))
        let heap = cast(*AllocatorThreadHeap) address
        heap.allocator = me
        heap.threadId  = currentThreadId()
        return heap
    }

    mtd retireThreadHeap(heap: *AllocatorThreadHeap)
    {
        if @atomxchg(&heap.retired, 1) != 0 do
            return

        .releaseThreadHeap(heap)

        .mutex.lock()
        heap.nextRetired  = .firstRetiredHeap
        .firstRetiredHeap = heap
        .mutex.unlock()
    }

    mtd threadHeap()->*AllocatorThreadHeap
    {
        let heap = g_AllocatorThreadHeap
        let tid = currentThreadId()
        if heap and heap.allocator == me and heap.threadId == tid do
            return heap

        if heap and heap.threadId == tid
        {
            g_AllocatorThreadHeap = null
            let oldAllocator = cast(#null *Allocator) heap.allocator
            if oldAllocator do
                oldAllocator.retireThreadHeap(heap)
        }

        let newHeap = .allocateThreadHeap()
        g_AllocatorThreadHeap = newHeap
        return newHeap
    }

    mtd fastPathEnabled(request: *AllocatorRequest, classIndex: u32)->bool
    {
        if .diagnosticMode() do
            return false
        if classIndex == AllocatorInvalidClass do
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
        discard @atomadd(value, delta)
    }

    mtd statAdd(value: *u32, delta: u32)
    {
        discard @atomadd(value, delta)
    }

    mtd statSub(value: *u64, delta: u64)
    {
        while true
        {
            let oldValue = atomicGet(value)
            @assert(oldValue >= delta)
            if @atomcmpxchg(value, oldValue, oldValue - delta) == oldValue do
                return
        }
    }

    mtd statSub(value: *u32, delta: u32)
    {
        while true
        {
            let oldValue = atomicGet(value)
            @assert(oldValue >= delta)
            if @atomcmpxchg(value, oldValue, oldValue - delta) == oldValue do
                return
        }
    }

    mtd decActive(heap: *AllocatorThreadHeap)->u32
    {
        while true
        {
            let oldValue = atomicGet(&heap.activeCount)
            @assert(oldValue > 0)
            if @atomcmpxchg(&heap.activeCount, oldValue, oldValue - 1) == oldValue do
                return oldValue
        }
    }

    mtd shouldCache(header: *AllocatorHeader)->bool
    {
        if .electricMode do
            return false
        if header.classIndex == AllocatorInvalidClass do
            return false
        if header.alignment > #sizeof(*void) do
            return false
        if header.blockSize > .maxCachedSize do
            return false
        return true
    }

    mtd pushThreadLocal(heap: *AllocatorThreadHeap, header: *AllocatorHeader)
    {
        let cls = &heap.classes[header.classIndex]
        header.prevFree  = null
        header.nextFree  = cls.firstFree
        cls.firstFree    = header
        cls.cachedBytes  += header.blockSize
        cls.cachedCount  += 1
        heap.cachedBytes += header.blockSize
        heap.cachedCount += 1
        .statAdd(&.sizeCached, header.blockSize)
        .statAdd(&.sizeFree, header.userSize)
        .statAdd(&.countFree, 1)
    }

    mtd releaseRetiredRemote(heap: *AllocatorThreadHeap, classIndex: u32)
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

    mtd pushThreadRemote(heap: *AllocatorThreadHeap, header: *AllocatorHeader)->bool
    {
        let cls = &heap.classes[header.classIndex]
        while true
        {
            if atomicGet(&heap.retired) != 0 do
                return false

            let oldHead = atomicLoadHeader(&cls.remoteFree)
            header.prevFree = null
            header.nextFree = oldHead
            if atomicCompareExchangeHeader(&cls.remoteFree, oldHead, header) == oldHead
            {
                if atomicGet(&heap.retired) != 0 do
                    .releaseRetiredRemote(heap, header.classIndex)
                return true
            }
        }
    }

    mtd drainThreadRemote(heap: *AllocatorThreadHeap, classIndex: u32)
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

    mtd releaseThreadCached(heap: *AllocatorThreadHeap, classIndex: u32)
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
        cls.cachedCount  -= 1
        cls.cachedBytes  -= header.blockSize
        heap.cachedCount -= 1
        heap.cachedBytes -= header.blockSize
        .statSub(&.sizeCached, header.blockSize)
        .statSub(&.sizeFree, header.userSize)
        .statSub(&.countFree, 1)

        .rawFree(header.allocAddr)
    }

    mtd trimThreadHeap(heap: *AllocatorThreadHeap)
    {
        while heap.cachedBytes > .maxCachedBytes
        {
            var released = false
            for i in AllocatorClassCount
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

    mtd releaseThreadHeap(heap: *AllocatorThreadHeap)
    {
        for i in AllocatorClassCount
        {
            .drainThreadRemote(heap, i)
            while heap.classes[i].firstFree do
                .releaseThreadCached(heap, i)
        }
    }

    mtd releaseThreadHeapRecord(heap: *AllocatorThreadHeap)
    {
        .rawFree(heap)
    }

    mtd releaseRetiredHeaps()
    {
        var prev: #null *AllocatorThreadHeap
        var heap: #null *AllocatorThreadHeap = .firstRetiredHeap
        while heap
        {
            let next = heap.nextRetired
            if atomicGet(&heap.activeCount) == 0
            {
                if !prev do
                    .firstRetiredHeap = next
                else do
                    prev.nextRetired = next
                .releaseThreadHeapRecord(heap)
            }
            else do
                prev = heap
            heap     = next
        }
    }

    mtd acquireThreadCached(heap: *AllocatorThreadHeap, classIndex: u32, size: u64)->#null *AllocatorHeader
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
        cls.cachedCount  -= 1
        cls.cachedBytes  -= header.blockSize
        heap.cachedCount -= 1
        heap.cachedBytes -= header.blockSize
        .statSub(&.sizeCached, header.blockSize)
        .statSub(&.sizeFree, header.userSize)
        .statSub(&.countFree, 1)

        header.prevFree, header.nextFree = null
        header.userSize                  = size
        return header
    }

    mtd userAddress(header: *AllocatorHeader)->[*] u8
    {
        return cast([*] u8) header + #sizeof(AllocatorHeader)
    }

    mtd footer(header: *AllocatorHeader)->*AllocatorFooter
    {
        return cast(*AllocatorFooter) (.userAddress(header) + header.userSize)
    }

    mtd checkFree(header: *AllocatorHeader)
    {
        let foot = .footer(header)
        if header.magic != MagicFree or foot.magic != MagicFree
        {
            @panic("memory block corruption", #curlocation)
        }
    }

    mtd checkAllocated(header: *AllocatorHeader, callerLoc = #callerlocation)
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
            @panic("memory block is freed twice", loc)
        }
    }

    mtd assertIsAllocated(addr: #null *void, callerLoc = #callerlocation)
    {
        if !addr do
            return

        let header = cast(*AllocatorHeader) (cast([*] u8) addr - #sizeof(AllocatorHeader))
        .checkAllocated(header, callerLoc)
    }

    mtd unlinkAllocated(header: *AllocatorHeader)
    {
        if !header.prev do
            .firstAlloc = header.next
        else do
            header.prev.next = header.next

        if header.next do
            header.next.prev = header.prev

        header.prev, header.next = null
    }

    mtd linkAllocated(header: *AllocatorHeader)
    {
        header.prev = null
        header.next = .firstAlloc
        if header.next do
            header.next.prev = header
        .firstAlloc          = header
    }

    mtd unlinkFree(header: *AllocatorHeader)
    {
        if !header.prev do
            .firstFree = header.next
        else do
            header.prev.next = header.next

        if header.next do
            header.next.prev = header.prev
        else do
            .lastFree = header.prev

        let isCached = header.classIndex != AllocatorInvalidClass and (header.prevFree or header.nextFree or .classes[header.classIndex].firstFree == header)
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
        header.prev, header.next         = null
        header.prevFree, header.nextFree = null
    }

    mtd linkFree(header: *AllocatorHeader)
    {
        header.prev = null
        header.next = .firstFree
        if .firstFree do
            .firstFree.prev = header
        .firstFree          = header
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
            cls.firstFree              = header
            cls.cachedCount            += 1
            cls.cachedBytes            += header.blockSize
            .statAdd(&.sizeCached, header.blockSize)
        }
    }

    mtd releaseBlock(header: *AllocatorHeader)
    {
        .checkFree(header)
        .unlinkFree(header)

        .releaseUncached(header)
    }

    mtd releaseUncached(header: *AllocatorHeader)
    {
        .checkFree(header)

        let freeAddr = header.allocAddr

        @memset(header, FreeByte, #sizeof(AllocatorHeader))
        .rawFree(freeAddr)
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

    mtd acquireCached(classIndex: u32, size: u64)->#null *AllocatorHeader
    {
        if .electricMode or classIndex == AllocatorInvalidClass do
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

    mtd allocateBlock(request: *AllocatorRequest, blockSize: u64, classIndex: u32)->#null *AllocatorHeader
    {
        let alignment = request.alignment orelse cast(u32) #sizeof(*void)
        let toAddAlign = memAlign(#sizeof(AllocatorHeader), alignment)

        let allocSize = toAddAlign + blockSize + #sizeof(AllocatorFooter)
        let address = .rawAlloc(allocSize, alignment)
        if !address do
            return null

        var userAddr = cast([*] u8) address
        userAddr += toAddAlign

        let header = cast(*AllocatorHeader) (userAddr - #sizeof(AllocatorHeader))
        header.allocAddr  = address
        header.allocSize  = allocSize
        header.blockSize  = blockSize
        header.classIndex = classIndex
        header.alignment  = alignment
        return header
    }

    mtd setupAllocatedHeader(header: *AllocatorHeader, request: *AllocatorRequest, heap: *AllocatorThreadHeap)
    {
        header.magic                     = MagicAlloc
        header.userSize                  = request.size
        header.loc                       = request.callerLoc
        header.hint                      = request.hint
        header.stackCount                = .captureAllocStack ? __captureStack(2, @mkslice(&header.stack[0], @countof(header.stack))) : 0
        header.ownerHeap                 = heap
        header.prev, header.next         = null
        header.prevFree, header.nextFree = null
        header.isTracked                 = .trackAllocations
        discard @atomadd(&heap.activeCount, 1)

        let foot = .footer(header)
        foot.magic = MagicAlloc

        if .fillAlloc do
            @memset(.userAddress(header), AllocByte, request.size)

        header.allocId = @atomadd(&.nextId, 1) + 1
        if header.allocId == .breakOnAllocId do
            @assert(false)

        .statAdd(&.countAlloc, 1)
        .statAdd(&.sizeAlloc, request.size)
        if header.isTracked do
            .linkAllocated(header)
        request.address = .userAddress(header)
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

        let classIndex = sizeClass(request.size)
        let blockSize  = classIndex == AllocatorInvalidClass ? request.size : classSize(classIndex)
        let heap       = .threadHeap()

        var header: #null *AllocatorHeader
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
            .freeBlock(request)
            return
        }

        let oldAddress = request.address
        let oldHeader  = cast(*AllocatorHeader) (cast([*] u8) oldAddress - #sizeof(AllocatorHeader))
        .checkAllocated(oldHeader, request.callerLoc)

        if request.size <= oldHeader.blockSize and (request.alignment == 0 or request.alignment <= oldHeader.alignment)
        {
            let oldSize = oldHeader.userSize
            let oldFoot = .footer(oldHeader)
            oldFoot.magic      = 0
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
        allocReq.address = null
        .allocate(&allocReq)
        if !allocReq.address
        {
            request.address = null
            return
        }

        @memcpy(allocReq.address, oldAddress, copySize)

        var freeReq = dref request
        freeReq.address = oldAddress
        freeReq.size    = oldHeader.userSize
        .freeBlock(&freeReq)

        request.address = allocReq.address
    }

    mtd freeBlock(request: *AllocatorRequest)
    {
        if !request.address do
            return

        let userAddr = cast([*] u8) request.address
        let header = cast(*AllocatorHeader) (userAddr - #sizeof(AllocatorHeader))
        .checkAllocated(header, request.callerLoc)
        let foot = .footer(header)

        // Every allocated block records its owner heap ('setupAllocatedHeader').
        let ownerHeap = notnull cast(#null *AllocatorThreadHeap) header.ownerHeap

        if header.isTracked do
            .unlinkAllocated(header)

        .statSub(&.countAlloc, 1)
        .statSub(&.sizeAlloc, header.userSize)

        if .fillFree do
            @memset(userAddr, FreeByte, header.userSize)

        header.magic = MagicFree
        foot.magic   = MagicFree
        header.loc   = request.callerLoc

        request.address = null

        if .fastPathEnabled(request, header.classIndex)
        {
            let heap = g_AllocatorThreadHeap
            if ownerHeap == heap and ownerHeap.threadId == currentThreadId() and atomicGet(&ownerHeap.retired) == 0
            {
                .pushThreadLocal(ownerHeap, header)
                .trimThreadHeap(ownerHeap)
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

        // Decrement activeCount LAST. It pins ownerHeap: a retired heap is only reclaimed
        // once activeCount hits 0, and the hand-off above (pushThreadRemote in particular)
        // still dereferences ownerHeap after we no longer own the block. Decrementing earlier
        // would let the heap be freed out from under that access.
        discard .decActive(ownerHeap)
    }

    mtd releaseAll()
    {
        let heap = g_AllocatorThreadHeap
        if heap and heap.allocator == me
        {
            g_AllocatorThreadHeap = null
            discard @atomxchg(&heap.retired, 1)
            .releaseThreadHeap(heap)
        }

        while .firstFree do
            .releaseBlock(.firstFree)

        while .firstAlloc
        {
            let header = .firstAlloc
            .unlinkAllocated(header)

            // Every tracked allocated block records its owner heap ('setupAllocatedHeader').
            discard .decActive(notnull cast(#null *AllocatorThreadHeap) header.ownerHeap)
            .statSub(&.countAlloc, 1)
            .statSub(&.sizeAlloc, header.userSize)

            .rawFree(header.allocAddr)
        }

        if heap and heap.allocator == me and atomicGet(&heap.activeCount) == 0 do
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

        @print("\nSwag allocator: memory remains allocated\n")
        @print("---------------------------------------\n")
        @print(.countAlloc)
        if .countAlloc == 1
        {
            @print(" allocation, totaling ")
        }
        else
        {
            @print(" allocations, totaling ")
        }

        printDisplaySize(.sizeAlloc)
        @print("\n")
        @print("---------------------------------------\n")

        var cpt = 0
        while scan
        {
            .checkAllocated(scan)

            @print("\x1b[91m")
            @print("allocation #", scan.allocId, ": size ")
            printDisplaySize(scan.userSize)
            if scan.hint do
                @print(", hint ", scan.hint)
            @print("\n")
            @print("\x1b[36m")
            @print("source: ")
            @print(scan.loc.fileName, ":", scan.loc.lineStart + 1, "\n")
            if scan.stackCount do
                __logStackTrace(@mkslice(&scan.stack[0], scan.stackCount), &scan.loc, false)
            @print("---------------------------------------\n")

            scan = scan.next
            cpt  += 1
            if .showMaxLeaks and cpt >= .showMaxLeaks
            {
                @print("\x1b[91m")
                @print("remaining allocation details omitted; ", .countAlloc, " allocations remain in total\n")
                @print("\x1b[97m")
                break
            }
        }
    }

    mtd release()
    {
        if !.installed() do
            return

        // Serialize against concurrent retireThreadHeap()/releaseRetiredHeaps() touching the
        // retired-heap list. Unlock before the memset (which zeroes the mutex itself).
        .mutex.lock()
        .printLeaks()
        .releaseAll()
        .releaseRetiredHeaps()
        .mutex.unlock()

        @memset(me, 0, #sizeof(Allocator))
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
        .releaseRetiredHeaps()
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

func releaseAllocatorThreadCache()
{
    let heap = g_AllocatorThreadHeap
    if !heap do
        return
    if heap.threadId != currentThreadId() do
        return

    g_AllocatorThreadHeap = null

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
