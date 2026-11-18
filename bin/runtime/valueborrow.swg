#global namespace Swag

// Compiler-owned records live in the borrowing frame. No allocator participates in the guard.
private struct ValueBorrowRecord
{
    next:     *ValueBorrowRecord?
    previous: *ValueBorrowRecord?
    address:  *void
    size:     u64
    threadId: u64
    sequence: u64
}

private const ValueBorrowShardCount = 64
private const ValueBorrowCellCount  = 512
private const ValueBorrowPageShift  = 16
private const ValueBorrowWideShard  = ValueBorrowShardCount

// A borrow that fits in one address page only shares a lock with pages of the same hash.
// Ranges spanning pages go in a separate shard, checked in addition to the affected pages.
#[Swag.Align(64)]
private struct ValueBorrowShard
{
    low:   u64
    high:  u64     // Inclusive, covering every range published by this shard.
    #[Swag.Align(64)]
    lock:  u64
    head:  *ValueBorrowRecord?
    wide:  u64
    epoch: u64
    cells: [ValueBorrowCellCount] u64
}

// Independent threads can order their records for panic cleanup without sharing a
// sequence counter in the usual case. Collisions leave the per-thread order intact.
#[Swag.Align(64)]
private struct ValueBorrowSequence
{
    next: u64
}

private struct ValueBorrowRegistry
{
    extentLock: u64
    published:  u64
    shards:     [ValueBorrowShardCount + 1] ValueBorrowShard
    sequences:  [ValueBorrowShardCount] ValueBorrowSequence
}

// A conservative address range covering every open borrow.
// It has a process-wide storage of its own, so the view generated guards read stays fixed: they
// skip the call for a write outside it. The compiler mirrors this layout.
private struct ValueBorrowExtent
{
    low:  u64
    high: u64     // Zero until the first borrow is published.
}

private const ValueBorrowRegistryKey = 5'u32
private const ValueBorrowExtentKey   = 6'u32

private var g_ValueBorrowRegistryAddress: u64
private var g_ValueBorrowExtentAddress:   u64

