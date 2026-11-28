#global public

private struct SharedByteStorage
{
    allocator:  Swag.IAllocator?
    references: s64 = 1
    bytes:      Array!{u8}
}

// Owns immutable bytes shared by copies of this value.
//
// A default value holds no bytes. Copies share the same storage. The allocator
// that created the buffer and the allocator active at construction must outlive
// every copy. They must support access on each thread that uses this value.
#[Swag.Opaque]
struct SharedBytes
{
    private storage: *SharedByteStorage?
}

impl SharedBytes
{
    // Takes ownership of `bytes` without copying its elements.
    //
    // Mutable views of the supplied array must no longer be used after the move.
    func create(bytes: #move Array!{u8})->SharedBytes
    {
        if bytes.isEmpty()
        {
            return {}
        }

        let allocator = Swag.getContext().allocator
        let storage   = Memory.new!{SharedByteStorage}(allocator)
        storage.allocator = allocator
        storage.bytes     = #move bytes
        var result: #returntype
        result.storage = storage
        return #move result
    }

    mtd opPostCopy()
    {
        if let storage = .storage
        {
            Atomic.add(&storage.references, 1)
        }
    }

    mtd opDrop()
    {
        if let storage = .storage where Atomic.add(&storage.references, -1) == 1
        {
            let allocator = storage.allocator
            Memory.delete(storage, allocator)
        }

        .storage = null
    }

    // Returns a read-only view. The view is valid while any owner keeps the bytes alive.
    mtd const toSlice()->const [..] u8 => .storage ? .storage.bytes.toSlice() : ""
}
