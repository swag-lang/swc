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
    lock:          Swag.Mutex      // Guards the rasterizations against concurrent first use.
    drawing:       Svg.Drawing     // The vector document, parsed once.
    rasters:       HashTable'(s64, Image)     // Rasterizations of `drawing`, by cell size in device pixels.
    embedded:      bool            // Only the unmodified stock document can use the shipped rasters.
    pendingSource: string?         // Static stock source, parsed only when an uncached size needs it.
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
        .embedded      = false
        .pendingSource = null
        .drawing       = try Svg.Drawing.parse(source)
    }

    // Supplies a precomputed sheet for `cell` device pixels per glyph.
    //
    // Call after [[Gui.IconAtlas.setup]], before creating icon sets from this atlas. `image`
    // must represent the same SVG grid at this size; the atlas owns a copy of its pixels. A
    // repeated call replaces that size, and setup discards all supplied rasters. Sizes not
    // supplied still rasterize on demand. Existing renderer textures are not refreshed.
    // Fails without changing the cache if the size is not positive or the image dimensions
    // do not match the document's 24-unit grid.
    mtd setRaster(cell: s32, image: Image) fail
    {
        Sync.scopedLock(&.lock)
        .ensureDrawing()
        let cols = cast(f64, Math.round(.drawing.width / 24))
        let rows = cast(f64, Math.round(.drawing.height / 24))
        if cell <= 0 or
           not image.isValid() or
           cast(f64, image.width) != cols * cell or
           cast(f64, image.height) != rows * cell do
            fail Core.Errors.BadParameterError{"icon raster dimensions do not match the SVG grid"}
        .rasters.add(cast(s64, cell), image)
    }

    // Returns the sheet rasterized with `cell` device pixels per glyph, building it on first use.
    //
    // The image is borrowed from the atlas and stays valid for its lifetime; a caller uploads a
    // copy of it into its own renderer rather than holding this one.
    //
    // Common stock sizes decode their lossless embedded PNG; other sheets are rasterized on the
    // processor, whatever renderer the application draws with. A window builds its controls before
    // it is first shown, and an OpenGL window whose context did offscreen rasterization while still
    // hidden could come up with none of its frames ever reaching the compositor: a taskbar entry
    // and no window, on a display chained through a DisplayLink adapter.
    internal mtd image(cell: s32)->*Image
    {
        Sync.scopedLock(&.lock)

        let key   = cast(s64, cell)
        let found = .rasters.tryFind(key)
        if found do
            return &found.value

        if .embedded
        {
            let bytes = themeIconRaster(cell)
            if bytes do
                return &.rasters.add(key, decodeThemeRaster(bytes)).value
        }

        .ensureDrawing()
        let cols = cast(s32, Math.round(.drawing.width / 24))
        let rows = cast(s32, Math.round(.drawing.height / 24))

        // Strong supersampling for exact edge coverage, with the internal buffer
        // bounded so a dense display keeps the one-time cost in check.
        var ss = 4'u8
        while ss > 1 and cols * cell * cast(s32, ss) > 8192 do
            ss /= 2

        return &.rasters.add(key, .drawing.rasterize(cols * cell, rows * cell, ss)).value
    }

    // The caller holds the atlas lock. Custom sources were already checked by setup.
    private mtd ensureDrawing()
    {
        if let source = .pendingSource
        {
            .drawing       = expect Svg.Drawing.parse(source)
            .pendingSource = null
        }
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
        atlas: *IconAtlas?
    }

    // The renderer frame textures are created through; borrowed, never owned.
    late renderer: Pixel.IRenderer

    lists: HashTable'(s32, *ImageList)     // Frame lists by logical size.
    scale: f32     // Device scale the lists were built at.
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
        for _, value in .lists
        {
            if .renderer != null do
                value.release(.renderer)
            Memory.delete(value)
        }

        .lists.clear()
    }

    // Creates an icon descriptor for glyph `index` displayed at `size` logical pixels.
    //
    // `scale` is the device density to rasterize at — usually the theme atlas scale. A
    // request sharper than the cached lists replaces their textures in place. Previously
    // returned icons keep their frame-list pointers until [[Gui.IconSet.free]]. A coarser
    // request reuses the sharper frames, which minify cleanly.
    mtd icon(index: s32, size: f32, scale: f32)->Icon
    {
        var result: #returntype
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
            // Controls retain Icon values across monitor changes. Their borrowed list must
            // keep its address while its renderer texture is replaced at the new density.
            for key, value in .lists do
                .updateList(value, key, wanted)
            .scale = wanted
        }

        let key   = cast(s32, Math.max(Math.round(size), 1.0))
        let found = .lists.tryFind(key)
        if found do
            return found.value

        let list = Memory.new'ImageList()
        .updateList(list, key, .scale)
        .lists.add(key, list)
        return list
    }

    private mtd updateList(list: *ImageList, size: s32, scale: f32)
    {
        let cell    = size * cast(s32, scale)
        let image   = .atlas!.image(cell)
        let texture = .renderer.addImage(image[])
        list.release(.renderer)
        list.set(texture, cell, cell)
    }
}
