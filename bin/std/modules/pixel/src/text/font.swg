using Core, TrueType

// Pixel storage for one page of cached glyph bitmaps.
//
// Applications normally obtain atlas data through a [[Pixel.GlyphCache]]. Atlas
// dimensions are expressed in pixels, while `width` and `curX` count bytes for
// multi-channel distance-field textures.
public struct GlyphAtlas
{
    texture: Texture      // GPU texture associated with this atlas page.
    width:   u32          // Row width in bytes.
    height:  u32          // Page height in pixels.
    bpp:     u32          // Bytes used by one atlas pixel.
    datas:   Array'u8     // CPU-side pixel storage.
    dirty:   bool         // Whether `datas` contains changes not uploaded to `texture`.
    curX:    s32          // Byte offset of the next glyph in the current row.
    curY:    s32          // Pixel offset of the current row.
    nextY:   s32          // Pixel offset available for the following row.
}

// Cached placement and metrics for one rendered glyph.
//
// Metric values are measured at the cache reference size. Multiply them by
// [[Pixel.Font.scale]] to obtain values for a particular font view.
public struct GlyphDesc
{
    uv:         Math.Rectangle     // Normalized texture coordinates in the atlas.
    atlasIndex: s32 = -1           // Atlas page containing the glyph, or `-1` when it has no bitmap.
    glyphIndex: u32                // Typeface glyph index, used for kerning lookups.
    advanceX:   f32                // Horizontal pen advance in reference-size pixels.
    advanceY:   f32                // Vertical pen advance in reference-size pixels.
    shiftX:     f32                // Horizontal offset from the pen to the bitmap.
    shiftY:     f32                // Vertical offset from the baseline to the bitmap.
    width:      f32                // Bitmap width in reference-size pixels.
    height:     f32                // Bitmap height in reference-size pixels.
}

// Selects the glyph rendering technique used by a [[Pixel.Font]].
//
// `Auto` is the recommended default and chooses the concrete technique from the
// effective on-screen size. `Bitmap` and `Msdf` force one technique. A glyph cache
// always uses a concrete mode; `Auto` belongs only to a font view.
public enum FontRenderMode
{
    Auto       // Select bitmap or MSDF rendering from the effective on-screen size.
    Bitmap     // Rasterize crisp grayscale glyphs at the exact pixel size.
    Msdf       // Use a size-independent multi-channel signed-distance-field atlas.
}

public impl FontRenderMode
{
    // Returns the glyph-atlas bytes per pixel for this mode.
    //
    // MSDF is 4 (MTSDF): RGB multi-channel field + a true SDF in alpha for effects.
    mtd bytesPerPixel()->u32
    {
        return me == .Msdf ? 4 : 1
    }

    // True if the mode is a distance field (sampled with linear filtering)
    mtd isDistanceField()->bool
    {
        return me == .Msdf
    }
}

// Defines the reference em size and range for size-independent MSDF rendering.
//
// A single MSDF atlas rendered at this size serves every draw size and zoom.
const RefEmSize:   u32 = 40
const RefEmSpread: u32 = 8

// Sets the on-screen threshold where automatic fonts switch to MSDF rendering.
//
// Below this size, an `Auto` font rasterizes a crisp bitmap at the exact pixel size.
// At or above it, the size-independent MSDF atlas scales and zooms cleanly.
const AutoMsdfMinPx: f32 = 20.0

// Stores glyphs shared by compatible [[Pixel.Font]] views.
//
// Fonts with the same typeface, style, render mode, reference size, and spread share
// this cache. A typeface therefore needs only one MSDF atlas across draw sizes.
public struct GlyphCache
{
    typeFace:    *TypeFace = undefined     // Typeface borrowed for rasterization and metrics.
    renderMode:  FontRenderMode            // Concrete atlas representation; never `Auto`.
    refSize:     u32                       // Reference em size in pixels.
    spread:      u32                       // Distance-field range in pixels, or zero for bitmap atlases.
    forceBold:   bool                      // Whether glyph rasterization synthesizes bold weight.
    forceItalic: bool                      // Whether glyph rasterization synthesizes italic slant.
    hasKerning:  bool                      // Whether the typeface advertises kerning information.

    // Metrics at the reference size, in pixels.
    ascent:        f32     // Distance from the baseline to the highest recommended extent.
    descent:       f32     // Signed distance from the baseline to the lowest recommended extent.
    height:        f32     // Recommended line height.
    underlinePos:  f32     // Underline position relative to the baseline.
    underlineSize: f32     // Recommended underline thickness.

    atlases:  Array'GlyphAtlas                // Atlas pages populated on demand.
    glyphRef: HashTable'(u32, *GlyphDesc)     // Cached descriptors indexed by typeface glyph index.

