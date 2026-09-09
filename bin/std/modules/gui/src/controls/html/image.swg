#global internal

using Core, Pixel

// A document may declare poster-sized vector bounds; cap their cached bitmap allocation.
private const HtmlSvgRasterLimit = 2048.0

// Resolves an offline resource without accepting URL schemes, UNC paths, or device namespaces.
internal func htmlLocalResourcePath(basePath, source: string)->String
{
    if !Path.isValidPathName(source) or Utf8.contains(source, "://") or Utf8.startsWith(source, "data:") do
        return {}
    let colon = Utf8.indexOf(source, ':'rune)
    if colon != Swag.U64.Max and !(WINDOWS and colon == 1 and Latin1.isLetter(source[0])) do
        return {}
    if basePath.count and !Path.isValidPathName(basePath) do
        return {}

    let fileName = Path.isRooted(source) ? String.from(source) : Path.combine(basePath, source)
    if fileName.count >= 2 and Path.isDirectorySeparator(fileName[0]) and Path.isDirectorySeparator(fileName[1]) do
        return {}
    return fileName
}

// One image a document referenced, decoded at most once.
#[Swag.NoDoc]
public struct HtmlImageEntry
{
    source:      String
    image:       Image
    drawing:     Svg.Drawing
    texture:     Texture
    naturalSize: Math.Vector2     // Layout dimensions; cached raster resolution may differ.
    loaded:      bool
    uploaded:    bool
    isVector:    bool
}

// The images of one document, resolved against the folder the document was read from.
//
// A reference that cannot be resolved is remembered as a failure, so a broken `src` repeated a
// hundred times costs one attempt rather than one attempt per layout. Decoding happens while the
// boxes are built, and the upload to the renderer waits for the first paint, because that is the
// first moment a renderer exists.
#[Swag.NoDoc]
public struct HtmlImageCache
{
    basePath: String
    entries:  Array'HtmlImageEntry
    index:    HashTable'(String, u32)
    renderer: IRenderer?
}

impl HtmlImageCache
{
    // Releases every texture this cache uploaded.
    mtd release()
    {
        let renderer = .renderer
        if renderer
        {
            for &entry in .entries where entry.uploaded
            {
                renderer.removeTexture(&entry.texture)
                entry.uploaded = false
            }
        }

        .renderer = null
    }

    mtd opDrop()
    {
        .release()
    }

    mtd clear()
    {
        .release()
        .entries.clear()
        .index.clear()
    }

    // Returns the decoded image for a source reference, or null when there is none to draw.
    //
    // A `data:` reference carries its bytes in the document and decodes in place. Otherwise only
    // a local reference is followed: the engine never opens a network connection for a document
    // it is asked to display, which is what makes viewing an untrusted file safe.
    mtd fetch(source: string)->*HtmlImageEntry?
    {
        if !source.count do
            return null

        let found = .index.tryFind(String.from(source))
        if found do
            return .entries[found!.value].loaded ? &.entries[found!.value] : null

        let slot = cast(u32) .entries.count
        var entry: HtmlImageEntry
        entry.source = source
        .entries.add(#move entry)
        .index.add(String.from(source), slot)

        if Utf8.startsWith(source, "data:")
        {
            let embedded = catch Image.fromDataUri(source) as decodeError
            if decodeError != null do
                return null
            .entries[slot].image       = embedded
            .entries[slot].naturalSize = {cast(f32) embedded.width, cast(f32) embedded.height}
            .entries[slot].loaded      = true
            return &.entries[slot]
        }

        let fileName = htmlLocalResourcePath(.basePath.toString(), source)
        if fileName.isEmpty() do
            return null

        if Path.lowercaseExtension(fileName.toString()) == ".svg"
        {
            let text = catch File.readAllText(fileName) as readError
            if readError != null do
                return null
            let drawing = catch Svg.Drawing.parse(text.toString()) as parseError
            if parseError != null or drawing.width <= 0 or drawing.height <= 0 do
                return null
            .entries[slot].naturalSize = drawing.naturalSize()
            .entries[slot].drawing     = #move drawing
            .entries[slot].isVector    = true
            .entries[slot].loaded      = true
            return &.entries[slot]
        }

        let image = catch Image.load(fileName.toString()) as loadError
        if loadError != null do
            return null

        .entries[slot].image       = image
        .entries[slot].naturalSize = {cast(f32) image.width, cast(f32) image.height}
        .entries[slot].loaded      = true
        return &.entries[slot]
    }

    // Rasterizes vectors at their displayed pixel size, retaining the largest requested raster.
    // Layout only parses the source; invisible vectors do not allocate or render a bitmap.
    mtd texture(renderer: IRenderer, source: string, pixelWidth, pixelHeight: f32)->*Texture?
    {
        let entry = .fetch(source)
        if !entry do
            return null
        if entry!.isVector
        {
            // Keep the source aspect ratio: CSS may stretch the uploaded texture independently.
            let size           = entry!.naturalSize
            let requestedScale = Math.max(pixelWidth / size.x, pixelHeight / size.y)
            let scale          = Math.min(requestedScale, HtmlSvgRasterLimit / Math.max(size.x, size.y))
            let width          = cast(s32) Math.max(Math.ceil(size.x * scale), 1)
            let height         = cast(s32) Math.max(Math.ceil(size.y * scale), 1)
            if entry!.image.width < width or entry!.image.height < height
            {
                if entry!.uploaded
                {
                    .renderer!.removeTexture(&entry!.texture)
                    entry!.uploaded = false
                }

                entry!.image = entry!.drawing.rasterize(width, height)
            }
        }

        if entry!.uploaded do
            return &entry!.texture

        .renderer       = renderer
        entry!.texture  = renderer.addImage(entry!.image)
        entry!.uploaded = true
        return &entry!.texture
    }
}
