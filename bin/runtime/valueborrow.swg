#global namespace Swag

// Compiler-owned records live in the borrowing frame. No allocator participates in the guard.
private struct ValueBorrowRecord
{
    next:     *ValueBorrowRecord?
    previous: *ValueBorrowRecord?
    address:  *void
    size:     u64
    threadId: u64
    location: const *SourceCodeLocation
}

private struct ValueBorrowRegistry
{
    lock:  u64
    head:  *ValueBorrowRecord?
    wide:  u64
    epoch: u64
    cells: [4096] u64
}

private var g_ValueBorrowRegistryAddress: u64

#[Swag.Safety(.All, false), Swag.Sanity(.All, false), Swag.NoInline]
private func valueBorrowRegistry()->*ValueBorrowRegistry
{
    let known = Swag.atomicLoad(&g_ValueBorrowRegistryAddress)
    if known != 0 do
        return cast(*ValueBorrowRegistry, known)

    // Mapped storage survives a JIT compiler instance and a native artifact unloading.
    let shared = __hostProcessStorage(2, #sizeof(ValueBorrowRegistry))
    if not shared do
        __exitError()
    discard Swag.atomicExchange(&g_ValueBorrowRegistryAddress, cast(u64, shared))
    return cast(*ValueBorrowRegistry, shared)
}

#[Swag.Safety(.All, false), Swag.Sanity(.All, false), Swag.NoInline]
private func valueBorrowLock(registry: *ValueBorrowRegistry)
{
    for
    {
        if Swag.atomicCompareExchange(&registry.lock, 0, 1) == 0 do
            return

        // Poll with ordinary atomic loads while another thread owns the cache line.
        while Swag.atomicLoad(&registry.lock) != 0 {}
    }
}

#[Swag.Safety(.All, false), Swag.Sanity(.All, false), Swag.Inline]
private func valueBorrowUnlock(registry: *ValueBorrowRegistry)
{
    Swag.atomicStore(&registry.lock, 0)
}

// A counting filter lets unrelated writes avoid the shared list lock. Hash collisions
// only request the exact overlap check. Large or wrapping ranges always take that check.
#[Swag.Safety(.All, false), Swag.Sanity(.All, false)]
private func valueBorrowCell(block: u64)->u64 => (block ^ (block >> 12) ^ (block >> 24)) & 4095

#[Swag.Safety(.All, false), Swag.Sanity(.All, false)]
private func valueBorrowFilterChange(registry: *ValueBorrowRegistry, address: *void, size, delta: u64)
{
    if size == 0 do
        return

    // The registry lock serializes writers. Atomic publication is needed for the
    // lock-free readers, but locked read-modify-write instructions are redundant.
    let epoch = Swag.atomicLoad(&registry.epoch)
    Swag.atomicStore(&registry.epoch, epoch + 1)
    let start = cast(u64, address)
    if size - 1 > ~start or ((start + size - 1) >> 6) - (start >> 6) >= 8
    {
        Swag.atomicStore(&registry.wide, Swag.atomicLoad(&registry.wide) + delta)
        Swag.atomicStore(&registry.epoch, epoch + 2)
        return
    }

    let last = (start + size - 1) >> 6
    for var block = start >> 6; block <= last; block += 1
    {
        let cell = &registry.cells[valueBorrowCell(block)]
        Swag.atomicStore(cell, Swag.atomicLoad(cell) + delta)
    }

    Swag.atomicStore(&registry.epoch, epoch + 2)
}

#[Swag.Safety(.All, false), Swag.Sanity(.All, false)]
private func valueBorrowFilterMiss(registry: *ValueBorrowRegistry, start, size: u64)->bool
{
    // A stable even epoch makes the lock-free reads one consistent filter snapshot.
    let epoch = Swag.atomicLoad(&registry.epoch)
    if epoch & 1 != 0 or Swag.atomicLoad(&registry.wide) != 0 or size - 1 > ~start do
        return false
    let first = start >> 6
    let last  = (start + size - 1) >> 6
    if last - first >= 8 do
        return false
    for var block = first; block <= last; block += 1
    {
        if Swag.atomicLoad(&registry.cells[valueBorrowCell(block)]) != 0 do
            return false
    }

    return epoch == Swag.atomicLoad(&registry.epoch)
}

#[Swag.Safety(.All, false), Swag.Sanity(.All, false), Swag.NoInline]
private func valueBorrowRemove(registry: *ValueBorrowRegistry, record: *ValueBorrowRecord)
{
    if record.previous do
        record.previous.next = record.next
    else do
        Swag.atomicStore(cast(*u64, &registry.head), cast(u64, record.next))
    if record.next do
        record.next.previous = record.previous
    valueBorrowFilterChange(registry, record.address, record.size, ~0'u64)
    record.size = 0
}

// Both native artifacts and JIT calls share their registry with their callees.
#[Swag.Safety(.All, false), Swag.Sanity(.All, false), Swag.NoInline]
func __valueBorrowEnter(storage: *void, address: *void, size: u64, location: const *SourceCodeLocation)
{
    let record = cast(*ValueBorrowRecord, storage)
    record.address  = address
    record.size     = size
    record.threadId = __hostCurrentThreadId()
    record.location = location
    let registry = valueBorrowRegistry()
    valueBorrowLock(registry)
    valueBorrowFilterChange(registry, address, size, 1)
    record.previous = null
    record.next     = registry.head
    if registry.head do
        registry.head.previous = record
    Swag.atomicStore(cast(*u64, &registry.head), cast(u64, record))
    valueBorrowUnlock(registry)
}

#[Swag.Safety(.All, false), Swag.Sanity(.All, false), Swag.NoInline]
func __valueBorrowLeave(storage: *void)
{
    let registry = valueBorrowRegistry()
    valueBorrowLock(registry)
    let record = cast(*ValueBorrowRecord, storage)

    // A resume boundary can return normally after panic cleanup removed its record.
    if record.size != 0 do
        valueBorrowRemove(registry, record)
    valueBorrowUnlock(registry)
}

// A panic can leave generated frames without running their deferred cleanup.
#[Swag.Safety(.All, false), Swag.Sanity(.All, false), Swag.NoInline]
func __valueBorrowReset(checkpoint: u64 = 0)
{
    let registry = valueBorrowRegistry()
    let thread   = __hostCurrentThreadId()
    valueBorrowLock(registry)
    var current = registry.head
    while current
    {
        if cast(u64, current) == checkpoint do
            break
        let next = current.next
        if current.threadId == thread do
            valueBorrowRemove(registry, current)
        current = next
    }

    valueBorrowUnlock(registry)
}

#[Swag.Safety(.All, false), Swag.Sanity(.All, false), Swag.NoInline]
func __valueBorrowWrite(address: *void, size: u64, location: const *SourceCodeLocation)
{
    if size == 0 do
        return
    let start    = cast(u64, address)
    let registry = valueBorrowRegistry()

    // A published empty list has no overlap to inspect. Head changes remain atomic
    // under the writer lock; this read only bypasses work while no record is active.
    if Swag.atomicLoad(cast(*u64, &registry.head)) == 0 do
        return
    if valueBorrowFilterMiss(registry, start, size) do
        return
    valueBorrowLock(registry)
    var current  = registry.head
    var conflict = false
    while current
    {
        let borrowed = cast(u64, current.address)

        // Subtractions avoid an overflowing end address, including erased byte views.
        if start >= borrowed ? start - borrowed < current.size : borrowed - start < size
        {
            conflict = true
            break
        }

        current = current.next
    }

    valueBorrowUnlock(registry)
    if conflict
    {
        Swag.safetyPanic("write overlaps storage borrowed by a value argument", location[])
    }
}

// A native panic catch retains the borrows owned by its caller's still-live frames.
#[Swag.Safety(.All, false), Swag.Sanity(.All, false), Swag.NoInline]
func __valueBorrowCheckpoint()->u64
{
    let registry = valueBorrowRegistry()
    let thread   = __hostCurrentThreadId()
    valueBorrowLock(registry)
    var current = registry.head
    var checkpoint: u64
    while current
    {
        if current.threadId == thread
        {
            checkpoint = cast(u64, current)
            break
        }

        current = current.next
    }

    valueBorrowUnlock(registry)
    return checkpoint
}
