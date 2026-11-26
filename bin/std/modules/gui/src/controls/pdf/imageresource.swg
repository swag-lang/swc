#global internal
#global namespace Pdf

using Core, Pixel

private struct ImageResource
{
    allocator:  Swag.IAllocator?
    references: s32 = 1
    image:      Image
    jpeg:       Array'u8
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
        var jpeg: Array'u8
        return create(#move image, #move jpeg)
    }

    func create(image: #move Image, jpeg: #move Array'u8)->ImageReference
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

    mtd const jpeg()->const [..] u8 => .resource!.jpeg.toSlice()

    // Applying a page-specific mask edits a private image.
    mtd edit()->*Image
    {
        let shared = unwrap .resource
        if Atomic.get(&shared.references) != 1
        {
            var pixels = shared.image
            me[] = #move create(#move pixels)
        }

        .resource.jpeg.free()
        return &.resource.image
    }
}
