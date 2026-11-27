#global internal
#global namespace Pdf

using Core, Pixel

enum EncodedImageFilter
{
    Dct
    Flate
    Ccitt
}

struct EncodedFaxParameters
{
    k:           s64
    rows:        s64
    damagedRows: s64
    blackIs1:    bool
    byteAlign:   bool
    endOfLine:   bool
    endOfBlock:  bool = true
}

struct EncodedImageStream
{
    bytes:       Array!{u8}
    filter:      EncodedImageFilter
    channels:    u8
    bits:        u8 = 8
    predictor:   u8 = 1
    invertedInk: u8     // CMYK DCT components whose stored samples use [1 0].
    interpolate: bool
    fax:         EncodedFaxParameters
}

private struct ImageResource
{
    allocator:  Swag.IAllocator?
    references: s32 = 1
    image:      Image
    encoded:    EncodedImageStream
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
        var encoded: EncodedImageStream
        return create(#move image, #move encoded)
    }

    func create(image: #move Image, encoded: #move EncodedImageStream)->ImageReference
    {
        let allocator = Swag.getContext().allocator
        let resource  = Memory.new!{ImageResource}(allocator)
        resource.allocator = allocator
        resource.image     = #move image
        resource.encoded   = #move encoded
        var result: #returntype
        result.resource = resource
        return result
    }

    mtd opPostCopy()
    {
        if let shared = .resource
        {
            Atomic.add(&shared.references, 1)
        }
    }

    mtd opDrop()
    {
        if let shared = .resource where Atomic.add(&shared.references, -1) == 1
        {
            Memory.delete(shared, shared.allocator)
        }

        .resource = null
    }

    mtd const value()->const *Image? => .resource ? &.resource.image : null

    mtd const encoded()->const *EncodedImageStream => &.resource!.encoded

    // Applying a page-specific mask edits a private image.
    mtd edit()->*Image
    {
        let shared = unwrap .resource
        if Atomic.get(&shared.references) != 1
        {
            var pixels = shared.image
            me[] = #move create(#move pixels)
        }

        .resource.encoded = {}
        return &.resource.image
    }
}
