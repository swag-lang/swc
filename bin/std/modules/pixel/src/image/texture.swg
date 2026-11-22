#global public

using Ogl, Core

// Describes a renderer-owned two-dimensional texture.
//
// The value does not own or release the renderer resource. Its handle belongs to the renderer
// that created it; discard every copy after removing the texture or resetting or releasing the
// renderer. See [[Pixel.Texture.isValid]] for the handle and resource-generation check.
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

    // The resource generation of the renderer that created the handle. Zero is reserved for
    // untracked descriptors that do not belong to a live renderer resource.
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
    // Returns the tightly packed texture storage size, in bytes.
    //
    // Planar chroma planes use rounded-up subsampled dimensions, so odd-sized pictures include
    // their full edge samples.
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

    // Reports whether the handle is present and its renderer resource generation is still current.
    //
    // This does not detect removal through another copy of the value. Discard every copy after
    // removing the texture or resetting its renderer. An owner that keeps the source can upload
    // it again after a reset makes this answer `false`.
    mtd const isValid()->bool => .handle != InvalidTextureHandle and .generation.isCurrent()

    // Invalidates the descriptor without releasing a renderer resource.
    internal mtd clear()
    {
        Swag.init(me, 1)
    }

    // Describes the resource a renderer just created.
    //
    // Only a renderer calls this: it is the one that knows the handle, the geometry the storage
    // was really allocated with, and the resource generation that storage belongs to.
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

// Names the renderer resource lifetime a handle was created in.
//
// A renderer claims a slot and stamps its resources with the slot's current tag. Resetting or
// releasing the renderer advances the tag, which retires every resource stamped before at once,
// without the renderer having to find their owners.
internal struct TextureGeneration
{
    tag: u32     // Slot in the top byte, generation count of that slot below; zero is untracked.
}

internal const TextureGenerationSlots    = 256'u32
private const TextureGenerationSlotShift = 24'u32
private const TextureGenerationCountMask = 0x00FF_FFFF'u32

// The current tag of every slot, and whether a renderer holds it. A tag keeps counting across
// owners, so a slot handed to a new renderer does not revive the resources of the previous one.
private var g_TextureGenerationTags:  [TextureGenerationSlots] Swag.AtomicValue'u32
private var g_TextureGenerationOwned: [TextureGenerationSlots] Swag.AtomicValue'u32

internal impl TextureGeneration
{
    // Claims a slot for a renderer resource lifetime.
    func claim()->TextureGeneration fail
    {
        for slot in 1 until TextureGenerationSlots
        {
            if g_TextureGenerationOwned[slot].compareExchange(0, 1) == 0 do
                return advanceSlot(slot)
        }

        fail RenderResourceError{"Renderer cannot track another resource generation: its slots are full"}
    }

    // Retires this generation and gives its slot back when the renderer releases its resources.
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

    // Reports whether resources stamped with this generation still belong to a live renderer.
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