    // Kerning between two glyph indices, in reference-size pixels (lazily filled).
    // Key = (leftGlyphIndex << 32) | rightGlyphIndex.
    kernRef: HashTable'(u64, f32)     // Lazily populated kerning-pair cache.
    dirty:   bool                     // Whether at least one atlas requires a GPU upload.
}

// Represents a lightweight view of a shared [[Pixel.GlyphCache]] at one draw size.
//
// Glyph quads and metrics scale from the cache reference size when drawn or
// measured.
//
// ## Example
//
// ```swag
// let font = try renderer.fonts.createFont("Inter-Regular.ttf", 18)
// painter.drawString(20, 32, "Hello, Pixel", font, Pixel.Argb.White)
// ```
public struct Font
{
    // A font view is what the cache hands out: everything it carries is a result to read.
    // Ask the cache for another view instead of rewriting this one.
    readonly
    {
        mode:        FontRenderMode     // Creation intent; the underlying cache is always concrete.
        size:        u32                // Requested drawing size in pixels.
        forceBold:   bool               // Whether this view synthesizes bold glyphs.
        forceItalic: bool               // Whether this view synthesizes italic glyphs.

        // Metrics scaled to 'size', in pixels.
        ascent:        f32     // Distance from the baseline to the highest recommended extent.
        descent:       f32     // Signed distance from the baseline to the lowest recommended extent.
        height:        f32     // Recommended line height.
        underlinePos:  f32     // Underline position relative to the baseline.
        underlineSize: f32     // Recommended underline thickness.
    }

    // Links back to the storage this view borrows. The text pipeline resolves glyphs through
    // them; a caller has no use for either.
    internal
    {
        owner: *FontCache  = undefined     // Cache that created this view and owns it.
        cache: *GlyphCache = undefined     // Shared glyph storage borrowed by this font view.
    }
}

// Owns the glyph storage and the font views created through it.
//
// A glyph atlas carries a GPU texture, so it has the lifetime of a graphics context, not of the
// process: [[Pixel.RenderOgl]] owns one cache and every font it hands out lives and dies with it.
// Code that only measures or lays out text can own a bare cache with no renderer at all -- atlases
// then simply never get a texture.
//
// A cache holds a handful of entries (one per typeface, size and style actually drawn), so lookups
// walk them rather than hashing a key. That keeps font creation allocation-free on the draw path,
// which matters because an automatic font resolves a concrete view on every run it draws.
#[Swag.NoCopy]
public struct FontCache
{
    // The storage the cache owns. Views come out of 'create'; nothing else should reach in.
    internal
    {
        glyphCaches: ArrayPtr'GlyphCache     // Glyph storage, one per typeface / reference size / style.
        fonts:       ArrayPtr'Font           // Views handed out by this cache.
    }
}

private func mulFix(a, b: s32)->s32
{
    let ab = cast(s64) a * cast(s64) b
    return cast(s32) ((ab + 0x8000 - (ab < 0 ? 1 : 0)) >> 16)
}

public impl FontCache
{
    // Drops every glyph cache and font view created through this cache.
    //
    // A renderer must release the GPU textures of the atlases before this runs; see
    // [[Pixel.RenderOgl.opDrop]].
    mtd clear()
    {
        .fonts.clear()
        .glyphCaches.clear()
    }

    // Get or create the glyph storage for a (typeface, style, mode, refSize, spread).
    private mtd acquireGlyphCache(typeFace: *TypeFace, refSize, spread: u32, renderMode: FontRenderMode, forceBold, forceItalic: bool)->*GlyphCache
    {
        for it in .glyphCaches
        {
            let cache = notnull it
            if cache.typeFace == typeFace and
               cache.refSize == refSize and
               cache.spread == spread and
               cache.renderMode == renderMode and
               cache.forceBold == forceBold and
               cache.forceItalic == forceItalic do
                return cache
        }

        let cache = .glyphCaches.addNewPtr()
        cache.typeFace    = typeFace
        cache.renderMode  = renderMode
        cache.refSize     = refSize
        cache.spread      = spread
        cache.forceBold   = forceBold
        cache.forceItalic = forceItalic
        cache.hasKerning  = expect typeFace.face.hasKerning()

        expect typeFace.face.setPixelSize(0, refSize)
        let metrics = &typeFace.face.size.metrics
        cache.ascent        = metrics.ascender / 64.0
        cache.descent       = metrics.descender / 64.0
        cache.height        = cache.ascent - cache.descent
        cache.underlinePos  = mulFix(cast(s32) typeFace.face.underlinePosition, metrics.yScale) / 64.0
        cache.underlineSize = mulFix(cast(s32) typeFace.face.underlineThickness, metrics.yScale) / 64.0

        return cache
    }

