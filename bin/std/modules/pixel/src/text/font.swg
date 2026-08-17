using Core, TrueType

// Pixel storage for one page of cached glyph bitmaps.
//
// Applications normally obtain atlas data through a [[Pixel.GlyphCache]]. Atlas
// dimensions are expressed in pixels, while `width` and `curX` count bytes for
// multi-channel distance-field textures.
#[Swag.Opaque]
public struct GlyphAtlas
{
    internal
    {
        texture:       Texture      // GPU texture associated with this atlas page.
        width:         u32          // Row width in bytes.
        height:        u32          // Page height in pixels.
        bytesPerPixel: u32          // Bytes used by one atlas pixel.
        data:          Array'u8     // CPU-side pixel storage.
        dirty:         bool         // Whether `data` contains changes not uploaded to `texture`.
        curX:          s32          // Byte offset of the next glyph in the current row.
        curY:          s32          // Pixel offset of the current row.
        nextY:         s32          // Pixel offset available for the following row.
    }
}

// Cached placement and metrics for one rendered glyph.
//
// Metric values are measured at the cache reference size. Multiply them by
// [[Pixel.Font.scale]] to obtain values for a particular font view.
public struct GlyphDesc
{
    public
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
//
// The threshold sits well above the size where the two techniques become hard to tell apart
// because they are not equally cheap. The MSDF atlas is size independent, so vertical
// hinting and stem darkening cannot apply to it, and text stays visibly softer and lighter
// than a bitmap until roughly thirty pixels; above that the two are indistinguishable. A
// first MSDF glyph also costs an order of magnitude more to produce than a bitmap glyph at
// the exact device size, and a page of text meeting a cold atlas pays that on the frame that
// draws it. So everything the eye cannot separate is rasterized, and MSDF is kept for text
// large enough to be scaled or zoomed. Thirty-two device pixels covers ordinary interface
// text at every common display scale: a sixteen-pixel body size only reaches it at 200%.
const AutoMsdfMinPx: f32 = 32.0

// Stores glyphs shared by compatible [[Pixel.Font]] views.
//
// Fonts with the same typeface, style, render mode, reference size, and spread share
// this cache. A typeface therefore needs only one MSDF atlas across draw sizes.
#[Swag.Opaque]
public struct GlyphCache
{
    internal
    {
        typeFace:    *TypeFace = undefined     // Typeface borrowed for rasterization and metrics.
        renderMode:  FontRenderMode            // Concrete atlas representation; never `Auto`.
        refSize:     u32                       // Reference em size in pixels.
        spread:      u32                       // Distance-field range in pixels, or zero for bitmap atlases.
        forceBold:   bool                      // Whether glyph rasterization synthesizes bold weight.
        forceItalic: bool                      // Whether glyph rasterization synthesizes italic slant.
        hasKerning:  bool                      // Whether the typeface advertises kerning information.

        ascent:        f32     // Distance from the baseline to the highest recommended extent.
        descent:       f32     // Signed distance from the baseline to the lowest recommended extent.
        height:        f32     // Recommended line height.
        capHeight:     f32     // Distance from the baseline to the top of an uppercase letter.
        underlinePos:  f32     // Underline position relative to the baseline.
        underlineSize: f32     // Recommended underline thickness.

        atlases:  Array'GlyphAtlas                // Atlas pages populated on demand.
        glyphRef: HashTable'(u32, *GlyphDesc)     // Cached descriptors indexed by typeface glyph index.
        kernRef:  HashTable'(u64, f32)            // Kerning cache keyed by two glyph indices.
        dirty:    bool                            // Whether at least one atlas requires a GPU upload.
    }
}

// Represents a lightweight view of a shared [[Pixel.GlyphCache]] at one draw size.
//
// Glyph quads and metrics scale from the cache reference size when drawn or
// measured.
//
// ## Example
//
// ```swag
// let font = try renderer.fontCache().createFont("Inter-Regular.ttf", 18)
// painter.drawString(20, 32, "Hello, Pixel", font, Pixel.Argb.White)
// ```
public struct Font
{
    // A font view is what the cache hands out: everything it carries is a result to read.
    // Ask the cache for another view instead of rewriting this one.
    public readonly
    {
        mode:        FontRenderMode     // Creation intent; the underlying cache is always concrete.
        size:        u32                // Requested drawing size in pixels.
        forceBold:   bool               // Whether this view synthesizes bold glyphs.
        forceItalic: bool               // Whether this view synthesizes italic glyphs.

        // Metrics scaled to 'size', in pixels.
        ascent:        f32     // Distance from the baseline to the highest recommended extent.
        descent:       f32     // Signed distance from the baseline to the lowest recommended extent.
        height:        f32     // Recommended line height.
        capHeight:     f32     // Distance from the baseline to the top of an uppercase letter.
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
// Each renderer owns one cache and every font it hands out lives and dies with it. An OpenGL
// renderer also uploads atlas pixels to context-owned textures; [[Pixel.RenderCpu]] samples the
// atlas bytes directly. Code that only measures or lays out text can own a bare cache with no
// renderer at all.
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
    // An OpenGL renderer must release the GPU textures of the atlases before this runs; see
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
            let cache = it!
            if cache.typeFace == typeFace and
               cache.refSize == refSize and
               cache.spread == spread and
               cache.renderMode == renderMode and
               cache.forceBold == forceBold and
               cache.forceItalic == forceItalic do
                return cache
        }

