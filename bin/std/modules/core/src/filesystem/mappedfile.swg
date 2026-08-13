#global public
#global namespace File

// Access policy for a memory-mapped file and its regions.
enum MapAccess
{
    Read            // Regions expose read-only bytes and never modify the file.
    ReadWrite       // Regions expose writable bytes whose changes can be flushed to the file.
    CopyOnWrite     // Regions expose private writable bytes whose changes are never written to the file.
}

// Owns an open file used to create independently owned mapped regions.
//
// A region keeps the native file resources it needs, so it can outlive this value. Resizing fails
// when the host refuses to resize a file that still has mapped regions; close those regions and
// retry. Closing this value does not invalidate regions already returned by [[Core.File.MappedFile.map]].
#[Swag.NoCopy]
struct MappedFile
{
    public readonly
    {
        name:   String        // Path associated with this file.
        access: MapAccess     // Access granted to every region created from this file.
    }

    internal stream: FileStream
}

impl MappedFile
{
    // Opens an existing file for memory mapping.
    //
    // `ReadWrite` enforces the process write sandbox. `CopyOnWrite` opens the underlying file for
    // reading because private page changes never reach it.
    func open(name: string, access = MapAccess.Read)->MappedFile fail
    {
        var result: retval
        result.name   = name
        result.access = access

        switch access
        {
        case .Read, .CopyOnWrite: result.stream = File.open(name, .Open, .Read, .ReadWrite | .Delete)
        case .ReadWrite:          result.stream = File.open(name, .Open, .ReadWrite, .ReadWrite | .Delete)
        }

        return result
    }

    // Releases this value's open file handle. Repeated calls do nothing.
    mtd close()
    {
        .stream.close()
    }

    // Releases this value's open file handle.
    mtd opDrop()
    {
        .close()
    }

    // Returns whether this value still owns an open file.
    mtd const isOpen()->bool => .stream.isOpen()

    // Returns the current file length in bytes.
    mtd size()->u64 fail
    {
        Debug.assert(.isOpen())
        return .stream.size()
    }

    // Changes the file length.
    //
    // The operation requires `ReadWrite` access and may fail while any process retains a mapped
    // region for this file. Existing regions are never resized implicitly.
    mtd resize(newSize: u64) fail
    {
        Debug.assert(.isOpen())
        Debug.assert(.access == .ReadWrite)
        .stream.resize(newSize)
    }

    // Flushes file data and metadata through the underlying file handle.
    mtd flush() fail
    {
        Debug.assert(.isOpen())
        Debug.assert(.access == .ReadWrite)
        .stream.flush()
    }

    // Maps exactly `length` bytes beginning at `offset`.
    //
    // The range must fit in the file size sampled by this call. Empty regions are supported and
    // own no native view. A non-empty region owns its view and a duplicate file handle, so it can
    // be closed or flushed after this [[Core.File.MappedFile]] is closed.
    mtd map(offset, length: u64)->MappedRegion fail
    {
        Debug.assert(.isOpen())

        let fileSize = .size()
        if offset > fileSize or length > fileSize - offset do
            fail Errors.BadParameterError{}

        var result: retval
        result.offset = offset
        result.length = length
        result.access = .access
        if length do
            result.mapNative(.stream.handle, offset, length, .access)
        result.valid = true
        return result
    }

    // Maps the complete current file.
    mtd mapAll()->MappedRegion fail
    {
        return .map(0, .size())
    }
}

// Owns one contiguous view into a [[Core.File.MappedFile]].
//
// Byte slices returned by this value remain valid until [[Core.File.MappedRegion.close]]. Closing
// the source mapped file does not invalidate them. This value is not safe to close while another
// thread is accessing one of its slices.
#[Swag.NoCopy]
struct MappedRegion
{
    public readonly
    {
        offset: u64           // File byte offset represented by the first byte.
        length: u64           // Number of bytes in the region.
        access: MapAccess     // Access policy applied to this region.
    }

    internal
    {
        view:       #null [*] u8
        nativeView: #null *void
        mapHandle:  FileHandle
        fileHandle: FileHandle
        valid:      bool
    }
}

impl MappedRegion
{
    // Releases this region's view and native handles. Repeated calls do nothing.
    mtd close()
    {
        .closeNative()
    }

    // Releases this region's view and native handles.
    mtd opDrop()
    {
        .close()
    }

    // Returns whether this value represents a valid mapped range.
    //
    // An empty region is valid even though it owns no native view.
    mtd const isOpen()->bool => .valid

    // Returns a read-only view of the mapped bytes.
    mtd const bytes()->const [..] u8
    {
        Debug.assert(.isOpen())
        return @mkslice(.view, .length)
    }

    // Returns a writable view of shared or copy-on-write bytes.
    mtd writableBytes()->[..] u8
    {
        Debug.assert(.isOpen())
        Debug.assert(.access != .Read)
        return @mkslice(.view, .length)
    }

    // Flushes shared writable pages and the duplicated file handle.
    //
    // The operation does nothing for read-only and copy-on-write regions. A successful flush of a
    // `ReadWrite` region makes both the mapped pages and file buffers durable according to the host
    // filesystem's guarantees.
    mtd flush() fail
    {
        Debug.assert(.isOpen())
        if .access != .ReadWrite or !.length do
            return
        .flushNative()
    }
}
