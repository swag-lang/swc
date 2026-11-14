#global public

using Ogl, Core

// Describes a renderer-owned two-dimensional texture.
//
// The value does not own or release the graphics resource. Its handle is valid
// only for the renderer that created it, and only while that renderer keeps the graphics device
// it was created on: see [[Pixel.Texture.isValid]].
struct Texture
{
    // What the renderer created. The four of them describe one resource, so they are established
    // together when the texture is created and never on their own: a width that disagrees with
    // the storage would silently corrupt every texture coordinate computed from it.

    public readonly
    {
        handle:      TextureHandle = InvalidTextureHandle     // Renderer-specific resource handle.
        pixelFormat: PixelFormat     // Pixel encoding; alpha formats use straight samples.
        width:       s32 = 0         // Width, in texels.
        height:      s32 = 0         // Height, in texels.
    }

    // The device generation of the renderer that created the handle, or zero when that renderer
    // never loses its storage.
    generation: TextureGeneration
}

// Selects how samples are interpolated between neighboring texels.
enum InterpolationMode
{
    Pixel      // Use nearest-neighbor sampling for hard pixel edges.
    Linear     // Blend neighboring texels for smooth scaling.
}

// Selects how source texture coordinates cover a destination shape.
enum UVMode
{
    Fill            // Stretch the complete texture over the destination.
    FillSubRect     // Stretch the configured texture sub-rectangle over the destination.
    Tile            // Repeat the texture over the destination.
}

impl Texture
{
    // Returns the tightly packed texture storage size, in bytes. Planar chroma planes use their
    // rounded-up subsampled dimensions, so odd-sized pictures include the full edge samples.
    mtd const byteCount()->u64
    {
        let width  = cast(u64, .width)
        let height = cast(u64, .height)
        if .pixelFormat == .Yuv420
        {
            let chromaWidth  = width / 2 + width % 2
            let chromaHeight = height / 2 + height % 2
            return width * height + 2 * chromaWidth * chromaHeight
        }
        return width * height * .pixelFormat.bitsPerPixel() / 8
    }

    // Reports whether the texture still names live renderer storage.
    //
    // A texture stops being valid when its renderer loses the graphics device it was created on,
    // even though nobody removed it: the storage went with the device. An owner that keeps the
    // source of its texture uploads it again when this answers `false`; removing a texture that
    // is no longer valid releases nothing and is harmless.
    mtd const isValid()->bool => .handle != InvalidTextureHandle and .generation.isCurrent()

    // Invalidates the descriptor without releasing a renderer resource.
    internal mtd clear()
    {
        Swag.init(me, 1)
    }

    // Describes the resource a renderer just created.
    //
    // Only a renderer calls this: it is the one that knows the handle, the geometry the storage
    // was really allocated with, and the device generation that storage belongs to.
    internal mtd attach(handle: TextureHandle, pixelFormat: PixelFormat, width, height: s32, generation: TextureGeneration = {})
    {
        Swag.assert(handle != InvalidTextureHandle and width > 0 and height > 0)
        .handle      = handle
        .pixelFormat = pixelFormat
        .width       = width
        .height      = height
        .generation  = generation
    }
}

// Names the graphics device a renderer's resources were created on.
//
// A renderer that can lose its device claims a slot for its whole life and stamps every resource
// with the slot's current tag. Losing the device advances the tag, which retires every resource
// stamped before at once, without the renderer having to find their owners. The zero tag is never
// retired: renderers that cannot lose their storage, such as [[Pixel.RenderCpu]], use it.
internal struct TextureGeneration
{
    tag: u32     // Slot in the top byte, device count of that slot below; zero is untracked.
}

private const TextureGenerationSlots     = 256'u32
private const TextureGenerationSlotShift = 24'u32
private const TextureGenerationCountMask = 0x00FF_FFFF'u32

// The current tag of every slot, and whether a renderer holds it. A tag keeps counting across
// owners, so a slot handed to a new renderer does not revive the resources of the previous one.
private var g_TextureGenerationTags:  [TextureGenerationSlots] Swag.AtomicValue'u32
private var g_TextureGenerationOwned: [TextureGenerationSlots] Swag.AtomicValue'u32

internal impl TextureGeneration
{
    // Claims a slot for a renderer that can lose its device, or returns the untracked generation
    // when every slot is taken: that renderer's resources then simply never read as retired.
    func claim()->TextureGeneration
    {
        for slot in 1 until TextureGenerationSlots
        {
            if g_TextureGenerationOwned[slot].compareExchange(0, 1) == 0 do
                return advanceSlot(slot)
        }

        return {}
    }

    // Retires this generation and gives its slot back once the renderer has no device left.
    mtd release()
    {
        if .tag == 0 do
            return
        let slot = .tag >> TextureGenerationSlotShift
        discard advanceSlot(slot)
        g_TextureGenerationOwned[slot].store(0)
        .tag = 0
    }

    // Retires every resource stamped with this generation and returns the generation that follows.
    mtd const next()->TextureGeneration => .tag == 0 ? {} : advanceSlot(.tag >> TextureGenerationSlotShift)

    // Reports whether resources stamped with this generation still belong to a live device.
    #[Swag.Inline]
    mtd const isCurrent()->bool => .tag == 0 or g_TextureGenerationTags[.tag >> TextureGenerationSlotShift].load() == .tag

    private func advanceSlot(slot: u32)->TextureGeneration
    {
        let previous = g_TextureGenerationTags[slot].load()
        var count    = ((previous & TextureGenerationCountMask) + 1) & TextureGenerationCountMask
        if count == 0 do
            count = 1
        let tag = (slot << TextureGenerationSlotShift) | count
        g_TextureGenerationTags[slot].store(tag)
        return {tag}
    }
}
