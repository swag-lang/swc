#global internal

using Core, Pixel

// One image a document referenced, decoded at most once.
#[Swag.NoDoc]
public struct HtmlImageEntry
{
    source:   String
    image:    Image
    texture:  Texture
    loaded:   bool
    uploaded: bool
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
            .entries[slot].image  = embedded
            .entries[slot].loaded = true
            return &.entries[slot]
        }

        if Utf8.contains(source, "://") or Utf8.startsWith(source, "//") do
            return null

        let fileName = Path.isRooted(source) ? String.from(source) : Path.combine(.basePath.toString(), source)
        let image    = catch Image.load(fileName.toString()) as loadError
        if loadError != null do
            return null

        .entries[slot].image  = image
        .entries[slot].loaded = true
        return &.entries[slot]
    }

    // Returns the texture a reference draws with, uploading it the first time it is needed.
    mtd texture(renderer: IRenderer, source: string)->*Texture?
    {
        let entry = .fetch(source)
        if !entry do
            return null
        if entry!.uploaded do
            return &entry!.texture

        .renderer       = renderer
        entry!.texture  = renderer.addImage(entry!.image)
        entry!.uploaded = true
        return &entry!.texture
    }
}