#[Swag.Safety(.All, false), Swag.Sanity(.All, false), Swag.NoInline]
private func valueBorrowRegistry()->*ValueBorrowRegistry
{
    let known = Swag.atomicLoad(&g_ValueBorrowRegistryAddress)
    if known != 0 do
        return cast(*ValueBorrowRegistry, known)

    // Mapped storage survives a JIT compiler instance and a native artifact unloading.
    let shared = __hostProcessStorage(ValueBorrowRegistryKey, #sizeof(ValueBorrowRegistry))
    if not shared do
        __exitError()
    discard Swag.atomicExchange(&g_ValueBorrowRegistryAddress, cast(u64, shared))
    return cast(*ValueBorrowRegistry, shared)
}

#[Swag.Safety(.All, false), Swag.Sanity(.All, false), Swag.NoInline]
private func valueBorrowExtent()->*ValueBorrowExtent
{
    let known = Swag.atomicLoad(&g_ValueBorrowExtentAddress)
    if known != 0 do
        return cast(*ValueBorrowExtent, known)

    let shared = __hostProcessStorage(ValueBorrowExtentKey, #sizeof(ValueBorrowExtent))
    if not shared do
        __exitError()
    discard Swag.atomicExchange(&g_ValueBorrowExtentAddress, cast(u64, shared))
    return cast(*ValueBorrowExtent, shared)
}

#[Swag.Safety(.All, false), Swag.Sanity(.All, false), Swag.NoInline]
private func valueBorrowLock(lock: *u64)
{
    for
    {
        if Swag.atomicCompareExchange(lock, 0, 1) == 0 do
            return

        // Mapped registries can have different virtual addresses in different artifacts.
        // Poll shared bytes, and yield if the holder cannot finish within a short spin.
        var spins: u32
        while Swag.atomicLoad(lock) != 0
        {
            spins += 1
            if spins == 64
            {
                __hostThreadYield()
                spins = 0
            }
        }
    }
}

#[Swag.Safety(.All, false), Swag.Sanity(.All, false), Swag.Inline]
private func valueBorrowPageIndex(page: u64)->u64 => (page ^ (page >> 6) ^ (page >> 12)) & (ValueBorrowShardCount - 1)

#[Swag.Safety(.All, false), Swag.Sanity(.All, false), Swag.Inline]
private func valueBorrowShardIndex(start, last: u64)->u64
{
    let page = start >> ValueBorrowPageShift
    return page == last >> ValueBorrowPageShift ? valueBorrowPageIndex(page) : ValueBorrowWideShard
}

#[Swag.Safety(.All, false), Swag.Sanity(.All, false), Swag.Inline]
private func valueBorrowSequence(registry: *ValueBorrowRegistry, thread: u64)->*u64
{
    let index = (thread ^ (thread >> 2) ^ (thread >> 8)) & (ValueBorrowShardCount - 1)
    return &registry.sequences[index].next
}

// Published ranges only widen. Publishing a new shard or a wider range takes the shared
// lock; steady-state registration and removal only touch the owning shard.
#[Swag.Safety(.All, false), Swag.Sanity(.All, false), Swag.NoInline]
private func valueBorrowPublish(registry: *ValueBorrowRegistry, index, start, end: u64)
{
    valueBorrowLock(&registry.extentLock)
    defer Swag.atomicStore(&registry.extentLock, 0)
    let extent    = valueBorrowExtent()
    let published = Swag.atomicLoad(&registry.published)
    let bit       = index == ValueBorrowWideShard ? 0'u64 : 1'u64 << index
    let oldLow    = Swag.atomicLoad(&extent.low)
    let oldHigh   = Swag.atomicLoad(&extent.high)
    let low       = oldHigh == 0 ? start : Swag.min(oldLow, start)
    let high      = Swag.max(oldHigh, end)
    if low != oldLow do
        Swag.atomicStore(&extent.low, low)
    if high != oldHigh do
        Swag.atomicStore(&extent.high, high)
    if published & bit == 0 do
        Swag.atomicStore(&registry.published, published | bit)
}

// A counting filter lets unrelated writes avoid the shard lock. Hash collisions
// only request the exact overlap check. Large or wrapping ranges always take that check.
#[Swag.Safety(.All, false), Swag.Sanity(.All, false)]
private func valueBorrowCell(block: u64)->u64 => (block ^ (block >> 12) ^ (block >> 24)) & (ValueBorrowCellCount - 1)

#[Swag.Safety(.All, false), Swag.Sanity(.All, false)]
private func valueBorrowFilterChange(shard: *ValueBorrowShard, address: *void, size, delta: u64)
{
    if size == 0 do
        return

    // The shard lock serializes writers. Atomic publication is needed for the
    // lock-free readers, but locked read-modify-write instructions are redundant.
    let epoch = Swag.atomicLoad(&shard.epoch)
    Swag.atomicStore(&shard.epoch, epoch + 1)
    let start = cast(u64, address)
    if size - 1 > ~start or ((start + size - 1) >> 6) - (start >> 6) >= 8
    {
        Swag.atomicStore(&shard.wide, Swag.atomicLoad(&shard.wide) + delta)
        Swag.atomicStore(&shard.epoch, epoch + 2)
        return
    }

    let last = (start + size - 1) >> 6
    for var block = start >> 6; block <= last; block += 1
    {
        let cell = &shard.cells[valueBorrowCell(block)]
        Swag.atomicStore(cell, Swag.atomicLoad(cell) + delta)
    }

    Swag.atomicStore(&shard.epoch, epoch + 2)
}

#[Swag.Safety(.All, false), Swag.Sanity(.All, false)]
private func valueBorrowFilterMiss(shard: *ValueBorrowShard, start, size: u64)->bool
{
    // A stable even epoch makes the lock-free reads one consistent filter snapshot.
    let epoch = Swag.atomicLoad(&shard.epoch)
    if epoch & 1 != 0 or Swag.atomicLoad(&shard.wide) != 0 or size - 1 > ~start do
        return false
    let first = start >> 6
    let last  = (start + size - 1) >> 6
    if last - first >= 8 do
        return false
    for var block = first; block <= last; block += 1
    {
        if Swag.atomicLoad(&shard.cells[valueBorrowCell(block)]) != 0 do
            return false
    }

    return epoch == Swag.atomicLoad(&shard.epoch)
}

#[Swag.Safety(.All, false), Swag.Sanity(.All, false), Swag.NoInline]
private func valueBorrowRemove(shard: *ValueBorrowShard, record: *ValueBorrowRecord)
{
    if record.previous do
        record.previous.next = record.next
    else do
        Swag.atomicStore(cast(*u64, &shard.head), cast(u64, record.next))
    if record.next do
        record.next.previous = record.previous
    valueBorrowFilterChange(shard, record.address, record.size, ~0'u64)
    record.size = 0
}

// Both native artifacts and JIT calls share their registry with their callees.
#[Swag.Safety(.All, false), Swag.Sanity(.All, false), Swag.NoInline]
func __valueBorrowEnter(storage: *void, address: *void, size: u64, _: const *SourceCodeLocation)
{
    let registry = valueBorrowRegistry()
    let thread   = __hostCurrentThreadId()
    let record   = cast(*ValueBorrowRecord, storage)
    record.address  = address
    record.size     = size
    record.threadId = thread
    record.sequence = Swag.atomicAdd(valueBorrowSequence(registry, thread), 1) + 1

    // An extent that wraps the address space ends at its top.
    let start = cast(u64, address)
    let last  = size - 1 > ~start ? ~0'u64 : start + (size - 1)
    let index = valueBorrowShardIndex(start, last)
    let shard = &registry.shards[index]
    valueBorrowLock(&shard.lock)
    valueBorrowFilterChange(shard, address, size, 1)

    let low  = Swag.atomicLoad(&shard.low)
    let high = Swag.atomicLoad(&shard.high)
    if high == 0 or start < low or last > high
    {
        let newLow = high == 0 ? start : Swag.min(low, start)
        let end    = last == ~0'u64 ? last : last + 1
        valueBorrowPublish(registry, index, start, end)
        Swag.atomicStore(&shard.low, newLow)
        Swag.atomicStore(&shard.high, Swag.max(high, last))
    }

    record.previous = null
    record.next     = shard.head
    if shard.head do
        shard.head.previous = record
    Swag.atomicStore(cast(*u64, &shard.head), cast(u64, record))
    Swag.atomicStore(&shard.lock, 0)
}

#[Swag.Safety(.All, false), Swag.Sanity(.All, false), Swag.NoInline]
func __valueBorrowLeave(storage: *void)
{
    let record = cast(*ValueBorrowRecord, storage)
    // A resume boundary can return normally after panic cleanup removed its record.
    if record.size == 0 do
        return

    let registry = valueBorrowRegistry()
    let start    = cast(u64, record.address)
    let last     = record.size - 1 > ~start ? ~0'u64 : start + (record.size - 1)
    let shard    = &registry.shards[valueBorrowShardIndex(start, last)]
    valueBorrowLock(&shard.lock)
    valueBorrowRemove(shard, record)
    Swag.atomicStore(&shard.lock, 0)
}

#[Swag.Safety(.All, false), Swag.Sanity(.All, false), Swag.NoInline]
private func valueBorrowResetShard(shard: *ValueBorrowShard, thread, checkpoint: u64)
{
    if Swag.atomicLoad(cast(*u64, &shard.head)) == 0 do
        return

    valueBorrowLock(&shard.lock)
    defer Swag.atomicStore(&shard.lock, 0)
    var current = shard.head
    while current
    {
        let next = current.next
        if current.threadId == thread and current.sequence > checkpoint do
            valueBorrowRemove(shard, current)
        current = next
    }
}

// A panic can leave generated frames without running their deferred cleanup.
#[Swag.Safety(.All, false), Swag.Sanity(.All, false), Swag.NoInline]
func __valueBorrowReset(checkpoint: u64 = 0)
{
    let registry = valueBorrowRegistry()
    let thread   = __hostCurrentThreadId()
    var shards   = Swag.atomicLoad(&registry.published)
    while shards != 0
    {
        let index = Swag.trailingZeros(shards)
        valueBorrowResetShard(&registry.shards[index], thread, checkpoint)
        shards &= shards - 1
    }
    valueBorrowResetShard(&registry.shards[ValueBorrowWideShard], thread, checkpoint)
}

#[Swag.Safety(.All, false), Swag.Sanity(.All, false)]
private func valueBorrowOverlaps(shard: *ValueBorrowShard, start, size: u64)->bool
{
    // Disjoint ranges miss without observing the filter or touching the lock's cache line.
    let low = Swag.atomicLoad(&shard.low)
    if start > Swag.atomicLoad(&shard.high) or (start < low and low - start >= size) do
        return false
    if Swag.atomicLoad(cast(*u64, &shard.head)) == 0 do
        return false
    if valueBorrowFilterMiss(shard, start, size) do
        return false

    valueBorrowLock(&shard.lock)
    defer Swag.atomicStore(&shard.lock, 0)
    var current = shard.head
    while current
    {
        let borrowed = cast(u64, current.address)
        // Subtractions avoid an overflowing end address, including erased byte views.
        if start >= borrowed ? start - borrowed < current.size : borrowed - start < size do
            return true
        current = current.next
    }

    return false
}

#[Swag.Safety(.All, false), Swag.Sanity(.All, false)]
private func valueBorrowCandidates(start, size, published: u64)->u64
{
    if size - 1 > ~start do
        return published
    let first = start >> ValueBorrowPageShift
    let last  = (start + size - 1) >> ValueBorrowPageShift
    if last - first >= ValueBorrowShardCount do
        return published
    if first == last do
        return published & (1'u64 << valueBorrowPageIndex(first))

    var mask: u64
    for page in first until last + 1 do
        mask |= 1'u64 << valueBorrowPageIndex(page)
    return published & mask
}

// Generated guards pass their module's cache of the extent address: they read the extent through
// it and call here only while the cache is still empty or the write falls inside the extent.
#[Swag.Safety(.All, false), Swag.Sanity(.All, false), Swag.NoInline]
func __valueBorrowWrite(address: *void, size: u64, location: const *SourceCodeLocation, cache: *u64? = null)
{
    if cache and Swag.atomicLoad(cache) == 0 do
        Swag.atomicStore(cache, cast(u64, valueBorrowExtent()))
    if size == 0 do
        return
    let registry = valueBorrowRegistry()
    let start = cast(u64, address)
    let wide  = &registry.shards[ValueBorrowWideShard]
    if valueBorrowOverlaps(wide, start, size) do
        Swag.safetyPanic("write overlaps storage borrowed by a value argument", location[])

    var candidates = valueBorrowCandidates(start, size, Swag.atomicLoad(&registry.published))
    while candidates != 0
    {
        let index = Swag.trailingZeros(candidates)
        if valueBorrowOverlaps(&registry.shards[index], start, size) do
            Swag.safetyPanic("write overlaps storage borrowed by a value argument", location[])
        candidates &= candidates - 1
    }
}

// A native panic catch retains the borrows owned by its caller's still-live frames.
#[Swag.Safety(.All, false), Swag.Sanity(.All, false), Swag.NoInline]
func __valueBorrowCheckpoint()->u64
{
    let registry = valueBorrowRegistry()
    let thread   = __hostCurrentThreadId()
    return Swag.atomicLoad(valueBorrowSequence(registry, thread))
}
