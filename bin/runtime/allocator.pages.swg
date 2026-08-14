#global namespace Swag

// The page supplier under the runtime allocator.
//
// Every carved block lives inside a *segment*: a segment-size-aligned region taken from one of a
// few large address-space reservations, whose first bytes hold the page table describing the whole
// region. Masking a block address down to its segment and indexing that table recovers the block's
// size, its owner, and its free list, which is why a live small block carries no header of its own.
// That single property is what removes both the per-block metadata and the per-block OS call.

const AllocatorPageShift       = 16'u64
const AllocatorPageSize        = 1'u64 << AllocatorPageShift
const AllocatorSegmentShift    = 22'u64
const AllocatorSegmentSize     = 1'u64 << AllocatorSegmentShift
const AllocatorUnitsPerSegment = cast(u32) (AllocatorSegmentSize >> AllocatorPageShift)

// Small classes get one 64 KiB unit per page, medium classes get eight. Both hold at least eight
// blocks, which is what keeps the page table's cost per block negligible.
const AllocatorSmallUnitShift  = 0'u32
const AllocatorMediumUnitShift = 3'u32

// One reservation covers a gibibyte of address space and costs no memory until a segment inside it
// is committed. A program that exhausts every reservation keeps working through the header path,
// so this bound degrades throughput rather than failing an allocation.
const AllocatorArenaSize = 1'u64 << 30
const AllocatorMaxArenas = 16'u32

// The host commit unit determines the segment-header prefix and every commit/decommit boundary.
const AllocatorCommitGranularity = AllocatorHostCommitGranularity

private const AllocatorSegmentMagic = 0x5347_4D45_4E54_0001'u64

enum AllocatorPageState
{
    // The page holds no block and its units are decommitted.
    Free

    // A live thread heap owns the page and serves allocations from it.
    Owned

    // The owning heap retired while blocks were still live; any thread may adopt the page.
    Abandoned
}

struct AllocatorPage
{
    // Free-list links are stored obfuscated with 'key'. A stray write into a freed block therefore
    // yields an address the pop-time check rejects, instead of the address the writer chose.
    freeList:   u64
    remoteFree: u64
    key:        u64

    areaStart: u64
    areaEnd:   u64
    carved:    u64

    ownerHeap: #null *AllocatorThreadHeap
    nextPage:  #null *AllocatorPage
    prevPage:  #null *AllocatorPage

    blockSize:  u32
    blockShift: u32
    blockInv:   u32
    blockLimit: u32

    // Blocks handed out, including those still waiting on 'remoteFree'. Only the owning thread
    // writes it, so the fast paths need no atomic to keep it exact.
    used: u32

    // Blocks pushed by another thread and not yet collected. Live blocks are 'used - remoteCount'.
    remoteCount: u32
    remoteLock:  u32

    classIndex: u32
    unitIndex:  u32
    state:      AllocatorPageState
}

struct AllocatorSegment
{
    magic:     u64
    allocator: #null *void

    nextSegment: #null *AllocatorSegment
    prevSegment: #null *AllocatorSegment

    // Bit i marks page i as carrying blocks. Pages are claimed by several threads at once, so the
    // mask moves only through compare-exchange.
    pageMask: u64

    // Pages the segment can ever hand out, which is 64 for small pages and 8 for medium ones.
    usableMask: u64

    unitShift: u32
    pageCount: u32

    pages: [AllocatorUnitsPerSegment] AllocatorPage
}

