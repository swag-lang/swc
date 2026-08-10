#global public

using Core, Pixel

// Rasterizes a vector icon document into shared frame lists, one per display size.
//
// The document is a uniform grid of 24-unit cells, one glyph per cell in row-major
// order. Frames are rasterized on demand at the requested logical size times the
// requested device scale, so one vector set stays sharp at any size on any display.
// The theme's own icon set and the standard applications' sets both go through this
// type.
struct IconSet
{
    public
    {
        // The vector document; borrowed, never owned. It must outlive the set.
        drawing: #null const *Svg.Drawing

        // The renderer frame textures are created through; borrowed, never owned.
        #[Swag.Late]
        internal
        renderer: Pixel.IRenderer

        internal
        {
            lists: HashTable'(s32, *ImageList)     // Frame lists by logical size.
            scale: f32                             // Device scale the lists were built at.
        }
    }
}

impl IconSet
{
    // Establishes the vector source and the renderer that owns the frame textures.
    mtd setup(renderer: Pixel.IRenderer, drawing: const *Svg.Drawing)
    {
        .renderer = renderer
        .drawing  = drawing
    }

    // Releases every frame texture and list.
    //
    // Call it while the renderer is alive; dropping the set without it leaks the
    // frame textures until the renderer's own teardown.
    mtd free()
    {
        for key, [value] in .lists
        {
            if @isset(.renderer) do
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

        let drawing = .drawing!
        let cols    = cast(s32) Math.round(drawing.width / 24)
        let rows    = cast(s32) Math.round(drawing.height / 24)
        let cell    = key * cast(s32) .scale

        // Strong supersampling for exact edge coverage, with the internal buffer
        // bounded so a dense display keeps the one-time cost in check.
        var ss = 4'u8
        while ss > 1 and cols * cell * cast(s32) ss > 8192 do
            ss /= 2

        let image = drawing.rasterize(.renderer, cols * cell, rows * cell, ss)
        let list  = Memory.new'ImageList()
        list.set(.renderer.addImage(image), cell, cell)
        .lists.add(key, list)
        return list
    }
}
