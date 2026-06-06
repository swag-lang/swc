using Core, TrueType

public struct GlyphAtlas
{
    texture:     Texture
    width:       u32
    height:      u32
    bpp:         u32
    datas:       Array'u8
    dirty:       bool
    curX:        s32
    curY:        s32
    nextY:       s32
}

public struct GlyphDesc
{
    uv:             Math.Rectangle
    atlasIndex:     s32 = -1
    glyphIndex:     u32         // Index in the typeface, used for kerning lookups
    advanceX:       f32
    advanceY:       f32
    shiftX:         f32
    shiftY:         f32
    width:          f32
    height:         f32
}

// Rendering technique requested when creating a Font.
// 'Auto' is the recommended default: the actual technique is chosen at draw time
// from the on-screen pixel size (crisp bitmap when small, MSDF when larger/zoomed).
// 'Bitmap' and 'Msdf' force a single technique.
// A glyph cache is always one of the two concrete modes; 'Auto' only ever lives
// on a Font, never on a cache.
public enum FontRenderMode
{
    Auto
    Bitmap
    Msdf
}

public impl FontRenderMode
{
    // Number of bytes per pixel in the glyph atlas for this render mode
    mtd bytesPerPixel()->u32
    {
        return me == .Msdf ? 3 : 1
    }

    // True if the mode is a distance field (sampled with linear filtering)
    mtd isDistanceField()->bool
    {
        return me == .Msdf
    }
}

// Reference em size and distance-field range used by the size-independent MSDF path.
// A single MSDF atlas rendered at this size serves every draw size and zoom.
const RefEmSize:   u32 = 40
const RefEmSpread: u32 = 8

// On-screen pixel size below which an 'Auto' font rasterizes a crisp bitmap at the
// exact pixel size; at or above it, the size-independent MSDF atlas is used (and
// scales/zooms cleanly). MSDF degrades below this, so bitmap wins for small text.
const AutoMsdfMinPx: f32 = 20.0

// Shared glyph storage for a (typeface, style, render mode, reference size, spread).
// All Fonts that map to the same key share this cache, so a typeface needs a single
// MSDF atlas regardless of how many sizes are used.
public struct GlyphCache
{
    typeFace:          *TypeFace
    renderMode:        FontRenderMode
    refSize:           u32
    spread:            u32
    forceBold:         bool
    forceItalic:       bool

    // Metrics at the reference size, in pixels.
    ascent:            f32
    descent:           f32
    height:            f32
    underlinePos:      f32
    underlineSize:     f32

    atlases:           Array'GlyphAtlas
    glyphRef:          HashTable'(u32, *GlyphDesc)

    // Kerning between two glyph indices, in reference-size pixels (lazily filled).
    // Key = (leftGlyphIndex << 32) | rightGlyphIndex.
    kernRef:           HashTable'(u64, f32)
    dirty:             bool
}

// A Font is a lightweight view over a shared GlyphCache at a given draw size.
// Glyph quads and metrics are scaled by size/refSize when drawn or measured.
public struct Font
{
    cache:             *GlyphCache
    mode:              FontRenderMode      // Creation intent (may be .Auto); the cache is always concrete
    size:              u32
    forceBold:         bool
    forceItalic:       bool

    // Metrics scaled to 'size', in pixels.
    ascent:            f32
    descent:           f32
    height:            f32
    underlinePos:      f32
    underlineSize:     f32

    fullname:          String
}

fileprivate var g_HashFont:       HashTable'(String, *Font)
fileprivate var g_HashGlyphCache: HashTable'(String, *GlyphCache)

#drop
{
    foreach k, v in g_HashFont do
        Memory.delete(v)
    g_HashFont.free()

    foreach k, v in g_HashGlyphCache do
        Memory.delete(v)
    g_HashGlyphCache.free()
}

fileprivate func mulFix(a, b: s32)->s32
{
    let ab = cast(s64) a * cast(s64) b
    return cast(s32) ((ab + 0x8000 - (ab < 0 ? 1 : 0)) >> 16)
}

