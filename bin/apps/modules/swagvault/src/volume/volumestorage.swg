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
    mtd isOpen()->bool => .stream.isOpen()
    mtd close() { .stream.close() }
    mtd flush() fail { .stream.flush() }
    mtd size()->u64 fail => .base ? .limit : try .stream.size()

    mtd resize(size: u64) fail
    {
        if .base or .protectedEnd do
            failWith("Capacity changes are disabled for hidden or protected volumes.", .HiddenProtected)
        .stream.resize(size)
    }

    mtd readExactAt(offset: u64, bytes: [..] u8)->bool fail
    {
        let size = try .size()
        if offset > size or bytes.count > size - offset do
            return false
        return .stream.readExactAt(.base + offset, bytes)
    }

    mtd writeAllAt(offset: u64, bytes: const [..] u8) fail
    {
        let size = try .size()
        if offset > size or bytes.count > size - offset do
            failWith("The transfer exceeds the volume boundary.", .Io)
        if .protectionTriggered do
            failWith("Hidden-volume protection has stopped writes until unmount.", .HiddenProtected)
        if .protectedEnd and bytes.count and offset < .protectedEnd and bytes.count > .protectedFirst - Math.min(offset, .protectedFirst)
        {
            .protectionTriggered = true
            failWith("Hidden-volume protection has stopped writes until unmount.", .HiddenProtected)
        }

        .stream.writeAllAt(.base + offset, bytes)
    }
}
