using Core

// Owns one host handle and bounds every transfer to a volume's byte range.
// A hidden view never resizes its host. Protection is transient and never changes outer metadata.
#[Swag.NoCopy]
struct VolumeStorage
{
    stream:              File.FileStream
    base:                u64
    limit:               u64
    protectedFirst:      u64
    protectedEnd:        u64
    protectionTriggered: bool
}

impl VolumeStorage
{
    // Forwarders to the host stream; a hidden view reports the size of its range, not of the host.
    mtd isOpen()->bool => .stream.isOpen()
    mtd close() { .stream.close() }
    mtd flush() fail { try .stream.flush() }
    mtd size()->u64 fail => .base ? .limit : try .stream.size()

    // Resizes the host; hidden and protected views cannot.
    mtd resize(size: u64) fail
    {
        if .base or .protectedEnd do
            fail volumeError(.HiddenProtected)
        try .stream.resize(size)
    }

    // Reads `bytes` at `offset` in the range; false when they would cross its end.
    mtd readExactAt(offset: u64, bytes: [..] u8)->bool fail
    {
        let size = try .size()
        if offset > size or bytes.count > size - offset do
            return false
        return try .stream.readExactAt(.base + offset, bytes)
    }

    // Writes `bytes` at `offset` in the range. A write reaching a protected hidden volume trips the
    // protection, which then refuses every write until unmount.
    mtd writeAllAt(offset: u64, bytes: const [..] u8) fail
    {
        let size = try .size()
        if offset > size or bytes.count > size - offset do
            fail volumeError(.Io)
        if .protectionTriggered do
            fail volumeError(.HiddenProtected)
        if .protectedEnd and
           bytes.count and
           offset < .protectedEnd and
           bytes.count > .protectedFirst - Math.min(offset, .protectedFirst)
        {
            .protectionTriggered = true
            fail volumeError(.HiddenProtected)
        }

        try .stream.writeAllAt(.base + offset, bytes)
    }
}
