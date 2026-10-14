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
    lock: u64
    head: *ValueBorrowRecord?
}

private var g_ValueBorrowRegistryAddress: u64

#[Swag.Safety(.All, false), Swag.Sanity(.All, false), Swag.NoInline]
private func valueBorrowRegistry()->*ValueBorrowRegistry
{
    let known = Swag.atomget(&g_ValueBorrowRegistryAddress)
    if known != 0 do
        return cast(*ValueBorrowRegistry, known)
    // Mapped storage survives a JIT compiler instance and a native artifact unloading.
    let shared = __hostProcessStorage(2, #sizeof(ValueBorrowRegistry))
    if not shared do
        __exitError()
    discard Swag.atomxchg(&g_ValueBorrowRegistryAddress, cast(u64, shared))
    return cast(*ValueBorrowRegistry, shared)
}

#[Swag.Safety(.All, false), Swag.Sanity(.All, false), Swag.NoInline]
private func valueBorrowLock(registry: *ValueBorrowRegistry)
{
    while Swag.atomcmpxchg(&registry.lock, 0, 1) != 0 {}
}

#[Swag.Safety(.All, false), Swag.Sanity(.All, false), Swag.NoInline]
private func valueBorrowUnlock(registry: *ValueBorrowRegistry)
{
    discard Swag.atomxchg(&registry.lock, 0)
}

#[Swag.Safety(.All, false), Swag.Sanity(.All, false), Swag.NoInline]
private func valueBorrowRemove(registry: *ValueBorrowRegistry, record: *ValueBorrowRecord)
{
    if record.previous do
        record.previous.next = record.next
    else do
        registry.head = record.next
    if record.next do
        record.next.previous = record.previous
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
    record.previous = null
    record.next     = registry.head
    if registry.head do
        registry.head.previous = record
    registry.head = record
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
    let thread = __hostCurrentThreadId()
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