        let cache = .glyphCaches.addNew()
        cache.typeFace    = typeFace
        cache.renderMode  = renderMode
        cache.refSize     = refSize
        cache.spread      = spread
        cache.forceBold   = forceBold
        cache.forceItalic = forceItalic
        cache.hasKerning  = typeFace.face.hasKerning()

        expect typeFace.face.setPixelSize(0, refSize)
        let metrics = &typeFace.face.size.metrics
        cache.ascent        = metrics.ascender / 64.0
        cache.descent       = metrics.descender / 64.0
        cache.height        = cache.ascent - cache.descent
        cache.underlinePos  = mulFix(cast(s32) typeFace.face.underlinePosition, metrics.yScale) / 64.0
        cache.underlineSize = mulFix(cast(s32) typeFace.face.underlineThickness, metrics.yScale) / 64.0

        // A face older than OS/2 version 2 declares no cap height. Reading a capital out of
        // the outlines would settle it exactly, but a face that old is a fallback anyway, so
        // take the proportion the common interface faces share rather than pay for a glyph
        // load on every cache miss.
        cache.capHeight = metrics.capHeight / 64.0
        if cache.capHeight <= 0 do
            cache.capHeight = cache.ascent * 0.72

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
            let font = it!
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
        let font  = .fonts.addNew()
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
        font.capHeight     = cache.capHeight * s
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

    // Distance from the middle of a line box to the middle of the text a reader sees in it.
    //
    // A line box reaches from the ascender to the descender, but a word is read on its capitals,
    // and the two middles are not the same point: the ascender keeps room above the capitals for
    // accents the word may not carry, and the descender keeps room below the baseline for tails it
    // may not carry either. The sign therefore belongs to the face, not to the rule — a text face
    // with generous accent room reads low in its line box, a compact one reads high. Add it to the
    // center of a rectangle a single line box is centered in to place anything that has to look
    // level with that line, such as a leading icon or a check mark.
    mtd const opticalOffset()->f32
    {
        return (.ascent + .descent - .capHeight) * 0.5
    }

    // Y of the top edge of `size` placed level with a line of this font centered on `centerY`.
    mtd const opticalTop(centerY, size: f32)->f32
    {
        return centerY + .opticalOffset() - size * 0.5
    }