fileprivate func renderModeName(mode: FontRenderMode)->string
{
    switch mode
    {
    case Auto:
        return "auto"
    case Msdf:
        return "msdf"
    }

    return "bitmap"
}

fileprivate var g_FontLock: Sync.Mutex

// Get or create the shared glyph cache for a (typeface, style, mode, refSize, spread).
// Assumes g_FontLock is held.
fileprivate func acquireGlyphCache(typeFace: *TypeFace, refSize, spread: u32, renderMode: FontRenderMode, forceBold, forceItalic: bool)->*GlyphCache
{
    let key = Format.toString("%_%_%_%_%_%", typeFace.fullname, refSize, forceBold, forceItalic, renderModeName(renderMode), spread)

    let here = g_HashGlyphCache.tryFind(key)
    if here do
        return here.value

    let cache = Memory.new'GlyphCache()
    cache.typeFace    = typeFace
    cache.renderMode  = renderMode
    cache.refSize     = refSize
    cache.spread      = spread
    cache.forceBold   = forceBold
    cache.forceItalic = forceItalic

    assume typeFace.face.setPixelSize(0, refSize)
    let metrics = &typeFace.face.size.metrics
    cache.ascent        = metrics.ascender / 64.0
    cache.descent       = metrics.descender / 64.0
    cache.height        = cache.ascent - cache.descent
    cache.underlinePos  = mulFix(cast(s32) typeFace.face.underlinePosition, metrics.yScale) / 64.0
    cache.underlineSize = mulFix(cast(s32) typeFace.face.underlineThickness, metrics.yScale) / 64.0

    g_HashGlyphCache.add(key, cache)
    return cache
}

public impl Font
{
    mtd opDrop()
    {
    }

    // Scale factor from the shared cache reference size to this Font's draw size
    mtd const scale()->f32
    {
        return cast(f32) .size / cast(f32) .cache.refSize
    }

    // The render mode requested at creation (may be .Auto)
    mtd const renderMode()->FontRenderMode
    {
        return .mode
    }

    // Returns the glyph descriptor of a given rune (in reference-size pixels)
    mtd getGlyphDesc(c: rune)->const *GlyphDesc
    {
        return .cache.getGlyphDesc(c)
    }

    // Returns the glyph descriptor of a given glyph index (in reference-size pixels)
    mtd getGlyphDescByIndex(glyphIndex: u32)->const *GlyphDesc
    {
        return .cache.getGlyphDescByIndex(glyphIndex)
    }

    // Returns the typeface glyph index of a rune
    mtd glyphIndex(c: rune)->u32
    {
        return .cache.typeFace.face.glyphIndex(c)
    }

    // Clear fileprivate caches
    func clearCaches()
    {
        foreach a, b in g_HashFont do
            Memory.delete(b)
        g_HashFont.clear()

        foreach a, b in g_HashGlyphCache do
            Memory.delete(b)
        g_HashGlyphCache.clear()
    }

    // Release the given font
    func release(font: *Font)
    {
        if !font do
            return
        Sync.scopedLock(&g_FontLock)
        g_HashFont.remove(font.fullname)
        Memory.delete(font)
    }

    // Builds (or returns the cached) Font view.
    // 'atlasMode' is the concrete glyph cache mode; 'intent' is the creation mode
    // stored on the Font (may be .Auto). Both take part in the Font key so an auto
    // Font and an explicit MSDF Font of the same size do not collide.
    fileprivate func createView(typeFace: *TypeFace, size, refSize, spread: u32, atlasMode, intent: FontRenderMode, forceBold, forceItalic: bool)->*Font
    {
        Debug.assert(typeFace != null)
        Debug.assert(size > 0)

        let str = Format.toString("%_%_%_%_%_%_%_%", typeFace.fullname, size, forceBold, forceItalic, renderModeName(intent), renderModeName(atlasMode), spread, refSize)

        Sync.scopedLock(&g_FontLock)

        let here = g_HashFont.tryFind(str)
        if here do
            return here.value

        let cache = acquireGlyphCache(typeFace, refSize, spread, atlasMode, forceBold, forceItalic)

        let font = Memory.new'Font()
        font.fullname    = str
        font.cache       = cache
        font.mode        = intent
        font.size        = size
        font.forceBold   = forceBold
        font.forceItalic = forceItalic

        let s = cast(f32) size / cast(f32) refSize
        font.ascent        = cache.ascent * s
        font.descent       = cache.descent * s
        font.height        = cache.height * s
        font.underlinePos  = cache.underlinePos * s
        font.underlineSize = cache.underlineSize * s

        g_HashFont.add(str, font)
        return font
    }

