#global public

using Core, Pixel

// Owns a vector icon document and the frames rasterized from it, at every size and density asked for.
//
// The document is a uniform grid of 24-unit cells, one glyph per cell in row-major order.
// Rasterizing that grid is the expensive half of an icon set, and its pixels depend only on the
// document, the logical size, and the device scale — never on the renderer they end up in. An
// atlas therefore sits beside the document it owns and is shared by every [[Gui.IconSet]] built
// on it, so a process holding several themes rasterizes each sheet once instead of once per theme.
//
// One atlas per document, for the lifetime of that document: the theme owns the one behind
// [[Gui.Theme.icon]], and an application owns its own beside its icon source.
struct IconAtlas
{
    internal
    {
        lock:    Sync.Mutex                 // Guards the rasterizations against concurrent first use.
        drawing: Svg.Drawing                // The vector document, parsed once.
        rasters: HashTable'(s64, Image)     // Rasterizations of `drawing`, by cell size in device pixels.
    }
}

impl IconAtlas
{
    // Parses `source`, an SVG document laid out as a uniform grid of 24-unit cells.
    //
    // Fails when the document does not parse. Call it once, on an atlas that outlives every
    // icon set built on it; parsing again replaces the document and discards the frames
    // rasterized from the previous one.
    mtd setup(source: string) fail
    {
        Sync.scopedLock(&.lock)
        .rasters.clear()
        .drawing = try Svg.Drawing.parse(source)
    }

    // Returns the sheet rasterized with `cell` device pixels per glyph, building it on first use.
    //
    // The image is borrowed from the atlas and stays valid for its lifetime; a caller uploads a
    // copy of it into its own renderer rather than holding this one. `renderer` only performs the
    // rasterization — the backends agree on the pixels, so the first caller's backend fills an
    // entry that every later one reuses.
    internal mtd image(renderer: IRenderer, cell: s32)->*Image
    {
        Sync.scopedLock(&.lock)

        let key   = cast(s64) cell
        let found = .rasters.tryFind(key)
        if found do
            return &found.value

        let cols = cast(s32) Math.round(.drawing.width / 24)
        let rows = cast(s32) Math.round(.drawing.height / 24)

        // Strong supersampling for exact edge coverage, with the internal buffer
        // bounded so a dense display keeps the one-time cost in check.
        var ss = 4'u8
        while ss > 1 and cols * cell * cast(s32) ss > 8192 do
            ss /= 2

        return &.rasters.add(key, .drawing.rasterize(renderer, cols * cell, rows * cell, ss)).value
    }
}

// Turns the frames of an [[Gui.IconAtlas]] into renderer textures, one frame list per display size.
//
// One set per renderer: the frames are shared through the atlas, and only the textures they are
// uploaded into belong here. The theme's own icon set and the standard applications' sets both
// go through this type.
struct IconSet
{
    public
    {
        // The rasterized document; borrowed, never owned. It must outlive the set.
        atlas: #null *IconAtlas
    }

    // The renderer frame textures are created through; borrowed, never owned.
    #[Swag.Late]
    renderer: Pixel.IRenderer

    lists: HashTable'(s32, *ImageList)     // Frame lists by logical size.
    scale: f32                             // Device scale the lists were built at.
}

impl IconSet
{
    // Establishes the rasterized document and the renderer that owns the frame textures.
    mtd setup(renderer: Pixel.IRenderer, atlas: *IconAtlas)
    {
        .renderer = renderer
        .atlas    = atlas
    }

    // Releases every frame texture and list.
    //
    // Call it while the renderer is alive; dropping the set without it leaks the
    // frame textures until the renderer's own teardown. The frames themselves stay
    // in the atlas, which every other set on that document goes on sharing.
    mtd free()
    {
        for key, value in .lists
        {
            if Swag.isSet(.renderer) do
                value.release(.renderer)
            Memory.delete(value)
        }

        .lists.clear()
    }

    // Creates an icon descriptor for glyph `index` displayed at `size` logical pixels.
    //
    // `scale` is the device density to rasterize at — usually the theme atlas scale. A
    // request sharper than the cached lists drops them, so they rebuild at the new
    // density; a coarser request reuses the sharper frames, which minify cleanly.
    mtd icon(index: s32, size: f32, scale: f32)->Icon
    {
        var result: retval
        result.imageList = .list(size, scale)
        result.index     = index
        result.sizeX     = size
        result.sizeY     = size
        return result
    }

    internal mtd list(size: f32, scale: f32)->*ImageList
    {
        let wanted = Math.max(Math.ceil(scale), 1.0)
        if wanted > .scale
        {
            .free()
            .scale = wanted
        }

        let key   = cast(s32) Math.max(Math.round(size), 1.0)
        let found = .lists.tryFind(key)
        if found do
            return found.value

        let cell  = key * cast(s32) .scale
        let image = .atlas!.image(.renderer, cell)
        let list  = Memory.new'ImageList()
        list.set(.renderer.addImage(image[]), cell, cell)
        .lists.add(key, list)
        return list
    }
}
