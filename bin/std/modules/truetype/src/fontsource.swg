using Core, Swag

private struct FontSourceStorage
{
    late allocator: IAllocator
    references:     s64 = 1
    bytes:          Array'u8
}

// Owns immutable font bytes shared by one or more independently loaded faces.
//
// Copies of this value and faces opened from it retain the same bytes. Each face has its
// own size, glyph slot, and drawing workspace. Separate threads may use their own
// source values when the source allocator supports access from those threads.
// A default value holds no font bytes.
#[Swag.Opaque]
public struct FontSource
{
    private storage: *FontSourceStorage?
}

impl FontSource
{
    mtd opPostCopy()
    {
        if let storage = .storage do
            discard Atomic.add(&storage.references, 1)
    }

    mtd opDrop()
    {
        if let storage = .storage
        {
            .storage = null
            if Atomic.add(&storage.references, -1) == 1
            {
                let allocator = storage.allocator
                Memory.delete(storage, allocator)
            }
        }
    }

    private func takeBytes(bytes: #move Array'u8, allocator: IAllocator)->FontSource
    {
        let storage = Memory.new'FontSourceStorage(allocator)
        storage.allocator = allocator
        storage.bytes     = #move bytes
        return {storage: storage}
    }
}

public impl FontSource
{
    // Takes a snapshot of a font file for subsequent face loads. File errors propagate.
    //
    // Decoding is deferred until [[TrueType.FontSource.loadFace]]. Later writes to or removal
    // of the file do not affect the snapshot. The supplied allocator, or the allocator active
    // at the start of the call, must remain alive until all source copies and faces are gone.
    func loadFile(fileName: string, allocator: IAllocator? = null)->FontSource fail
    {
        let context = Swag.getContext()
        let previousAllocator = context.allocator
        let resolvedAllocator = unwrap (allocator orelse previousAllocator)
        context.allocator = resolvedAllocator
        defer context.allocator = previousAllocator

        var bytes = try File.readAllBytes(fileName)
        return takeBytes(#move bytes, resolvedAllocator)
    }

    // Takes a private snapshot of bytes already in memory.
    //
    // The caller can overwrite or release the input after this call. Allocator lifetime and font
    // decoding follow [[TrueType.FontSource.loadFile]].
    func copy(bytes: const [..] u8, allocator: IAllocator? = null)->FontSource
    {
        let resolvedAllocator = unwrap (allocator orelse Swag.getContext().allocator)
        var owned = Array'u8{allocator: resolvedAllocator}
        owned.add(bytes)
        return takeBytes(#move owned, resolvedAllocator)
    }

    // Borrows the original bytes for inspection, including the original container header.
    //
    // The slice stays valid while this source is alive and retains the same snapshot.
    // A default source answers an empty slice.
    mtd const bytes()->const [..] u8
    {
        if let storage = .storage do
            return storage.bytes.toSlice()
        return ""
    }

    // Loads one zero-based face while retaining this snapshot.
    //
    // Formats, index checks, and face allocator follow [[TrueType.Face.loadAt]]. A default
    // source or invalid input fails. WOFF1 is expanded into storage owned by the face.
    // Destroy the face with [[TrueType.Face.destroy]]. It can outlive this source value.
    mtd const loadFace(faceIndex: u32 = 0, allocator: IAllocator? = null)->*Face fail =>
        try loadFaceBytes(.bytes(), faceIndex, "", allocator, source: me)
}