    // Builds a Font for the requested creation mode (spread is internal).
    fileprivate func createMode(typeFace: *TypeFace, size: u32, mode: FontRenderMode, forceBold, forceItalic: bool)->*Font
    {
        switch mode
        {
        case Bitmap:
            // Classic grayscale bitmap, rasterized at the exact pixel size.
            return createView(typeFace, size, size, 0, .Bitmap, .Bitmap, forceBold, forceItalic)
        case Msdf:
            // Multi-channel SDF, size-independent reference atlas.
            return createView(typeFace, size, RefEmSize, RefEmSpread, .Msdf, .Msdf, forceBold, forceItalic)
        }

        // Auto: an MSDF reference view that substitutes a crisp bitmap at small
        // on-screen sizes (resolved per draw, see resolveDrawFont).
        return createView(typeFace, size, RefEmSize, RefEmSpread, .Msdf, .Auto, forceBold, forceItalic)
    }

    // Resolves the concrete Font to rasterize with for a given on-screen pixel size.
    // Non-auto fonts return themselves. An auto Font uses the size-independent MSDF
    // view at or above AutoMsdfMinPx, and a crisp bitmap rasterized at the exact
    // pixel size below it.
    func resolveDrawFont(font: *Font, effectivePx: f32)->*Font
    {
        if font.mode != .Auto do
            return font
        if effectivePx >= AutoMsdfMinPx do
            return font

        var px = cast(s32) Math.round(effectivePx)
        px = Math.clamp(px, 1, cast(s32) AutoMsdfMinPx)
        return createView(font.cache.typeFace, font.size, cast(u32) px, 0, .Bitmap, .Bitmap, font.forceBold, font.forceItalic)
    }

    // Creates a Font of the given typeface and size.
    // 'mode' selects the rendering technique; .Auto (default) gives the best quality
    // at any on-screen size by adapting between a bitmap and MSDF at draw time.
    func create(typeFace: *TypeFace, size: u32, mode = FontRenderMode.Auto, forceBold, forceItalic = false)->*Font
    {
        return createMode(typeFace, size, mode, forceBold, forceItalic)
    }

    // Creates a Font with the given filename and size.
    // 'mode' selects the rendering technique; .Auto (default) adapts at draw time.
    func create(fullname: string, size: u32, mode = FontRenderMode.Auto, forceBold, forceItalic = false)->*Font throw
    {
        Debug.assert(@countof(fullname) != 0)
        Debug.assert(size > 0)

        let typeFace = try TypeFace.load(fullname)
        return createMode(typeFace, size, mode, forceBold, forceItalic)
    }
}

public impl GlyphCache
{
    mtd opDrop()
    {
        foreach k, v in .glyphRef do
            Memory.delete(v)
        .glyphRef.free()
        .kernRef.free()
    }

    // Horizontal kerning between two glyphs, in reference-size pixels (lazily cached).
    // Returns 0 when the typeface has no kerning pair for the couple.
    mtd kerning(leftIndex, rightIndex: u32)->f32
    {
        if !leftIndex or !rightIndex do
            return 0

        let key  = (cast(u64) leftIndex << 32) | cast(u64) rightIndex
        let here = .kernRef.tryFind(key)
        if here do
            return here.value

        // 'kern' is scaled to the current pixel size, so query it at the reference size.
        assume .typeFace.face.setPixelSize(0, .refSize)
        let kv = assume .typeFace.face.getKerning(leftIndex, rightIndex)
        let px = kv.x / 64.0
        .kernRef.add(key, px)
        return px
    }

