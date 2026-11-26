#global internal
#global namespace Pdf

using Core, Pixel

struct EncodedJpeg
{
    bytes:    Array'u8
    channels: u8
}

private struct ImageResource
{
    allocator:  Swag.IAllocator?
    references: s32 = 1
    image:      Image
    jpeg:       EncodedJpeg
}

// A decoded page and the reader cache each own their references to read-only pixels.
struct ImageReference
{
    private resource: *ImageResource?
}

impl ImageReference
{
    func create(image: #move Image)->ImageReference
    {
        var jpeg: EncodedJpeg
        return create(#move image, #move jpeg)
    }

    func create(image: #move Image, jpeg: #move EncodedJpeg)->ImageReference
    {
        let allocator = Swag.getContext().allocator
        let resource  = Memory.new'ImageResource(allocator)
        resource.allocator = allocator
        resource.image     = #move image
        resource.jpeg      = #move jpeg
        var result: #returntype
        result.resource = resource
        return result
    }

    mtd opPostCopy()
    {
        if let shared = .resource do
            Atomic.add(&shared.references, 1)
    }

    mtd opDrop()
    {
        if let shared = .resource where Atomic.add(&shared.references, -1) == 1 do
            Memory.delete(shared, shared.allocator)
        .resource = null
    }

    mtd const value()->const *Image? => .resource ? &.resource.image : null

    mtd const jpeg()->const [..] u8 => .resource!.jpeg.bytes.toSlice()

    mtd const jpegChannels()->u8 => .resource!.jpeg.channels

    // Applying a page-specific mask edits a private image.
    mtd edit()->*Image
    {
        let shared = unwrap .resource
        if Atomic.get(&shared.references) != 1
        {
            var pixels = shared.image
            me[] = #move create(#move pixels)
        }

        .resource.jpeg = {}
        return &.resource.image
    }
}