// The header claims the front of the segment; the first page starts right after it and simply
// holds fewer blocks than its peers, so no address space is lost to the table.
const AllocatorSegmentHeaderBytes = (cast(u64) #sizeof(AllocatorSegment) + AllocatorCommitGranularity - 1) & ~(AllocatorCommitGranularity - 1)

struct AllocatorArena
{
    // The exact reservation. Nothing releases it: an arena lives for the whole process, which is
    // what makes recovering a page from any address safe at any time, and it costs address space
    // rather than memory. The base is kept because it is the only record of what was reserved.
    reserveBase: #null [*] u8

    // First segment-aligned address, and the bump cursor over the segments already created.
    base: u64
    used: u64
    end:  u64
}

private var g_AllocatorArenaMutex: MutexRW
private var g_AllocatorArenas: [AllocatorMaxArenas] AllocatorArena
private var g_AllocatorArenaCount: u32
private var g_AllocatorFreeSegment: #null *AllocatorSegment
private var g_AllocatorKeySeed: u64

// Committed bytes and the OS calls behind them, published for the allocator's statistics.
var g_AllocatorCommittedBytes:  u64
var g_AllocatorOsCommitCount:   u64
var g_AllocatorOsDecommitCount: u64
var g_AllocatorOsReserveCount:  u64

func atomicGet(addr: *u32)->u32 => @atomcmpxchg(addr, 0, 0)
func atomicGet(addr: *u64)->u64 => @atomcmpxchg(addr, 0, 0)

func atomicAddU64(addr: *u64, delta: u64)
{
    discard @atomadd(addr, delta)
}

// Two's complement wrap-around: the counters are unsigned and never underflow in a well-formed
// sequence, so subtracting is adding the complement. The wrap is the mechanism, not an accident.
#[Swag.Safety(.Overflow, false)]
{
    func atomicSubU64(addr: *u64, delta: u64)
    {
        discard @atomadd(addr, ~delta + 1)
    }

    func atomicSubU32(addr: *u32, delta: u32)
    {
        discard @atomadd(addr, ~delta + 1)
    }
}

// Reserves address space without committing it. The reservation is over-sized so a
// segment-aligned window always fits inside it, because a reservation cannot be released in parts.
private func osReserve(size: u64)->#null [*] u8
{
    return __hostPageReserve(size)
}

func allocatorOsCommit(address: u64, size: u64)->bool
{
    if size == 0 do
        return true

    if !__hostPageCommit(cast(*void) address, size) do
        return false

    atomicAddU64(&g_AllocatorCommittedBytes, size)
    atomicAddU64(&g_AllocatorOsCommitCount, 1)
    return true
}

func allocatorOsDecommit(address: u64, size: u64)
{
    if size == 0 do
        return

    __hostPageDecommit(cast(*void) address, size)

    atomicSubU64(&g_AllocatorCommittedBytes, size)
    atomicAddU64(&g_AllocatorOsDecommitCount, 1)
}

// Mixes the segment address, which carries the loader's randomization, with a running counter so
// two pages never share a free-list key. Every step is modular arithmetic by construction: the
// wrap-around is what spreads the bits.
#[Swag.Safety(.Overflow, false)]
private func allocatorNextKey(seed: u64)->u64
{
    var value = seed ^ (@atomadd(&g_AllocatorKeySeed, 0x9E37_79B9_7F4A_7C15'u64) + 0x9E37_79B9_7F4A_7C15'u64)
    value ^= value >> 30
    value *= 0xBF58_476D_1CE4_E5B9'u64
    value ^= value >> 27
    value *= 0x94D0_49BB_1331_11EB'u64
    value ^= value >> 31

    // An odd key keeps an encoded link non-zero for every aligned block address, which is what lets
    // zero stand for "list empty" with no extra flag.
    return value | 1
}

impl AllocatorPage
{
    // The block area of page 'index', which starts after the segment header for the first page.
    mtd setup(segment: *AllocatorSegment, index: u32, classIndex: u32, blockSize: u32)
    {
        let segmentBase = cast(u64) segment
        let unitIndex   = index << segment.unitShift
        var start       = segmentBase + cast(u64) unitIndex * AllocatorPageSize
        let limit       = start + (cast(u64) 1 << segment.unitShift) * AllocatorPageSize

        if start < segmentBase + AllocatorSegmentHeaderBytes do
            start = segmentBase + AllocatorSegmentHeaderBytes

        let blocks = (limit - start) / cast(u64) blockSize

        .freeList    = 0
        .remoteFree  = 0
        .key         = allocatorNextKey(cast(u64) me)
        .areaStart   = start
        .areaEnd     = start + blocks * cast(u64) blockSize
        .carved      = start
        .ownerHeap   = null
        .nextPage    = null
        .prevPage    = null
        .used        = 0
        .remoteCount = 0
        .remoteLock  = 0
        .classIndex  = classIndex
        .unitIndex   = unitIndex
        .state       = .Owned

        .setupBlockDivision(blockSize)
    }

    // Precomputes the exact-division test used to reject an interior or bogus address on free.
    // 'blockSize' splits into a power of two and an odd factor; divisibility by the odd factor is
    // a multiply and a compare against a precomputed limit. The Newton iteration below converges
    // modulo 2^32, so it wraps on purpose.
    #[Swag.Safety(.Overflow, false)]
    mtd setupBlockDivision(blockSize: u32)
    {
        let odd = blockSize >> cast(u32) @bitcounttz(blockSize)
        .blockSize  = blockSize
        .blockShift = cast(u32) @bitcounttz(blockSize)
        .blockLimit = 0xFFFF_FFFF'u32 / odd

        var inverse = odd
        for 5 do
            inverse *= 2 - odd * inverse
        .blockInv = inverse
    }

    // Accepts only an address that starts a block of this page. A free list corrupted by an
    // overflow, an interior pointer, and a stale pointer all fail here rather than later. The
    // divisibility test multiplies modulo 2^32, so it wraps by design.
    #[Swag.Inline, Swag.Safety(.Overflow, false)]
    mtd isBlockAddress(address: u64)->bool
    {
        if address < .areaStart or address >= .areaEnd do
            return false

        let offset = cast(u32) (address - .areaStart)
        if (offset & ((1'u32 << .blockShift) - 1)) != 0 do
            return false

        return (offset >> .blockShift) * .blockInv <= .blockLimit
    }

    #[Swag.Inline]
    mtd encode(address: u64)->u64 => address ^ .key

    #[Swag.Inline]
    mtd decode(link: u64)->u64 => link ^ .key

    mtd liveCount()->u32
    {
        let remote = atomicGet(&.remoteCount)
        return .used > remote ? .used - remote : 0
    }

    mtd capacityBytes()->u64 => .areaEnd - .areaStart

    mtd lockRemote()
    {
        while @atomcmpxchg(&.remoteLock, 0, 1) != 0 {}
    }

    mtd unlockRemote()
    {
        discard @atomxchg(&.remoteLock, 0)
    }

    // Moves the blocks other threads freed onto the owner's free list. A page can alternate between
    // owners and the abandoned list while frees are still arriving, so detaching the intrusive list
    // is serialized with its producers. Once detached, no producer can reach those links again.
    mtd collectRemote()
    {
        .lockRemote()
        if .remoteFree == 0
        {
            .unlockRemote()
            return
        }

        var list = .remoteFree
        .remoteFree = 0
        .unlockRemote()
        var taken = 0'u32

        while list != 0
        {
            let block = .decode(list)
            if !.isBlockAddress(block) do
                @panic("allocator free list is corrupted", #curlocation)

            let next = dref cast(*u64) block
            dref cast(*u64) block = .freeList
            .freeList             = list
            list                  = next
            taken                 += 1
        }

        @assert(.used >= taken)
        .used -= taken
        atomicSubU32(&.remoteCount, taken)
    }

    // Pushes a block freed by a thread that does not own the page. The page metadata outlives every
    // block it carries, so this never dereferences storage that could already be gone.
    mtd pushRemote(address: u64)
    {
        let encoded = .encode(address)
        discard @atomadd(&.remoteCount, 1)

        .lockRemote()
        dref cast(*u64) address = .remoteFree
        .remoteFree             = encoded
        .unlockRemote()
    }

    // Hands out the next block, from the free list first and from the untouched tail after that.
    // Returning zero means the page is exhausted and the caller must look further.
    #[Swag.Inline]
    mtd acquireBlock()->u64
    {
        let head = .freeList
        if head != 0
        {
            let block = .decode(head)
            if !.isBlockAddress(block) do
                @panic("allocator free list is corrupted", #curlocation)
            .freeList = dref cast(*u64) block
            .used     += 1
            return block
        }

        if .carved < .areaEnd
        {
            let block = .carved
            .carved += cast(u64) .blockSize
            .used   += 1
            return block
        }

        return 0
    }

    // Reports whether the block at 'address' is currently waiting on one of the page's free lists.
    // Linear in the number of free blocks, so this belongs to a check a caller asked for, never to
    // the free path.
    mtd holdsFreeBlock(address: u64)->bool
    {
        let wanted = .encode(address)

        var scan = .freeList
        while scan != 0
        {
            if scan == wanted do
                return true
            scan = dref cast(*u64) .decode(scan)
        }

        .lockRemote()
        scan = .remoteFree
        while scan != 0
        {
            if scan == wanted
            {
                .unlockRemote()
                return true
            }

            scan = dref cast(*u64) .decode(scan)
        }

        .unlockRemote()

        return false
    }

    #[Swag.Inline]
    mtd releaseBlock(address: u64)
    {
        dref cast(*u64) address = .freeList
        .freeList               = .encode(address)
        @assert(.used > 0)
        .used -= 1
    }
}

impl AllocatorSegment
{
    mtd segmentBase()->u64 => cast(u64) me

    // The committed extent of one page. The first page shares its unit with the header, which is
    // committed for the segment's whole life, so only the remainder is committed and decommitted.
    mtd pageCommitStart(index: u32)->u64
    {
        let base  = .segmentBase()
        let start = base + cast(u64) (index << .unitShift) * AllocatorPageSize
        return @max(start, base + AllocatorSegmentHeaderBytes)
    }

    mtd pageCommitEnd(index: u32)->u64
    {
        let unitIndex = (index + 1) << .unitShift
        return .segmentBase() + cast(u64) unitIndex * AllocatorPageSize
    }

    // Claims a free page for a size class. Several threads carve pages from the same segment, so
    // the mask moves only through compare-exchange and the loser simply retries.
    mtd acquirePage(classIndex: u32, blockSize: u32)->#null *AllocatorPage
    {
        var mask = .pageMask
        while true
        {
            let free = ~mask & .usableMask
            if free == 0 do
                return null

            let index = cast(u32) @bitcounttz(free)
            let bit   = 1'u64 << index
            let seen  = @atomcmpxchg(&.pageMask, mask, mask | bit)
            if seen != mask
            {
                mask = seen
                continue
            }

            let start = .pageCommitStart(index)
            let end   = .pageCommitEnd(index)
            if !allocatorOsCommit(start, end - start)
            {
                .clearPageBit(bit)
                return null
            }

            let page = &.pages[index]
            page.setup(me, index, classIndex, blockSize)
            return page
        }
    }

    // Returns a page with no live block. Its units are decommitted, so the resident cost of an
    // idle class drops back to the segment header alone.
    mtd releasePage(page: *AllocatorPage)
    {
        @assert(page.used == 0)
        let index = page.unitIndex >> .unitShift
        allocatorOsDecommit(.pageCommitStart(index), .pageCommitEnd(index) - .pageCommitStart(index))

        page.state     = .Free
        page.ownerHeap = null
        page.freeList  = 0
        page.carved    = page.areaStart

        .clearPageBit(1'u64 << index)
    }

    mtd clearPageBit(bit: u64)
    {
        var mask = .pageMask
        while true
        {
            let seen = @atomcmpxchg(&.pageMask, mask, mask & ~bit)
            if seen == mask do
                return
            mask = seen
        }
    }

    mtd isEmpty()->bool => atomicGet(&.pageMask) == 0
}

// Adds one address-space reservation. The caller holds the arena mutex.
private func allocatorAddArena()->bool
{
    if g_AllocatorArenaCount >= AllocatorMaxArenas do
        return false

    // Reserving one extra segment guarantees an aligned window inside the reservation, because a
    // reservation is released as a whole and cannot be trimmed to alignment.
    let reserved = osReserve(AllocatorArenaSize + AllocatorSegmentSize)
    if !reserved do
        return false

    let arena = &g_AllocatorArenas[g_AllocatorArenaCount]
    arena.reserveBase = reserved
    arena.base        = (cast(u64) reserved + AllocatorSegmentSize - 1) & ~(AllocatorSegmentSize - 1)
    arena.used        = arena.base
    arena.end         = arena.base + AllocatorArenaSize

    atomicAddU64(&g_AllocatorOsReserveCount, 1)

    // Publish the arena only once its bounds are readable, so a concurrent lookup never sees a
    // half-built entry.
    discard @atomadd(&g_AllocatorArenaCount, 1)
    return true
}

// Carves a fresh segment out of the reservations and commits its header.
private func allocatorCreateSegment(unitShift: u32)->#null *AllocatorSegment
{
    var chosen: #null *AllocatorArena
    for i in g_AllocatorArenaCount
    {
        let arena = &g_AllocatorArenas[i]
        if arena.used + AllocatorSegmentSize <= arena.end
        {
            chosen = arena
            break
        }
    }

    if !chosen
    {
        if !allocatorAddArena() do
            return null
        chosen = &g_AllocatorArenas[g_AllocatorArenaCount - 1]
    }

    // Commit the page table before publishing the address range that contains it. A lookup only
    // ever reads below 'used', so no thread can reach a segment whose header is not yet mapped -
    // not even one asked to free an address that never came from here.
    let arena = chosen!
    let base  = arena.used
    if !allocatorOsCommit(base, AllocatorSegmentHeaderBytes) do
        return null

    let segment = cast(*AllocatorSegment) base
    @memset(cast(*void) base, 0, AllocatorSegmentHeaderBytes)
    segment.unitShift  = unitShift
    segment.pageCount  = AllocatorUnitsPerSegment >> unitShift
    segment.usableMask = segment.pageCount >= 64 ? ~0'u64 : (1'u64 << segment.pageCount) - 1
    segment.magic      = AllocatorSegmentMagic

    arena.used += AllocatorSegmentSize
    return segment
}

// Hands the caller a segment shaped for 'unitShift', reusing an emptied one when possible.
func allocatorAcquireSegment(owner: *void, unitShift: u32)->#null *AllocatorSegment
{
    g_AllocatorArenaMutex.lock()
    defer g_AllocatorArenaMutex.unlock()

    var prev: #null *AllocatorSegment
    var scan: #null *AllocatorSegment = g_AllocatorFreeSegment
    while scan
    {
        let next = scan.nextSegment
        if scan.unitShift == unitShift
        {
            if !prev do
                g_AllocatorFreeSegment = next
            else do
                prev.nextSegment = next
            scan.nextSegment = null
            scan.prevSegment = null
            scan.allocator   = owner
            return scan
        }

        prev = scan
        scan = next
    }

    let segment = allocatorCreateSegment(unitShift)
    if !segment do
        return null

    segment.allocator = owner
    return segment
}

// Returns an emptied segment to the shared pool. Its header stays committed and its address stays
// reserved for the process lifetime, which is what keeps an address-to-page lookup always safe.
func allocatorReleaseSegment(segment: *AllocatorSegment)
{
    @assert(segment.isEmpty())

    g_AllocatorArenaMutex.lock()
    defer g_AllocatorArenaMutex.unlock()

    segment.allocator      = null
    segment.prevSegment    = null
    segment.nextSegment    = g_AllocatorFreeSegment
    g_AllocatorFreeSegment = segment
}

// Recovers the page owning an address, or null when the address did not come from a segment. Two
// range tests and a shift replace every per-block header the old layout needed.
#[Swag.Inline]
func allocatorPageOf(address: u64)->#null *AllocatorPage
{
    // Plain loads: the target is x86-64, where a store is visible to another core in program
    // order, and a caller that reached this address already synchronized with its producer.
    for i in g_AllocatorArenaCount
    {
        let arena = &g_AllocatorArenas[i]
        if address < arena.base or address >= arena.used do
            continue

        let segment = cast(*AllocatorSegment) (address & ~(AllocatorSegmentSize - 1))
        if segment.magic != AllocatorSegmentMagic do
            return null

        let unit = cast(u32) ((address - cast(u64) segment) >> AllocatorPageShift)
        return &segment.pages[unit >> segment.unitShift]
    }

    return null
}

#[Swag.Inline]
func allocatorSegmentOf(page: *AllocatorPage)->*AllocatorSegment
{
    return cast(*AllocatorSegment) (cast(u64) page & ~(AllocatorSegmentSize - 1))
}