    // Returns the glyph descriptor of a given rune, rendered at the reference size
    mtd getGlyphDesc(c: rune)->const *GlyphDesc
    {
        return .getGlyphDescByIndex(.typeFace.face.glyphIndex(c))
    }

    // Returns the glyph descriptor of a given glyph index, rendered at the reference size
    mtd getGlyphDescByIndex(glyphIndex: u32)->const *GlyphDesc
    {
        let entry = .glyphRef.tryFind(glyphIndex)
        if entry do
            return entry.value

        // Render the glyph
        let bpp = .renderMode.bytesPerPixel()
        var bmp: const *Bitmap
        switch .renderMode
        {
        case Msdf:
            bmp = assume .typeFace.renderGlyphMsdfByIndex(glyphIndex, .refSize, .spread, .forceBold, .forceItalic)
        default:
            bmp = assume .typeFace.renderGlyphByIndex(glyphIndex, .refSize, .forceBold, .forceItalic)
        }

        // Glyph width in bytes (atlas columns are measured in bytes, rows in pixels)
        let rowBytes = bmp.width * bpp

        // Creates a new atlas if this is the first time, or if the last atlas is full
        var atlas = .atlases.count ? &.atlases.buffer[.atlases.count - 1] : null
        if atlas
        {
            if atlas.curX + rowBytes > atlas.width
            {
                atlas.curX = 0
                if atlas.nextY + bmp.rows > atlas.height do
                    atlas = null
                else do
                    atlas.curY = atlas.nextY
            }
            elif atlas.curY + bmp.rows > atlas.height
            {
                atlas = null
            }
        }

        if !atlas
        {
            var newAtlas: GlyphAtlas
            newAtlas.bpp    = bpp
            let atlasSide   = Math.roundUpToPowerOf2(Math.max(.refSize * 4, Math.max(bmp.width, bmp.rows) * 2))
            newAtlas.width  = atlasSide * newAtlas.bpp
            newAtlas.height = atlasSide
            newAtlas.datas.resize(cast(u64) newAtlas.width * newAtlas.height)
            Memory.clear(newAtlas.datas.buffer, newAtlas.datas.count)
            .atlases.add(newAtlas)
            atlas = &.atlases.buffer[.atlases.count - 1]
        }

        let x = atlas.curX
        let y = atlas.curY
        atlas.curX += rowBytes
        atlas.nextY = Math.max(atlas.nextY, atlas.curY + bmp.rows)

        // Copy the rendered glyph to the atlas datas
        var buffer = atlas.datas.buffer + x + (atlas.width * (atlas.height - 1))
        buffer -= (y * atlas.width)
        var src = bmp.buffer
        for j in bmp.rows
        {
            Memory.copy(buffer, src, cast(u64) rowBytes)
            src += bmp.pitch
            buffer -= atlas.width
        }

        // Setup GlyphDesc
        let refr = Memory.new'GlyphDesc()
        .glyphRef.add(glyphIndex, refr)

        refr.width  = bmp.width
        refr.height = bmp.rows

        let glyph = .typeFace.face.glyph
        refr.glyphIndex = glyph.index
        refr.advanceX   = glyph.advance.x / 64.0
        refr.advanceY   = glyph.advance.y / 64.0
        refr.shiftX     = glyph.bitmapLeft
        refr.shiftY     = glyph.bitmapTop

        // 'x' and the atlas width are measured in bytes; both numerator and
        // denominator carry the bpp factor, so the resulting uv stays correct.
        let widthf  = cast(f32) atlas.width
        let heightf = cast(f32) atlas.height
        refr.uv.x      = x / widthf
        refr.uv.y      = y / heightf
        refr.uv.width  = cast(f32) rowBytes / widthf
        refr.uv.height = refr.height / heightf

        refr.atlasIndex = cast(u32) (.atlases.count - 1)

        .dirty      = true
        atlas.dirty = true

        return refr
    }
}
