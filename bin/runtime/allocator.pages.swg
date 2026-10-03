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

// Two cache lines. The first holds everything the owning thread reads and writes on every
// allocation and free; the second holds the links, the identity, and the fields other threads
// write. Pages of different threads sit side by side in a segment, so a page must never share
// a line with its neighbour, and remote frees must not invalidate the owner's hot line.
#[Swag.Align(64)]
struct AllocatorPage
{
    // Heads of the owner's and the remote free lists, as plain block addresses, zero when empty.
    // The link a free block stores is obfuscated with 'key', the end of a list included. A stray
    // write into a freed block therefore yields an address the pop-time check rejects instead of
    // the address the writer chose, and a free block is recognizable from its first word alone,
    // which is what makes a double free cheap to detect.
    freeList: u64
    key:      u64

    areaStart: u64
    areaEnd:   u64
    carved:    u64

    // Blocks handed out, including those still waiting on 'remoteFree'. Only the owning thread
    // writes it, so the fast paths need no atomic to keep it exact.
    used: u32

    blockSize:  u32
    blockInv:   u32
    blockLimit: u32
    blockShift: u32
    classIndex: u32

    ownerHeap: *AllocatorThreadHeap?
    nextPage:  *AllocatorPage?
    prevPage:  *AllocatorPage?

    remoteFree: u64
    remoteLock: u32

    unitIndex: u32
    state:     AllocatorPageState

    // Set while the page sits on its heap's full list, where the slow path no longer scans it.
    // A remote free that finds it set queues the page for its owner to take back.
    inFull: u32

    // Set while the page is on the allocator's revisit stack, linked through 'revisitNext'. Only
    // the queue and its drain touch these, so a page reused in between keeps them intact.
    revisitQueued: u32
    revisitNext:   u64
}

// The first line is read on every free and changes almost never; the masks, which every thread
// claiming or releasing a page moves, live on a line of their own so they never invalidate it.
struct AllocatorSegment
{
    magic:     u64
    allocator: *void?

    nextSegment: *AllocatorSegment?
    prevSegment: *AllocatorSegment?

    // Pages the segment can ever hand out, which is 64 for small pages and 8 for medium ones.
    usableMask: u64

    unitShift: u32
    pageCount: u32

    // Bit i marks page i as carrying blocks. Pages are claimed by several threads at once, so the
    // mask moves only through compare-exchange.
    #[Swag.Align(64)]
    pageMask: u64

    // Bit i marks free page i as still committed. Recommitting a page and faulting its memory in
    // again costs far more than the page's blocks, so an emptied page stays committed, within a
    // process-wide budget, until a later claim reuses it for any class. A bit is only ever set
    // while the page bit is held and cleared by the thread that claims the page bit next.
    idleMask: u64

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
    reserveBase: [*] u8?

    // First segment-aligned address, and the bump cursor over the segments already created.
    base: u64
    used: u64
    end:  u64
}

private var g_AllocatorArenaMutex:  MutexRW
private var g_AllocatorArenas:      [AllocatorMaxArenas] AllocatorArena
private var g_AllocatorArenaCount:  u32
private var g_AllocatorFreeSegment: *AllocatorSegment?
private var g_AllocatorKeySeed:     u64

// Bytes of free pages left committed for reuse. The process keeps up to a quarter of what it
// has committed, and never less than the floor, so the budget grows with the number of threads
// churning pages while a quiet program holds little.
const AllocatorIdleMinBytes = 8'u64 * 1024 * 1024
private var g_AllocatorIdleBytes: u64

func allocatorIdleBytes()->u64 => atomicGet(&g_AllocatorIdleBytes)

// Committed bytes and the OS calls behind them, published for the allocator's statistics.
var g_AllocatorCommittedBytes:  u64
var g_AllocatorOsCommitCount:   u64
var g_AllocatorOsDecommitCount: u64
var g_AllocatorOsReserveCount:  u64