    // Y of the top of a line box of this font whose capitals are centered on `centerY`.
    //
    // This is how a single line is centered in something a reader sees the edges of — a field, a
    // cell, a button. Centering the line *box* instead hands the placement to the internal leading
    // of the face: two fields of one form, one set in the interface face and one in the fixed-width
    // one, then put their words on centers a couple of pixels apart, and neither on the center of
    // the frame around it. What the eye compares is the ink, so it is the ink that is centered.
    mtd const opticalLineTop(centerY: f32)->f32
    {
        return centerY - .height * 0.5 - .opticalOffset()
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

    // Returns the glyph index a PostScript glyph name selects, or zero when the typeface
    // names no glyph so.
    //
    // A CFF or Type 1 program keys its outlines by name, which is how a document format
    // addresses them; a TrueType face names none and always answers zero.
    mtd glyphIndexByName(name: string)->u32
    {
        return .cache.typeFace.face.glyphIndexByName(name)
    }

    // Returns the glyph index the typeface's own built-in encoding places at one code.
    //
    // This is the encoding the font program declares, not a Unicode map. Zero is returned
    // for a typeface that declares none, and for an unused code.
    mtd glyphIndexByCode(code: u32)->u32
    {
        return .cache.typeFace.face.glyphIndexByCode(code)
    }

    // Returns the glyph index a character identifier selects in a CID-keyed typeface.
    //
    // Zero is returned for any typeface that is not CID-keyed.
    mtd glyphIndexByCid(cid: u32)->u32
    {
        return .cache.typeFace.face.glyphIndexByCid(cid)
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
    // `effectivePx` is the glyph size in physical device pixels, including zoom and
    // display scale. An MSDF font returns itself: it is size independent. A bitmap
    // font re-rasterizes at the effective size when it differs from its own, so the
    // atlas always matches the device pixels it lands on. An automatic font uses the
    // size-independent MSDF view at or above the automatic quality threshold, and a
    // crisp bitmap rasterized at the exact device pixel size below it.
    func resolveDrawFont(font: *Font, effectivePx: f32)->*Font
    {
        if font.mode == .Bitmap
        {
            let px = cast(s32) Math.max(Math.round(effectivePx), 1.0)
            if px == font.cache.refSize do
                return font
            return font.owner.createView(font.cache.typeFace, font.size, cast(u32) px, 0, .Bitmap, .Bitmap, font.forceBold, font.forceItalic)
        }

        if font.mode != .Auto do
            return font
        if effectivePx >= AutoMsdfMinPx do
            return font

        var px = cast(s32) Math.round(effectivePx)
        px = Math.clamp(px, 1, cast(s32) AutoMsdfMinPx)
        return font.owner.createView(font.cache.typeFace, font.size, cast(u32) px, 0, .Bitmap, .Bitmap, font.forceBold, font.forceItalic)
    }
}

impl GlyphCache
{
    // Releases atlas descriptors and cached kerning data owned by this cache.
    mtd opDrop()
    {
        for k, v in .glyphRef do
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
        let kv = .typeFace.face.getKerning(leftIndex, rightIndex)
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
            return cast(const *GlyphDesc) entry.value!

        // Render the glyph
        let bpp = .renderMode.bytesPerPixel()
        discard catch .renderGlyphBitmap(glyphIndex)
        let bmpRef = &.typeFace.face.glyph.bitmap

        // Glyph width in bytes (atlas columns are measured in bytes, rows in pixels)
        let rowBytes = bmpRef.width * bpp

        // Creates a new atlas if this is the first time, or if the last atlas is full
        var atlas = .atlases.count ? &.atlases.buffer![.atlases.count - 1] : null
        if atlas
        {
            let a = atlas!
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
            newAtlas.bytesPerPixel = bpp
            let atlasSide = Math.roundUpToPowerOf2(Math.max(.refSize * 4, Math.max(bmpRef.width, bmpRef.rows) * 2))
            newAtlas.width  = atlasSide * newAtlas.bytesPerPixel
            newAtlas.height = atlasSide
            newAtlas.data.resize(cast(u64) newAtlas.width * newAtlas.height)
            let data = newAtlas.data.buffer!
            Memory.clear(data, newAtlas.data.count)
            .atlases.add(newAtlas)
            atlas = &.atlases.buffer![.atlases.count - 1]
        }

        let ca = atlas!
        let x  = ca.curX
        let y  = ca.curY
        ca.curX  += rowBytes
        ca.nextY = Math.max(ca.nextY, ca.curY + bmpRef.rows)

        // Copy the rendered glyph to the atlas datas
        var buffer = ca.data.buffer! + x + (ca.width * (ca.height - 1))
        buffer -= (y * ca.width)
        var src = bmpRef.buffer
        for j in bmpRef.rows
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