    // Builds (or returns the already created) font view.
    //
    // 'atlasMode' is the concrete glyph cache mode; 'intent' is the creation mode stored on the
    // font and may be 'Auto'. Both take part in the identity, so an automatic font and an explicit
    // MSDF font of the same size are two distinct views.
    private mtd createView(typeFace: *TypeFace, size, refSize, spread: u32, atlasMode, intent: FontRenderMode, forceBold, forceItalic: bool)->*Font
    {
        Debug.assert(typeFace != null)
        Debug.assert(size > 0)

        for it in .fonts
        {
            let font = notnull it
            if font.cache.typeFace == typeFace and
               font.size == size and
               font.cache.refSize == refSize and
               font.cache.spread == spread and
               font.cache.renderMode == atlasMode and
               font.mode == intent and
               font.forceBold == forceBold and
               font.forceItalic == forceItalic do
                return font
        }

        let cache = .acquireGlyphCache(typeFace, refSize, spread, atlasMode, forceBold, forceItalic)
        let font  = .fonts.addNewPtr()
        font.owner       = me
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

        return font
    }

    // Creates a font from an existing typeface and draw size.
    //
    // `mode` selects the rendering technique. `Auto`, the default, adapts between bitmap and MSDF
    // rendering at draw time. The returned view is owned by this cache; never delete it.
    mtd createFont(typeFace: *TypeFace, size: u32, mode = FontRenderMode.Auto, forceBold, forceItalic = false)->*Font
    {
        switch mode
        {
        case .Bitmap:

            // Classic grayscale bitmap, rasterized at the exact pixel size.
            return .createView(typeFace, size, size, 0, .Bitmap, .Bitmap, forceBold, forceItalic)

        case .Msdf:

            // Multi-channel SDF, size-independent reference atlas.
            return .createView(typeFace, size, RefEmSize, RefEmSpread, .Msdf, .Msdf, forceBold, forceItalic)
        }

        // Auto: an MSDF reference view that substitutes a crisp bitmap at small on-screen sizes
        // (resolved per draw, see resolveDrawFont).
        return .createView(typeFace, size, RefEmSize, RefEmSpread, .Msdf, .Auto, forceBold, forceItalic)
    }

    // Loads a typeface file and creates a font at the requested draw size.
    //
    // Typefaces are shared process-wide: they are immutable parsed files with no graphics resource
    // of their own, so loading the same one through two caches parses it once.
    mtd createFont(fullname: string, size: u32, mode = FontRenderMode.Auto, forceBold, forceItalic = false)->*Font fail
    {
        Debug.assert(@countof(fullname) != 0)
        let typeFace = try TypeFace.load(fullname)
        return .createFont(typeFace, size, mode, forceBold, forceItalic)
    }
}

public impl Font
{
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

    // Returns the horizontal kerning between two glyph indices, in pixels at the drawing size.
    //
    // Returns zero when the typeface carries no kerning for the pair. Pass the indices
    // returned by [[Pixel.Font.glyphIndex]].
    mtd kerning(leftIndex, rightIndex: u32)->f32
    {
        return .cache.kerning(leftIndex, rightIndex)
    }

    // Resolves the concrete font for an on-screen pixel size.
    //
    // Non-automatic fonts return themselves. An automatic font uses the
    // size-independent MSDF view at or above the automatic quality threshold, and
    // a crisp bitmap rasterized at the exact pixel size below it.
    func resolveDrawFont(font: *Font, effectivePx: f32)->*Font
    {
        if font.mode != .Auto do
            return font
        if effectivePx >= AutoMsdfMinPx do
            return font

        var px = cast(s32) Math.round(effectivePx)
        px = Math.clamp(px, 1, cast(s32) AutoMsdfMinPx)
        return font.owner.createView(font.cache.typeFace, font.size, cast(u32) px, 0, .Bitmap, .Bitmap, font.forceBold, font.forceItalic)
    }
}

public impl GlyphCache
{
    // Releases atlas descriptors and cached kerning data owned by this cache.
    mtd opDrop()
    {
        for k, [v] in .glyphRef do
            Memory.delete(v)
        .glyphRef.free()
        .kernRef.free()
    }

    // Returns horizontal kerning in reference-size pixels.
    //
    // Returns 0 when the typeface has no kerning pair for the couple.
    mtd kerning(leftIndex, rightIndex: u32)->f32
    {
        // Most fonts carry no legacy 'kern' table: skip the per-pair hash lookup entirely.
        if !.hasKerning or !leftIndex or !rightIndex do
            return 0

        let key  = (cast(u64) leftIndex << 32) | cast(u64) rightIndex
        let here = .kernRef.tryFind(key)
        if here do
            return here.value

        // 'kern' is scaled to the current pixel size, so query it at the reference size.
        expect .typeFace.face.setPixelSize(0, .refSize)
        let kv = expect .typeFace.face.getKerning(leftIndex, rightIndex)
        let px = kv.x / 64.0
        .kernRef.add(key, px)
        return px
    }