func atomicGet(addr: *u32)->u32 => Swag.atomget(addr)
func atomicGet(addr: *u64)->u64 => Swag.atomget(addr)

func atomicAddU64(addr: *u64, delta: u64)
{
    discard Swag.atomadd(addr, delta)
}

// Two's complement wrap-around: the counters are unsigned and never underflow in a well-formed
// sequence, so subtracting is adding the complement. The wrap is the mechanism, not an accident.
#[Swag.Safety(.Overflow, false)]
{
    func atomicSubU64(addr: *u64, delta: u64)
    {
        discard Swag.atomadd(addr, ~delta + 1)
    }

    func atomicSubU32(addr: *u32, delta: u32)
    {
        discard Swag.atomadd(addr, ~delta + 1)
    }
}

// Reserves address space without committing it. The reservation is over-sized so a
// segment-aligned window always fits inside it, because a reservation cannot be released in parts.
private func osReserve(size: u64)->[*] u8? => __hostPageReserve(size)

func allocatorOsCommit(address: u64, size: u64)->bool
{
    if size == 0 do
        return true

    if not __hostPageCommit(cast(*void) address, size) do
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
    var value = seed ^ (Swag.atomadd(&g_AllocatorKeySeed, 0x9E37_79B9_7F4A_7C15'u64) + 0x9E37_79B9_7F4A_7C15'u64)
    value ^= value >> 30
    value *= 0xBF58_476D_1CE4_E5B9'u64
    value ^= value >> 27
    value *= 0x94D0_49BB_1331_11EB'u64
    value ^= value >> 31

    // An odd key keeps an encoded link non-zero for every aligned block address, which is what lets
    // zero stand for "list empty" with no extra flag.
    return value | 1
}

// Out of line, so the fast paths that can detect a corrupted list do not carry the panic's
// arguments in their own frames.
#[Swag.NoInline]
func allocatorCorruptedFreeList()
{
    Swag.panic("allocator free list is corrupted", #curlocation)
}

#[Swag.NoInline]
func allocatorFreedBlockWritten()
{
    Swag.panic("memory block was written after being freed", #curlocation)
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
        .remoteLock  = 0
        .classIndex  = classIndex
        .unitIndex   = unitIndex
        .state       = .Owned
        .inFull      = 0

        .setupBlockDivision(blockSize)
    }

    // Precomputes the exact-division test used to reject an interior or bogus address on free.
    // Multiplying by the inverse of the odd factor and rotating out the power of two turns
    // divisibility into one unsigned comparison. The Newton iteration converges modulo 2^32,
    // so it wraps on purpose.
    #[Swag.Safety(.Overflow, false)]
    mtd setupBlockDivision(blockSize: u32)
    {
        let odd = blockSize >> cast(u32) Swag.bitCountTz(blockSize)
        .blockSize  = blockSize
        .blockShift = cast(u32) Swag.bitCountTz(blockSize)
        .blockLimit = 0xFFFF_FFFF'u32 / blockSize

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
        // An address below the area wraps to a huge offset, so one comparison bounds both ends.
        let offset = address - .areaStart
        if offset >= .areaEnd - .areaStart do
            return false

        return Swag.ror(cast(u32) offset * .blockInv, cast(u8) .blockShift) <= .blockLimit
    }

    #[Swag.Inline]
    mtd encode(address: u64)->u64 => address ^ .key

    #[Swag.Inline]
    mtd decode(link: u64)->u64 => link ^ .key

    // Blocks pushed by other threads and not yet collected. Counted on demand, so a remote free
    // pays one compare-exchange and nothing else.
    mtd remoteCount()->u32
    {
        .lockRemote()
        defer .unlockRemote()

        var count = 0'u32
        var scan  = atomicGet(&.remoteFree)
        while scan != 0
        {
            count += 1
            scan = .nextFree(scan)
        }

        return count
    }

    // 'used' counts the blocks still waiting on the remote list too.
    mtd liveCount()->u32
    {
        let remote = .remoteCount()
        return .used > remote ? .used - remote : 0
    }

    mtd capacityBytes()->u64 => .areaEnd - .areaStart

    mtd lockRemote()
    {
        while Swag.atomcmpxchg(&.remoteLock, 0, 1) != 0 {}
    }

    mtd unlockRemote()
    {
        discard Swag.atomxchg(&.remoteLock, 0)
    }

    // Moves the blocks other threads freed onto the owner's free list. Producers only ever push,
    // and this takes the whole list in one exchange, so a block can never be popped from under a
    // producer that is linking in front of it and no ABA case exists. The lock only orders this
    // detach against 'holdsFreeBlock', which walks the list without taking it.
    mtd collectRemote()
    {
        if atomicGet(&.remoteFree) == 0 do
            return

        .lockRemote()
        var list = Swag.atomxchg(&.remoteFree, 0)
        .unlockRemote()
        var taken = 0'u32

        while list != 0
        {
            let next = .nextFree(list)
            (cast(*u64) list)[] = .encode(.freeList)
            .freeList = list
            list      = next
            taken     += 1
        }

        Swag.assert(.used >= taken)
        .used -= taken
    }

    // Pushes a block freed by a thread that does not own the page. The page metadata outlives every
    // block it carries, so this never dereferences storage that could already be gone. The block
    // belongs to the pusher until the exchange publishes it, so writing its link needs no lock.
    mtd pushRemote(address: u64)
    {
        .markFree(address)
        var head = atomicGet(&.remoteFree)
        while true
        {
            (cast(*u64) address)[] = .encode(head)
            let seen = Swag.atomcmpxchg(&.remoteFree, head, address)
            if seen == head
            {
                // The exchange above is a full barrier, so this read pairs with the owner's
                // 'parkFullPage', which marks the page before reading the remote list again.
                if atomicGet(&.inFull) != 0 do
                    allocatorQueueRevisit(me)
                return
            }

            head = seen
        }
    }

    // Hands out the next block, from the free list first and from the untouched tail after that.
    // Returning zero means the page is exhausted and the caller must look further.
    #[Swag.Inline]
    mtd acquireBlock()->u64
    {
        let block = .freeList
        if block != 0
        {
            .checkStillFree(block)
            .freeList = .nextFree(block)
            .used     += 1

            // Under memory safety, a block handed out must not keep reading as free, or freeing
            // it before its first word is written would look like a double free and cost a walk
            // of the lists.
            #static if #safety(Swag.SafetyWhat.Memory)
            {
                (cast(*u64) block)[] = 0
            }
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
        if .holdsOwnFreeBlock(address) do
            return true
        return .holdsRemoteFreeBlock(address)
    }

    // Walks the owner's list, so only the owning thread, or a caller that holds the page while no
    // heap owns it, may ask.
    mtd holdsOwnFreeBlock(address: u64)->bool
    {
        var scan = .freeList
        while scan != 0
        {
            if scan == address do
                return true
            scan = .nextFree(scan)
        }

        return false
    }

    // Any thread may ask: producers only prepend, and the lock keeps the owner from detaching the
    // list during the walk.
    mtd holdsRemoteFreeBlock(address: u64)->bool
    {
        .lockRemote()
        defer .unlockRemote()

        var scan = atomicGet(&.remoteFree)
        while scan != 0
        {
            if scan == address do
                return true
            scan = .nextFree(scan)
        }

        return false
    }

    // Reads the link a free block stores. Under memory safety, a link that names no block of
    // this page, other than the end of the list, means the block was overwritten after it was
    // freed.
    #[Swag.Inline]
    mtd nextFree(block: u64)->u64
    {
        let next = .decode((cast(const *u64) block)[])
        #static if #safety(Swag.SafetyWhat.Memory)
        {
            if next != 0 and not .isBlockAddress(next) do
                allocatorCorruptedFreeList()
        }

        return next
    }

    // Reports whether a block's first word reads as a free-list link, which every free block
    // holds: the end of the list, or an address inside the page's block area. A live block holds
    // one only by a coincidence of its data with the page key, about one chance in 2^40, so a
    // match calls for a walk of the lists to tell a double free from that. The range test alone
    // is enough to keep coincidences that rare, so the divisibility test is not repeated here.
    #[Swag.Inline, Swag.Safety(.Overflow, false)]
    mtd looksFree(address: u64)->bool
    {
        let next = .decode((cast(const *u64) address)[])
        if next == 0 do
            return true
        return next - .areaStart < .areaEnd - .areaStart
    }

    // Under memory safety, a free block of sixteen bytes or more carries a canary in its second
    // word, derived from the page key. Handing the block out again checks it, so a write through
    // a pointer kept past its free that reaches the start of the block - where an object's fields
    // begin - is reported instead of silently corrupting the next owner's data. The 8-byte class
    // has no room for it.
    #[Swag.Inline]
    mtd markFree(address: u64)
    {
        #static if #safety(Swag.SafetyWhat.Memory)
        {
            if .blockSize >= 16 do
                (cast(*u64) (address + 8))[] = ~.key
        }
    }

    #[Swag.Inline]
    mtd checkStillFree(block: u64)
    {
        #static if #safety(Swag.SafetyWhat.Memory)
        {
            if .blockSize >= 16 and (cast(const *u64) (block + 8))[] != ~.key do
                allocatorFreedBlockWritten()
        }
    }

    #[Swag.Inline]
    mtd releaseBlock(address: u64)
    {
        .markFree(address)
        (cast(*u64) address)[] = .encode(.freeList)
        .freeList = address
        Swag.assert(.used > 0)
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
        return Swag.max(start, base + AllocatorSegmentHeaderBytes)
    }

    mtd pageCommitEnd(index: u32)->u64
    {
        let unitIndex = (index + 1) << .unitShift
        return .segmentBase() + cast(u64) unitIndex * AllocatorPageSize
    }

    // Claims a free page for a size class. Several threads carve pages from the same segment, so
    // the mask moves only through compare-exchange and the loser simply retries.
    mtd acquirePage(classIndex: u32, blockSize: u32)->*AllocatorPage?
    {
        var mask = .pageMask
        while true
        {
            let free = ~mask & .usableMask
            if free == 0 do
                return null

            let index = cast(u32) Swag.bitCountTz(free)
            let bit   = 1'u64 << index
            let seen  = Swag.atomcmpxchg(&.pageMask, mask, mask | bit)
            if seen != mask
            {
                mask = seen
                continue
            }

            let start = .pageCommitStart(index)
            let end   = .pageCommitEnd(index)
            if .takeIdleBit(bit) do
                atomicSubU64(&g_AllocatorIdleBytes, end - start)
            elif not allocatorOsCommit(start, end - start)
            {
                .clearPageBit(bit)
                return null
            }

            let page = &.pages[index]
            page.setup(me, index, classIndex, blockSize)
            return page
        }
    }

    // Returns a page with no live block. It stays committed while the process-wide idle budget
    // allows, so the next page any class needs costs no system call and no page fault; past the
    // budget its units are decommitted and the resident cost drops back to the segment header.
    mtd releasePage(page: *AllocatorPage)
    {
        Swag.assert(page.used == 0)
        let index = page.unitIndex >> .unitShift
        let bit   = 1'u64 << index
        let start = .pageCommitStart(index)
        let size  = .pageCommitEnd(index) - start

        page.state     = .Free
        page.ownerHeap = null
        page.freeList  = 0
        page.carved    = page.areaStart

        if allocatorReserveIdle(size) do
            .setIdleBit(bit)
        else do
            allocatorOsDecommit(start, size)

        .clearPageBit(bit)
    }

    // Decommits every idle page of the segment. A page is claimed first, exactly as an allocation
    // would claim it, so no other thread can be reusing it while its units go away.
    mtd decommitIdlePages()
    {
        var idle = atomicGet(&.idleMask)
        while idle
        {
            let index = cast(u32) Swag.bitCountTz(idle)
            let bit   = 1'u64 << index
            idle &= ~bit

            let mask = atomicGet(&.pageMask)
            if mask & bit do
                continue
            if Swag.atomcmpxchg(&.pageMask, mask, mask | bit) != mask
            {
                idle = atomicGet(&.idleMask)
                continue
            }

            if .takeIdleBit(bit)
            {
                let start = .pageCommitStart(index)
                let size  = .pageCommitEnd(index) - start
                atomicSubU64(&g_AllocatorIdleBytes, size)
                allocatorOsDecommit(start, size)
            }

            .clearPageBit(bit)
        }
    }

    mtd setIdleBit(bit: u64)
    {
        var mask = .idleMask
        while true
        {
            let seen = Swag.atomcmpxchg(&.idleMask, mask, mask | bit)
            if seen == mask do
                return
            mask = seen
        }
    }

    // Clears the idle bit of a page the caller has claimed, and reports whether it was set.
    mtd takeIdleBit(bit: u64)->bool
    {
        var mask = .idleMask
        while mask & bit
        {
            let seen = Swag.atomcmpxchg(&.idleMask, mask, mask & ~bit)
            if seen == mask do
                return true
            mask = seen
        }

        return false
    }

    mtd clearPageBit(bit: u64)
    {
        var mask = .pageMask
        while true
        {
            let seen = Swag.atomcmpxchg(&.pageMask, mask, mask & ~bit)
            if seen == mask do
                return
            mask = seen
        }
    }

    mtd isEmpty()->bool => atomicGet(&.pageMask) == 0
}

// Charges 'size' bytes to the idle budget, or reports that the budget has no room for them.
func allocatorReserveIdle(size: u64)->bool
{
    let budget  = Swag.max(atomicGet(&g_AllocatorCommittedBytes) / 4, AllocatorIdleMinBytes)
    var current = atomicGet(&g_AllocatorIdleBytes)
    while true
    {
        if current + size > budget do
            return false
        let seen = Swag.atomcmpxchg(&g_AllocatorIdleBytes, current, current + size)
        if seen == current do
            return true
        current = seen
    }

    return false
}

// Adds one address-space reservation. The caller holds the arena mutex.
private func allocatorAddArena()->bool
{
    if g_AllocatorArenaCount >= AllocatorMaxArenas do
        return false

    // Reserving one extra segment guarantees an aligned window inside the reservation, because a
    // reservation is released as a whole and cannot be trimmed to alignment.
    let reserved = osReserve(AllocatorArenaSize + AllocatorSegmentSize)
    if not reserved do
        return false

    let arena = &g_AllocatorArenas[g_AllocatorArenaCount]
    arena.reserveBase = reserved
    arena.base        = (cast(u64) reserved + AllocatorSegmentSize - 1) & ~(AllocatorSegmentSize - 1)
    arena.used        = arena.base
    arena.end         = arena.base + AllocatorArenaSize

    atomicAddU64(&g_AllocatorOsReserveCount, 1)

    // Publish the arena only once its bounds are readable, so a concurrent lookup never sees a
    // half-built entry.
    discard Swag.atomadd(&g_AllocatorArenaCount, 1)
    return true
}

// Carves a fresh segment out of the reservations and commits its header.
private func allocatorCreateSegment(unitShift: u32)->*AllocatorSegment?
{
    var chosen: *AllocatorArena?
    for i in g_AllocatorArenaCount
    {
        let arena = &g_AllocatorArenas[i]
        if arena.used + AllocatorSegmentSize <= arena.end
        {
            chosen = arena
            break
        }
    }

    if not chosen
    {
        if not allocatorAddArena() do
            return null
        chosen = &g_AllocatorArenas[g_AllocatorArenaCount - 1]
    }

    // Commit the page table before publishing the address range that contains it. A lookup only
    // ever reads below 'used', so no thread can reach a segment whose header is not yet mapped -
    // not even one asked to free an address that never came from here.
    let arena = chosen
    let base  = arena.used
    if not allocatorOsCommit(base, AllocatorSegmentHeaderBytes) do
        return null

    let segment = cast(*AllocatorSegment) base
    Swag.memset(cast(*void) base, 0, AllocatorSegmentHeaderBytes)
    segment.unitShift  = unitShift
    segment.pageCount  = AllocatorUnitsPerSegment >> unitShift
    segment.usableMask = segment.pageCount >= 64 ? ~0'u64 : (1'u64 << segment.pageCount) - 1
    segment.magic      = AllocatorSegmentMagic

    arena.used += AllocatorSegmentSize
    return segment
}

// Hands the caller a segment shaped for 'unitShift', reusing an emptied one when possible.
func allocatorAcquireSegment(owner: *void, unitShift: u32)->*AllocatorSegment?
{
    g_AllocatorArenaMutex.lock()
    defer g_AllocatorArenaMutex.unlock()

    var prev: *AllocatorSegment?
    var scan: *AllocatorSegment? = g_AllocatorFreeSegment
    while scan
    {
        let next = scan.nextSegment
        if scan.unitShift == unitShift
        {
            if not prev do
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
    if not segment do
        return null

    segment.allocator = owner
    return segment
}

// Returns an emptied segment to the shared pool. Its header stays committed and its address stays
// reserved for the process lifetime, which is what keeps an address-to-page lookup always safe.
func allocatorReleaseSegment(segment: *AllocatorSegment)
{
    Swag.assert(segment.isEmpty())
    segment.decommitIdlePages()

    g_AllocatorArenaMutex.lock()
    defer g_AllocatorArenaMutex.unlock()

    segment.allocator      = null
    segment.prevSegment    = null
    segment.nextSegment    = g_AllocatorFreeSegment
    g_AllocatorFreeSegment = segment
}

// Recovers the page owning an address, or null when the address did not come from a segment. Two
// range tests and a shift replace every per-block header the old layout needed.
#[Swag.Inline, Swag.Safety(.Overflow, false)]
func allocatorPageOf(address: u64)->*AllocatorPage?
{
    // Plain loads: the target is x86-64, where a store is visible to another core in program
    // order, and a caller that reached this address already synchronized with its producer.
    // An address below an arena wraps to a huge offset, so one comparison bounds both ends.
    // The first arena serves every program that stays under a gibibyte of small blocks, so it is
    // tested first without the loop.
    let first = &g_AllocatorArenas[0]
    if address - first.base < first.used - first.base do
        return allocatorPageInSegment(address)

    var index = 1'u32
    while index < g_AllocatorArenaCount
    {
        let arena = &g_AllocatorArenas[index]
        if address - arena.base < arena.used - arena.base do
            return allocatorPageInSegment(address)
        index += 1
    }

    return null
}

// The page of an address known to lie below an arena's bump cursor, where every segment-aligned
// address starts a segment whose header is committed.
#[Swag.Inline]
func allocatorPageInSegment(address: u64)->*AllocatorPage?
{
    let segment = cast(*AllocatorSegment) (address & ~(AllocatorSegmentSize - 1))
    if segment.magic != AllocatorSegmentMagic do
        return null

    let unit = cast(u32) ((address - cast(u64) segment) >> AllocatorPageShift)
    return &segment.pages[unit >> segment.unitShift]
}

#[Swag.Inline]
func allocatorSegmentOf(page: *AllocatorPage)->*AllocatorSegment => cast(*AllocatorSegment) (cast(u64) page & ~(AllocatorSegmentSize - 1))