    // Returns the glyph descriptor of a given rune, rendered at the reference size
    mtd getGlyphDesc(c: rune)->const *GlyphDesc
    {
        return .getGlyphDescByIndex(.typeFace.face.glyphIndex(c))
    }

    // Rasterizes a typeface glyph into the face bitmap using this cache's mode.
    //
    // This is a low-level cache operation; [[Pixel.GlyphCache.getGlyphDescByIndex]]
    // normally invokes it automatically when a descriptor is first requested.
    mtd renderGlyphBitmap(glyphIndex: u32) fail
    {
        switch .renderMode
        {
        case .Msdf: discard try .typeFace.renderGlyphMsdfByIndex(glyphIndex, .refSize, .spread, .forceBold, .forceItalic)
        default:    discard try .typeFace.renderGlyphByIndex(glyphIndex, .refSize, .forceBold, .forceItalic)
        }
    }

    // Returns the glyph descriptor of a given glyph index, rendered at the reference size
    mtd getGlyphDescByIndex(glyphIndex: u32)->const *GlyphDesc
    {
        let entry = .glyphRef.tryFind(glyphIndex)
        if entry do
            return cast(const *GlyphDesc) (notnull entry.value)

        // Render the glyph
        let bpp = .renderMode.bytesPerPixel()
        discard catch .renderGlyphBitmap(glyphIndex)
        let bmpRef = &.typeFace.face.glyph.bitmap

        // Glyph width in bytes (atlas columns are measured in bytes, rows in pixels)
        let rowBytes = bmpRef.width * bpp

        // Creates a new atlas if this is the first time, or if the last atlas is full
        var atlas = .atlases.count ? &(notnull .atlases.buffer)[.atlases.count - 1] : null
        if atlas
        {
            let a = notnull atlas
            if a.curX + rowBytes > a.width
            {
                a.curX = 0
                if a.nextY + bmpRef.rows > a.height do
                    atlas = null
                else do
                    a.curY = a.nextY
            }
            elif a.curY + bmpRef.rows > a.height
            {
                atlas = null
            }
        }

        if !atlas
        {
            var newAtlas: GlyphAtlas
            newAtlas.bpp = bpp
            let atlasSide = Math.roundUpToPowerOf2(Math.max(.refSize * 4, Math.max(bmpRef.width, bmpRef.rows) * 2))
            newAtlas.width  = atlasSide * newAtlas.bpp
            newAtlas.height = atlasSide
            newAtlas.datas.resize(cast(u64) newAtlas.width * newAtlas.height)
            let datas = notnull newAtlas.datas.buffer
            Memory.clear(datas, newAtlas.datas.count)
            .atlases.add(newAtlas)
            atlas = &(notnull .atlases.buffer)[.atlases.count - 1]
        }

        let ca = notnull atlas
        let x  = ca.curX
        let y  = ca.curY
        ca.curX  += rowBytes
        ca.nextY = Math.max(ca.nextY, ca.curY + bmpRef.rows)

        // Copy the rendered glyph to the atlas datas
        var buffer = (notnull ca.datas.buffer) + x + (ca.width * (ca.height - 1))
        buffer -= (y * ca.width)
        var src = bmpRef.buffer
        for [j] in bmpRef.rows
        {
            Memory.copy(buffer, src, cast(u64) rowBytes)
            src    += bmpRef.pitch
            buffer -= ca.width
        }

        // Setup GlyphDesc
        let refr = Memory.new'GlyphDesc()
        .glyphRef.add(glyphIndex, refr)

        refr.width  = bmpRef.width
        refr.height = bmpRef.rows

        let glyph = .typeFace.face.glyph
        refr.glyphIndex = glyph.index
        refr.advanceX   = glyph.advance.x / 64.0
        refr.advanceY   = glyph.advance.y / 64.0
        refr.shiftX     = glyph.bitmapLeft
        refr.shiftY     = glyph.bitmapTop

        // 'x' and the atlas width are measured in bytes; both numerator and
        // denominator carry the bpp factor, so the resulting uv stays correct.
        let widthf  = cast(f32) ca.width
        let heightf = cast(f32) ca.height
        refr.uv.x      = x / widthf
        refr.uv.y      = y / heightf
        refr.uv.width  = cast(f32) rowBytes / widthf
        refr.uv.height = refr.height / heightf

        refr.atlasIndex = cast(u32) (.atlases.count - 1)

        .dirty   = true
        ca.dirty = true

        return refr
    }
}
