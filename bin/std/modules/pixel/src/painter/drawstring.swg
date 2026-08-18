#global public

using Core

// Selects horizontal placement of text inside its layout rectangle.
enum StringHorzAlignment
{
    Center      // Center each line horizontally.
    Left        // Align each line to the left edge.
    Right       // Align each line to the right edge.
    Justify     // Expand eligible spaces to reach both edges.
}

// Selects vertical placement of text inside its layout rectangle.
enum StringVertAlignment
{
    Center            // Center the text block vertically.
    Top               // Align the text block to the top edge.
    Bottom            // Align the text block to the bottom edge.
    OpticalCenter     // Center one line on its capitals; see [[Pixel.Font.opticalLineTop]].
}

// Selects an optional decoration drawn along a text run.
enum UnderlineStyle
{
    None          // Draw no decoration.
    Underline     // Draw a line below the baseline.
    Strikeout     // Draw a line through the glyphs.
}

// Configures face, outline, glow, shadow, and bevel effects for MSDF text.
//
// The face effects are derived from the glyph distance field and share one draw.
// The soft drop shadow uses an offset second pass. Effects apply only when the
// resolved draw font uses MSDF; bitmap rendering ignores them. Distances are in
// distance-field units, where `0.5` spans approximately the atlas spread, so widths
// scale with the text size.
struct TextEffect
{
    public
    {
        // Outline drawn under the glyph face. 0 disables it; useful range ~0.05..0.35.
        outlineWidth: f32
        outlineColor: Color = Color.fromArgb(Argb.Black)     // Straight-alpha outline color.

        // Grows (+) or shrinks (-) the glyph face; ~ -0.3..0.3.
        faceDilate: f32

        // Edge softness in distance-field units; 0 = crisp, > 0 = feathered.
        softness: f32

        // Soft halo around the glyph. A fully transparent color disables it.
        glowColor:  Color
        glowOffset: f32            // shifts the glow band outward
        glowInner:  f32 = 0.0      // Inner edge of the glow band.
        glowOuter:  f32 = 0.45     // Outer edge of the glow band.
        glowPower:  f32 = 1.0      // Glow falloff exponent.

        // Distance-field emboss amount, lit from the upper-left; 0 disables it (~0..1).
        bevel: f32

        // Soft drop shadow (offset second pass). A transparent color disables it.
        shadowColor:    Color
        shadowOffset:   Math.Point     // Shadow displacement in path-space pixels.
        shadowDilate:   f32 = 0.0      // Signed expansion of the shadow silhouette.
        shadowSoftness: f32 = 0.35     // Width of the softened shadow edge.
    }
}

impl TextEffect
{
    // True if #null any single-pass face effect (outline/glow/bevel/dilate/softness) is on.
    mtd const hasFaceEffects()->bool
    {
        return .outlineWidth > 0 or .glowColor.a > 0 or .bevel > 0 or .faceDilate != 0 or .softness != 0
    }

    // True if a drop shadow must be rendered.
    mtd const hasShadow()->bool
    {
        return .shadowColor.a > 0
    }

    // Resolve the shader uniforms for the main glyph face.
    mtd const faceParams()->FontEffectParams
    {
        var r: retval
        r.enabled      = .hasFaceEffects() ? 1.0 : 0.0
        r.faceDilate   = .faceDilate
        r.faceSoftness = .softness
        r.outlineWidth = .outlineWidth
        r.outlineColor = .outlineColor
        r.glowColor    = .glowColor
        r.glowOffset   = .glowOffset
        r.glowInner    = .glowInner
        r.glowOuter    = .glowOuter
        r.glowPower    = .glowPower
        r.bevel        = .bevel
        return r
    }

    // Resolves shader parameters for the drop-shadow pass.
    //
    // The pass draws a softened, dilated face in the shadow color without outline,
    // glow, or bevel effects.
    mtd const shadowParams()->FontEffectParams
    {
        var r: retval
        r.enabled      = 1.0
        r.faceDilate   = .shadowDilate
        r.faceSoftness = .shadowSoftness
        r.glowOuter    = 1.0
        r.glowPower    = 1.0
        return r
    }
}

const DefaultTextTabSize: u32 = 4     // Default tab-stop width measured in space advances.

// Mark ending a line cut by [[Pixel.StringFormatFlags.Ellipsis]]. A typeface carrying no glyph
// for it falls back to three periods, which every text face has.
private const EllipsisRune = '\u2026'rune

// Controls wrapping and clipping during text layout.
#[Swag.EnumFlags]
enum StringFormatFlags
{
    Default      // Use single-line, unclipped layout defaults.
    WordWrap     // Wrap at word boundaries within the layout width.
    Clip         // Clip drawing to the layout rectangle.
    Ellipsis     // Cut a line that overflows the layout width and end it with an ellipsis. Ignored by justified text.
}

// Reports the logical dimensions of laid-out text.
struct StringMetrics
{
    public
    {
        ascent:  f32     // Maximum extent above the baseline, in pixels.
        descent: f32     // Maximum extent below the baseline, in pixels.
        width:   f32     // Logical advance width, in pixels.
        height:  f32     // Sum of ascent and descent, in pixels.
    }
}

// Stores one positioned glyph in a shaped text run.
struct ShapedGlyph
{
    public
    {
        desc:       const *GlyphDesc = undefined     // Borrowed glyph metrics and atlas descriptor.
        glyphIndex: u32                              // Typeface-specific glyph index.
        cluster:    u64                              // Byte offset of the originating UTF-8 cluster.
        advanceX:   f32                              // Horizontal advance in reference-font units.
        advanceY:   f32                              // Vertical advance in reference-font units.
        offsetX:    f32                              // Horizontal placement adjustment.
        offsetY:    f32                              // Vertical placement adjustment.
        isTab:      bool                             // Whether this glyph represents an expanded tab.
    }
}

// Owns shaped glyphs and aggregate measurements for a single font run.
struct ShapedRun
{
    public
    {
        font:          *Font = undefined              // Borrowed font used for shaping.
        glyphs:        Array'ShapedGlyph              // Glyphs in logical text order.
        metrics:       StringMetrics                  // Logical run measurements.
        inkBounds:     Math.Rectangle                 // Bounds of visible glyph pixels.
        hasInk:        bool                           // Whether `inkBounds` contains visible glyphs.
        tabSize:       u32   = DefaultTextTabSize     // Tab-stop width in space advances.
        letterSpacing: f32                            // Additional spacing between glyphs, in pixels.
    }
}

// Contains resolved font and scaling choices for one text draw.
struct TextDrawInfo
{
    public
    {
        drawFont:    *Font = undefined     // Borrowed bitmap or MSDF font selected for drawing.
        snapPixels:  bool                  // Whether glyph positions snap to the device-pixel grid.
        scale:       f32                   // Scale from reference glyph metrics to logical draw units.
        deviceScale: f32   = 1             // Physical device pixels per logical draw unit.

        // Translation of the transform the text is drawn under, when it is translation
        // only. Snapping accounts for it so glyph edges land on the *device* grid after
        // the renderer applies the transform; without it a fractional translation puts
        // every "snapped" quad half a pixel off the grid. Zero for pure measurement.
        snapOffsetX: f32     // Path-to-surface X translation compensated by snapping.
        snapOffsetY: f32     // Path-to-surface Y translation compensated by snapping.
    }
}

// Configures rich-text layout and drawing.
struct RichStringFormat
{
    public
    {
        font:          FontFamily                                           // Fonts used for regular, bold, italic, and bold-italic runs.
        fontStyle:     FontFamilyStyle     = Regular                        // Initial font style.
        palette:       [4] Color                                            // Colors selected by `<p?>` rich-text markers.
        colorUrl:      Color               = Color.fromArgb(Argb.White)     // Normal `<url>` text color.
        colorHotUrl:   Color               = Color.fromArgb(Argb.Blue)      // Hovered `<url>` text color.
        brush:         Brush                                                // Default text paint source.
        horzAlignment: StringHorzAlignment = Left                           // Horizontal line alignment.
        vertAlignment: StringVertAlignment = Top                            // Vertical block alignment.
        lineGap:       s32                                                  // Extra gap between baselines, in pixels.
        flags:         StringFormatFlags   = Default                        // Wrapping and clipping behaviors.
        justifyLimit:  f32                 = 2                              // Maximum expansion factor for justified spaces.
        tabSize:       u32                 = DefaultTextTabSize             // Tab width in space advances.
        letterSpacing: f32                                                  // Extra glyph spacing, in pixels.
        minLineHeight: f32                                                  // Minimum line height, in pixels; `0` uses font metrics.
        paragraphGap:  s32                                                  // Extra gap after paragraphs, in pixels.
        maxLines:      u32                                                  // Maximum laid-out line count; `0` is unlimited.
    }
}

private func appendShapedGlyph(run: *ShapedRun, font: *Font, glyphIndex: u32, cluster: u64, previousGlyphIndex: u32, customAdvanceX = 0.0'f32, isTab = false, letterSpacing = 0.0'f32)
{
    var glyph: ShapedGlyph
    glyph.desc       = font.getGlyphDescByIndex(glyphIndex)
    glyph.glyphIndex = glyphIndex
    glyph.cluster    = cluster
    let desc = glyph.desc
    glyph.advanceX = isTab ? customAdvanceX : desc.advanceX
    glyph.advanceY = desc.advanceY
    glyph.isTab    = isTab
    if previousGlyphIndex and !isTab do
        glyph.offsetX = font.cache.kerning(previousGlyphIndex, glyphIndex) + letterSpacing

    let glyphX = run.metrics.width + glyph.offsetX
    if desc.width != 0 and desc.height != 0
    {
        let bounds = Math.Rectangle{glyphX + desc.shiftX, glyph.offsetY - desc.shiftY, desc.width, desc.height}
        if run.hasInk do
            run.inkBounds.combine(bounds)
        else
        {
            run.inkBounds = bounds
            run.hasInk    = true
        }
    }

    if run.glyphs.isEmpty()
    {
        run.metrics.ascent  = desc.shiftY
        run.metrics.descent = desc.height - desc.shiftY
    }
    else
    {
        run.metrics.ascent  = Math.max(run.metrics.ascent, desc.shiftY)
        run.metrics.descent = Math.max(run.metrics.descent, desc.height - desc.shiftY)
    }

    run.metrics.width += glyph.offsetX + glyph.advanceX
    run.glyphs.add(glyph)
}

private func appendShapedTab(run: *ShapedRun, font: *Font, cluster: u64, tabSize: u32)
{
    let spaceGlyphIndex  = font.glyphIndex(' ')
    let spaceDesc        = font.getGlyphDescByIndex(spaceGlyphIndex)
    var effectiveTabSize = tabSize
    if !effectiveTabSize do
        effectiveTabSize = 1

    var spaceAdvance = spaceDesc.advanceX
    if spaceAdvance <= 0 do
        spaceAdvance = cast(f32) font.cache.refSize * 0.25

    let tabWidth   = spaceAdvance * cast(f32) effectiveTabSize
    let nextStop   = (Math.floor(run.metrics.width / tabWidth) + 1) * tabWidth
    let tabAdvance = nextStop - run.metrics.width
    appendShapedGlyph(run, font, spaceGlyphIndex, cluster, 0, tabAdvance, true)
}

private func finishShapedRun(run: *ShapedRun, font: *Font)
{
    if run.glyphs.isEmpty() do
        return

    let sc = font.scale()
    run.metrics.ascent  *= sc
    run.metrics.descent *= sc
    run.metrics.width   *= sc
    run.metrics.height  = run.metrics.ascent + run.metrics.descent
    if run.hasInk
    {
        run.inkBounds.x      *= sc
        run.inkBounds.y      *= sc
        run.inkBounds.width  *= sc
        run.inkBounds.height *= sc
    }
}

private func snapTextPosition(value: f32, snapPixels: bool, deviceScale: f32, snapOffset = 0.0'f32)->f32
{
    if !snapPixels do
        return value

    // Snapping happens on the *device* grid: at a content scale of 1.5 a value
    // rounded to a whole logical unit would land between physical pixels, which is
    // exactly the blur snapping exists to prevent. The transform translation is
    // folded in and out so the snapped position is on the grid after the renderer
    // applies the transform, not merely in path space.
    return Math.round((value + snapOffset) * deviceScale) / deviceScale - snapOffset
}

impl Painter
{
    // Resolves the bitmap or MSDF font, pixel snapping, and scale for a draw.
    //
    // `zoom` and `transformScale` are multiplicative and must be positive for
    // meaningful output. `transformScale` is the number of physical device pixels
    // one drawing unit covers on screen; pass the surface's device scale (or
    // [[Pixel.Painter.textTransformScale]] when drawing through a painter) so an
    // automatic font resolves against the real on-screen glyph size.
    func computeTextDrawInfo(font: *Font, zoom = 1.0'f32, transformScale = 1.0'f32)->TextDrawInfo
    {
        var result: retval
        result.drawFont    = Font.resolveDrawFont(font, cast(f32) font.size * zoom * transformScale)
        result.snapPixels  = !result.drawFont.cache.renderMode.isDistanceField()
        result.deviceScale = transformScale

        // A resolved bitmap font is rasterized at its device pixel size, so it draws
        // texel-exact: one atlas texel per device pixel, hence 1/transformScale in
        // logical units. MSDF glyphs are size independent and keep the nominal scale.
        if result.snapPixels do
            result.scale = 1.0 / transformScale
        else do
            result.scale = result.drawFont.scale() * zoom
        return result
    }

    // Scale applied to text by the current transform (max of the two axis scales),
    // in physical device pixels per drawing unit.
    mtd const textTransformScale()->f32
    {
        let tr = .curState.transform
        return Math.max(Math.sqrt(tr.m11 * tr.m11 + tr.m12 * tr.m12), Math.sqrt(tr.m21 * tr.m21 + tr.m22 * tr.m22)) * .curContentScale
    }

    // Resolves one glyph's left and right positions from scaled metrics.
    //
    // Bitmap runs snap offsets and advances to whole device pixels. When `runStart`
    // is true, the initial position is snapped as well, compensating the transform
    // translation carried by `info`. Offsets and advances are relative widths and
    // snap without it.
    func advanceTextX(left, offsetX, advanceX: f32, info: TextDrawInfo, runStart = false)->{ glyphX: f32, rightX: f32 }
    {
        var result: retval
        result.glyphX = runStart ? snapTextPosition(left, info.snapPixels, info.deviceScale, info.snapOffsetX) : left

        let snappedOffset = snapTextPosition(offsetX * info.scale, info.snapPixels, info.deviceScale)
        result.glyphX += snappedOffset

        let snappedAdvance = snapTextPosition(advanceX * info.scale, info.snapPixels, info.deviceScale)
        result.rightX = result.glyphX + snappedAdvance
        return result
    }

    // Shapes text into a reusable caller-provided run.
    //
    // The glyph buffer is cleared while retaining its capacity, so per-frame shaping
    // can avoid allocation. The current implementation preserves one rune per glyph
    // and records glyph indices, advances, and cluster positions.
    func shapeRunInto(result: *ShapedRun, text: string, font: *Font, tabSize: u32 = DefaultTextTabSize, letterSpacing = 0.0'f32)
    {
        Debug.assert(font != null, "invalid font")

        result.font          = font
        result.tabSize       = tabSize
        result.letterSpacing = letterSpacing
        result.hasInk        = false
        result.metrics.ascent, result.metrics.descent, result.metrics.width, result.metrics.height = 0
        result.glyphs.clear()
        result.glyphs.reserve(@countof(text))

        var count              = @countof(text)
        var scan               = @dataof(text)
        var byteIdx            = 0'u64
        var previousGlyphIndex = 0'u32
        let letterSpacingRef   = letterSpacing / font.scale()

        while count
        {
            let sl       = @mkslice(scan, count)
            let {c, eat} = Utf8.decodeRune(sl)
            if eat == 0 do
                break

            if c == '\t'
            {
                appendShapedTab(result, font, byteIdx, tabSize)
                previousGlyphIndex = 0
            }
            else
            {
                let glyphIndex = font.glyphIndex(c)
                appendShapedGlyph(result, font, glyphIndex, byteIdx, previousGlyphIndex, 0.0, false, letterSpacingRef)
                previousGlyphIndex = glyphIndex
            }

            byteIdx += eat
            scan    += eat
            count   -= eat
        }

        finishShapedRun(result, font)
    }

    // Shape a single-font text run, returning a freshly allocated run.
    func shapeRun(text: string, font: *Font, tabSize: u32 = DefaultTextTabSize, letterSpacing = 0.0'f32)->ShapedRun
    {
        var result: retval
        shapeRunInto(&result, text, font, tabSize, letterSpacing)
        return result
    }

    // Rebuild a shaped run for another concrete font cache while preserving its
    // glyph sequence and cluster mapping.
    func shapeRunForFont(run: const *ShapedRun, font: *Font)->ShapedRun
    {
        Debug.assert(font != null, "invalid font")
        Debug.assert(!run.font or run.font.cache.typeFace == font.cache.typeFace, "cannot reuse glyph indexes with another typeface")

        var result: retval
        result.font          = font
        result.tabSize       = run.tabSize
        result.letterSpacing = run.letterSpacing
        result.glyphs.reserve(run.glyphs.count)

        var previousGlyphIndex = 0'u32
        let letterSpacingRef   = run.letterSpacing / font.scale()
        for glyph in run.glyphs
        {
            if glyph.isTab
            {
                appendShapedTab(&result, font, glyph.cluster, run.tabSize)
                previousGlyphIndex = 0
            }
            else
            {
                appendShapedGlyph(&result, font, glyph.glyphIndex, glyph.cluster, previousGlyphIndex, 0.0, false, letterSpacingRef)
                previousGlyphIndex = glyph.glyphIndex
            }
        }

        finishShapedRun(&result, font)
        return result
    }

    // Resolves the glyph descriptors for a UTF-8 string and font.
    func glyphs(text: string, font: *Font)->Array'(const *GlyphDesc)
    {
        var result: retval
        result.reserve(@countof(text))
        Utf8.visitRunes(text)
        {
            result.add(font.getGlyphDesc(c))
        }

        return result
    }

    // Resolves the glyph descriptors for a rune array and font.
    func glyphs(text: Array'rune, font: *Font)->Array'(const *GlyphDesc)
    {
        var result: retval
        result.reserve(@countof(text))
        for c in text
        {
            result.add(font.getGlyphDesc(c))
        }

        return result
    }

    // Get a rune size for a given font
    func measureRune(c: rune, font: #null *Font)->Math.Point
    {
        var result: retval
        if !font do
            return result
        let localFont = font
        let desc      = localFont.getGlyphDesc(c)
        let sc        = localFont.scale()
        result.x = desc.advanceX * sc
        result.y = (desc.shiftY + desc.height) * sc
        return result
    }

    // Returns the metrics of a given text
    func measureString(text: string, font: *Font, tabSize: u32 = DefaultTextTabSize, letterSpacing = 0.0'f32)->StringMetrics
    {
        let shaped = shapeRun(text, font, tabSize, letterSpacing)
        return shaped.metrics
    }

    // Returns the metrics of an already shaped text run
    func measureString(text: *ShapedRun)->StringMetrics => text.metrics

    // Measures the rendered horizontal advance up to byte `atByte`.
    //
    // The result uses the same pixel snapping and draw-font resolution as
    // [[Pixel.Painter.drawString]]. Unlike [[Pixel.Painter.measureString]], it
    // matches on-screen glyph positions for carets, selections, and right-aligned
    // anchors. The default `atByte` measures the whole run. `deviceScale` must match
    // the device scale the text is drawn with (see `Gui.Wnd.deviceScale`);
    // measuring with another scale snaps advances to a different pixel grid and the
    // measured position drifts from the drawn one.
    func measureStringSnapped(run: const *ShapedRun, atByte: u64 = Swag.U64.Max, deviceScale = 1.0'f32)->f32
    {
        let info = computeTextDrawInfo(run.font, 1.0, deviceScale)

        // drawString re-shapes onto the resolved draw font; mirror that so the
        // advances use the same glyph metrics it will actually draw with.
        var drawShape: ShapedRun
        var toDraw:    const *ShapedRun = run
        if run.font != info.drawFont
        {
            drawShape = shapeRunForFont(run, info.drawFont)
            toDraw    = &drawShape
        }

        var x = 0.0'f32
        for glyph, idx in toDraw.glyphs
        {
            if glyph.cluster >= atByte do
                break
            let step = advanceTextX(x, glyph.offsetX, glyph.advanceX, info, idx == 0)
            x = step.rightX
        }

        return x
    }

    // string convenience overload of `measureStringSnapped`.
    func measureStringSnapped(text: string, font: *Font, atByte: u64 = Swag.U64.Max, tabSize: u32 = DefaultTextTabSize, letterSpacing = 0.0'f32, deviceScale = 1.0'f32)->f32
    {
        let shaped = shapeRun(text, font, tabSize, letterSpacing)
        return measureStringSnapped(&shaped, atByte, deviceScale)
    }

    // Returns the byte length of the longest prefix of `run` that fits `maxWidth`, or
    // `Swag.U64.Max` when the whole run fits.
    //
    // The walk mirrors [[Pixel.Painter.measureStringSnapped]]: the prefix is measured with the
    // resolved draw font and device-snapped advances, so the cut point agrees with the width
    // the run is drawn at rather than with its nominal advances.
    private func fitShapedPrefix(run: const *ShapedRun, maxWidth: f32, deviceScale: f32)->u64
    {
        let info = computeTextDrawInfo(run.font, 1.0, deviceScale)

        var drawShape: ShapedRun
        var toWalk:    const *ShapedRun = run
        if run.font != info.drawFont
        {
            drawShape = shapeRunForFont(run, info.drawFont)
            toWalk    = &drawShape
        }

        var x = 0.0'f32
        for glyph, idx in toWalk.glyphs
        {
            let step = advanceTextX(x, glyph.offsetX, glyph.advanceX, info, idx == 0)
            if step.rightX > maxWidth do
                return glyph.cluster
            x = step.rightX
        }

        return Swag.U64.Max
    }

    // Returns the bounding rectangle of a given text, scaled to the font draw size
    func measureString(text: Array'(const *GlyphDesc), font: *Font)->StringMetrics
    {
        var result: retval
        result.ascent  = Swag.F32.NegInf
        result.descent = Swag.F32.NegInf
        for refr, i in text
        {
            result.ascent  = Math.max(result.ascent, refr.shiftY)
            result.descent = Math.max(result.descent, refr.height - refr.shiftY)
            if i do
                result.width += font.cache.kerning(text[i - 1].glyphIndex, refr.glyphIndex)
            result.width += refr.advanceX
        }

        let sc = font.scale()
        result.ascent  *= sc
        result.descent *= sc
        result.width   *= sc
        result.height  = result.ascent + result.descent
        return result
    }

    // Emit the glyph quads of a shaped run, translated by (dx, dy) and tinted with
    // 'color'. The offset is applied after pixel snapping so a sub-pixel shadow
    // offset survives. Shared by the face pass and the drop-shadow pass.
    private mtd pushShapedGlyphs(runToDraw: *ShapedRun, drawFont: *Font, info: TextDrawInfo, startLeft, baselineY, dx, dy: f32, snapPixels: bool, color: Color)
    {
        var x = startLeft
        for glyph, idx in runToDraw.glyphs
        {
            let step   = Painter.advanceTextX(x, glyph.offsetX, glyph.advanceX, info, idx == 0)
            let glyphX = step.glyphX

            let refr = glyph.desc
            if refr.width != 0 and refr.height != 0
            {
                .setTextureFont(drawFont, refr.atlasIndex)

                let x1 = snapTextPosition(glyphX + refr.shiftX * info.scale, snapPixels, info.deviceScale, info.snapOffsetX) + dx
                let y1 = snapTextPosition(baselineY + glyph.offsetY * info.scale - refr.shiftY * info.scale, snapPixels, info.deviceScale, info.snapOffsetY) + dy
                let x2 = snapTextPosition(glyphX + (refr.shiftX * info.scale) + (refr.width * info.scale), snapPixels, info.deviceScale, info.snapOffsetX) + dx
                let y2 = snapTextPosition(baselineY + glyph.offsetY * info.scale - (refr.shiftY * info.scale) + (refr.height * info.scale), snapPixels, info.deviceScale, info.snapOffsetY) + dy

                let p1 = Math.Vector2{x1, y1}
                let p2 = Math.Vector2{x2, y1}
                let p3 = Math.Vector2{x1, y2}
                let p4 = Math.Vector2{x2, y2}

                let uv1 = Math.Vector2{refr.uv.x, refr.uv.y}
                let uv2 = Math.Vector2{refr.uv.x + refr.uv.width, refr.uv.y}
                let uv3 = Math.Vector2{refr.uv.x, refr.uv.y + refr.uv.height}
                let uv4 = Math.Vector2{refr.uv.x + refr.uv.width, refr.uv.y + refr.uv.height}

                discard .pushTriangle(p1, p2, p3, uv1, uv2, uv3, color)
                discard .pushTriangle(p3, p2, p4, uv3, uv2, uv4, color)
            }

            x = step.rightX
        }
    }

    // Draw an already shaped text run
    mtd drawShapedRun(left, top: f32, shaped: *ShapedRun, font: *Font, brush: Brush, under = UnderlineStyle.None, zoom = 1.0)
    {
        .drawShapedRun(left, top, shaped, font, brush, TextEffect{}, under, zoom)
    }

    // Draw an already shaped text run, with MSDF text effects (outline/glow/bevel/
    // shadow). Effects are ignored when the resolved draw font is not MSDF.
    mtd drawShapedRun(left, top: f32, shaped: *ShapedRun, font: *Font, brush: Brush, effect: TextEffect, under = UnderlineStyle.None, zoom = 1.0)
    {
        if shaped.glyphs.isEmpty() do
            return
        if .layoutOnly do
            return

        // Nothing visible: no face fill and no outline/glow/shadow either.
        if .isInvisible(brush) and effect.outlineColor.a == 0 and effect.glowColor.a == 0 and !effect.hasShadow() do
            return

        var info = Painter.computeTextDrawInfo(font, zoom, .textTransformScale())

        // Under a translation-only transform, fold the translation into the snap so
        // glyph edges land on the device grid on screen, matching the caret's
        // translation-aware snapToDeviceX.
        if .curState.transform.isTranslationOnly()
        {
            info.snapOffsetX = .curState.transform.tx
            info.snapOffsetY = .curState.transform.ty
        }

        let drawFont   = info.drawFont
        let snapPixels = info.snapPixels
        let isMsdf     = drawFont.cache.renderMode == .Msdf

        var drawShape: ShapedRun
        var runToDraw: *ShapedRun = shaped
        if shaped.font != drawFont
        {
            drawShape = shapeRunForFont(shaped, drawFont)
            runToDraw = &drawShape
        }

        let drawLeft = snapTextPosition(left, snapPixels, info.deviceScale, info.snapOffsetX)
        let y        = snapTextPosition(top + font.ascent * zoom, snapPixels, info.deviceScale, info.snapOffsetY)

        switch drawFont.cache.renderMode
        {
        case .Msdf: .startMsdfFont()
        default:    .startFont()
        }

        .updateFont(drawFont)

        // Drop shadow: an offset pass behind the text, drawn solid in the shadow
        // color (paint reset to solid). Binds the glyph atlas, so reset the font
        // texture afterwards to keep the underline (which samples a white texture).
        if isMsdf and effect.hasShadow()
        {
            .resetTexture0()
            .setFontEffect(effect.shadowParams())
            .pushShapedGlyphs(runToDraw, drawFont, info, left, y, effect.shadowOffset.x * zoom, effect.shadowOffset.y * zoom, snapPixels, effect.shadowColor)
            .resetTextureFont()
        }

        // Set brush main texture
        if brush.type != .SolidColor
        {
            let paintBounds = shaped.hasInk ? shaped.inkBounds : Math.Rectangle{0, -shaped.metrics.ascent, shaped.metrics.width, shaped.metrics.height}
            .setTexture0({drawLeft + paintBounds.x * zoom, y + paintBounds.y * zoom}, {drawLeft + paintBounds.right() * zoom, y + paintBounds.bottom() * zoom}, brush)
        }
        else do
            .resetTexture0()

        if isMsdf do
            .setFontEffect(effect.faceParams())

        // Underline
        if under != .None
        {
            var pen = Pen.createSolid(brush.color, .hairline(Math.floor(font.underlineSize)))
            pen.begCapStyle = .None
            pen.endCapStyle = .None

            .canSetTexture0 = false
            switch under
            {
            case .Strikeout:
                let yUnder = y - (shaped.metrics.ascent * zoom / 2)
                .drawLine(drawLeft, yUnder, drawLeft + shaped.metrics.width * zoom, yUnder, pen)

            case .Underline:
                let yUnder = y - font.underlinePos
                .drawLine(drawLeft, yUnder, drawLeft + shaped.metrics.width * zoom, yUnder, pen)
            }

            .canSetTexture0 = true
        }

        .pushShapedGlyphs(runToDraw, drawFont, info, left, y, 0, 0, snapPixels, brush.color)

        .resetTextureFont()
        .endFont()
    }

    // Draw a simple string (centered)
    mtd drawStringCenter(x, y: f32, text: string, font: *Font, color: Color, under = UnderlineStyle.None, zoom = 1.0)
    {
        let ms = measureString(text, font)
        var yr = y - (ms.height * 0.5 * zoom)
        yr -= (font.ascent - ms.ascent) * zoom
        .drawString(x - (ms.width * 0.5 * zoom), yr, text, font, color, under, zoom)
    }

    // Draw a simple string
    mtd drawString(left, top: f32, text: string, font: *Font, color: Color, under = UnderlineStyle.None, zoom = 1.0)
    {
        if @countof(text) == 0 or .isInvisible(color) do
            return

        let brush = Brush.createSolid(color)
        .drawString(left, top, text, font, brush, under, zoom)
    }

    // Draw a simple string
    mtd drawString(left, top: f32, text: string, font: *Font, brush: Brush, under = UnderlineStyle.None, zoom = 1.0)
    {
        if @countof(text) == 0 or .isInvisible(brush) do
            return
        if .layoutOnly do
            return

        // Shape directly on the resolved draw font. For an 'Auto' font drawn small
        // this is the crisp bitmap, so we avoid rasterizing the (unused) MSDF glyph
        // and the subsequent re-shape that drawShapedRun would otherwise do. Shaping
        // into the painter's reusable scratch run avoids a per-call glyph allocation.
        let info = Painter.computeTextDrawInfo(font, zoom, .textTransformScale())
        Painter.shapeRunInto(&.scratchShaped, text, info.drawFont)
        .drawShapedRun(left, top, &.scratchShaped, font, brush, under, zoom)
    }

    // Draw a simple string with MSDF text effects (outline/glow/bevel/shadow).
    mtd drawString(left, top: f32, text: string, font: *Font, color: Color, effect: TextEffect, under = UnderlineStyle.None, zoom = 1.0)
    {
        if @countof(text) == 0 do
            return
        let brush = Brush.createSolid(color)
        .drawString(left, top, text, font, brush, effect, under, zoom)
    }

    // Draw a simple string with a brush and MSDF text effects.
    mtd drawString(left, top: f32, text: string, font: *Font, brush: Brush, effect: TextEffect, under = UnderlineStyle.None, zoom = 1.0)
    {
        if @countof(text) == 0 do
            return
        if .layoutOnly do
            return

        let info = Painter.computeTextDrawInfo(font, zoom, .textTransformScale())
        Painter.shapeRunInto(&.scratchShaped, text, info.drawFont)
        .drawShapedRun(left, top, &.scratchShaped, font, brush, effect, under, zoom)
    }

    // Recompute the layout for a given rectangle
    //
    // `deviceScale` must match the scale the text is drawn with. Chunk widths are
    // measured with the same resolved draw font and device-snapped advances the
    // draw pass uses, so wrapped lines, alignment, and inter-chunk gaps land where
    // the glyphs actually end; measuring with nominal advances instead lets a
    // per-glyph drift accumulate until a space between two chunks visually vanishes.
    func computeLayout(pos: Math.Rectangle, text: *RichString, format: RichStringFormat, deviceScale = 1.0'f32)
    {
        Debug.assert(format.font.regular != null, "invalid default font")
        text.layoutRect  = pos
        text.layoutScale = deviceScale

        struct OneLine
        {
            public
            {
                measure:     StringMetrics
                height:      f32
                fontAscent:  f32
                fontDescent: f32
                start, end:  s32
                countSpaces: s32
                whiteSpaces: f32
                hasEol:      bool
            }
        }

        // Divide in lines
        var lines: Array'OneLine
        var line:  OneLine

        var startLine         = 0
        var lastWasSpace      = false
        let defaultLineHeight = format.font.regular!.height
        for &resetChunk in text.chunks do
            resetChunk.visible = false

        for &c, idx in text.chunks
        {
            // Attributes
            let fs = c.hasFontStyle ? c.fontStyle : format.fontStyle
            c.font = format.font.getFont(fs)!

            // Measure. The width uses the same resolved draw font and device-snapped
            // advances the chunk is drawn with (see the function comment); vertical
            // metrics stay nominal, they position lines, not glyph runs.
            c.shaped = shapeRun(c.slice, c.font, format.tabSize, format.letterSpacing)
            var ms = c.shaped.metrics
            ms.width    = measureStringSnapped(&c.shaped, deviceScale: deviceScale)
            c.boundRect = {0, 0, ms.width, ms.height}

            // Whether the chunk before this one was whitespace, which is what decides if a line
            // closed here ends on a space it should drop. Read into a local and advanced now,
            // because both branches below leave the iteration early: left to the bottom of the
            // loop, the flag still described the chunk before last, and a run too wide to break
            // was mistaken for that trailing space and cut off the line it had just opened —
            // which made a path or a URL between two spaces vanish from the layout entirely.
            let previousWasSpace = lastWasSpace
            lastWasSpace = c.isSpace

            // User eol
            if c.isEol
            {
                line.start  = startLine
                line.end    = cast(s32) idx
                line.height = Math.max(defaultLineHeight, line.fontAscent - line.fontDescent)
                if format.minLineHeight > 0 do
                    line.height = Math.max(line.height, format.minLineHeight)
                line.hasEol = true
                lines.add(line)

                startLine                                 = line.end + 1
                line.measure.width, line.measure.height   = 0
                line.measure.ascent, line.measure.descent = 0
                line.height                               = 0
                line.fontAscent, line.fontDescent         = 0
                line.countSpaces                          = 0
                line.whiteSpaces                          = 0
                line.hasEol                               = false
                continue
            }

            // Wrap
            if format.flags & .WordWrap or format.horzAlignment == .Justify
            {
                var curW = line.measure.width
                if format.horzAlignment == .Justify do
                    curW += line.whiteSpaces

                if curW + c.boundRect.width > pos.width
                {
                    if startLine != idx
                    {
                        line.start = startLine
                        line.end   = cast(s32) idx

                        // We: not want the current line to end with a space
                        if previousWasSpace and idx
                        {
                            line.countSpaces -= 1
                            if format.horzAlignment != .Justify do
                                line.measure.width -= text.chunks[idx - 1].boundRect.width
                            else do
                                line.whiteSpaces -= text.chunks[idx - 1].boundRect.width
                            line.end -= 1
                        }

                        line.height = Math.max(defaultLineHeight, line.fontAscent - line.fontDescent)
                        if format.minLineHeight > 0 do
                            line.height = Math.max(line.height, format.minLineHeight)
                        lines.add(line)
                    }

                    startLine                                 = cast(s32) idx
                    line.measure.width, line.measure.height   = 0
                    line.measure.ascent, line.measure.descent = 0
                    line.height                               = 0
                    line.fontAscent, line.fontDescent         = 0
                    line.countSpaces                          = 0
                    line.whiteSpaces                          = 0

                    // We: not want the new line to start with a space
                    if c.isSpace do
                        startLine += 1
                    else
                    {
                        line.measure.width   += ms.width
                        line.measure.ascent  = Math.max(line.measure.ascent, ms.ascent)
                        line.measure.descent = Math.max(line.measure.descent, ms.descent)
                        line.measure.height  = Math.max(line.measure.height, ms.height)
                        line.fontAscent      = Math.max(line.fontAscent, c.font.ascent)
                        line.fontDescent     = Math.min(line.fontDescent, c.font.descent)
                    }

                    continue
                }
            }

            if c.isSpace
            {
                line.countSpaces += 1
                if format.horzAlignment != .Justify do
                    line.measure.width += ms.width
                else do
                    line.whiteSpaces += ms.width
            }
            else do
                line.measure.width += ms.width
            line.measure.ascent  = Math.max(line.measure.ascent, ms.ascent)
            line.measure.descent = Math.max(line.measure.descent, ms.descent)
            line.measure.height  = Math.max(line.measure.height, ms.height)
            line.fontAscent      = Math.max(line.fontAscent, c.font.ascent)
            line.fontDescent     = Math.min(line.fontDescent, c.font.descent)

            c.boundRect.height = Math.max(c.font.height, ms.height)
        }

        if startLine != text.chunks.count
        {
            line.start  = startLine
            line.end    = cast(s32) text.chunks.count
            line.height = Math.max(defaultLineHeight, line.fontAscent - line.fontDescent)
            if format.minLineHeight > 0 do
                line.height = Math.max(line.height, format.minLineHeight)
            lines.add(line)
        }

        // A line budget drops everything below the line it stops on. Remember which line that is,
        // so the ellipsis pass below can mark it: a paragraph cut short otherwise reads as one
        // that simply ended there, and nothing tells the reader there was more.
        var cutLine = -1's64
        if format.maxLines and lines.count > format.maxLines
        {
            lines.resize(cast(u64) format.maxLines)
            lines[lines.count - 1].hasEol = false
            cutLine = cast(s64) lines.count - 1
        }

        // Ellipsis
        //
        // A line the rectangle cannot hold is cut where the room runs out and finished with an
        // ellipsis, so an unbreakable run — a path, a URL — reports that it was shortened
        // instead of silently losing its tail to the edge. The line a budget stopped on takes the
        // mark for the text below it, whether or not it overflows itself. Justified text is left
        // alone: its spacing math owns the line width.
        if format.flags & .Ellipsis and format.horzAlignment != .Justify and pos.width > 0
        {
            for i in lines.count
            {
                let l      = &lines[i]
                let wasCut = cast(s64) i == cutLine and l.end > l.start
                if l.measure.width <= pos.width and !wasCut do
                    continue

                // The chunk the overflow lands in, and the width of everything before it.
                var accum: f32
                var cut = -1's32
                for idx in l.start until l.end
                {
                    let w = text.chunks[idx].boundRect.width
                    if accum + w > pos.width
                    {
                        cut = idx
                        break
                    }

                    accum += w
                }

                // The line itself holds; it is the text under it that went missing, so the mark
                // lands after its last chunk instead of in place of an overflow.
                if cut < 0
                {
                    if !wasCut do
                        continue

                    cut   = l.end - 1
                    accum = 0
                    for idx in l.start until cut do
                        accum += text.chunks[idx].boundRect.width
                }

                // Back off while what is left cannot even hold the mark, so a cut landing just
                // short of the edge does not push the ellipsis past it. The mark inherits the cut
                // chunk's style; a typeface without the ellipsis glyph falls back to three dots.
                var mark = ""
                var room = 0'f32
                while true
                {
                    let scan = &text.chunks[cut]
                    mark = scan.font.glyphIndex(EllipsisRune) ? "\u2026" : "..."
                    room = pos.width - accum - measureStringSnapped(mark, scan.font, deviceScale: deviceScale)
                    if room >= 0 or cut == l.start
                    {
                        room = Math.max(room, 0)
                        break
                    }

                    cut   -= 1
                    accum -= text.chunks[cut].boundRect.width
                }

                let c        = &text.chunks[cut]
                let fitBytes = fitShapedPrefix(&c.shaped, room, deviceScale)

                var trimmed = String.from(fitBytes == Swag.U64.Max ? c.slice : @mkstring(@dataof(c.slice), fitBytes))
                trimmed += mark

                // A shaped run copies the glyphs it needs and borrows nothing from its source
                // text, so shaping a temporary is safe; the next layout re-shapes the chunk from
                // its own slice, which this pass leaves intact.
                c.shaped          = shapeRun(trimmed.toString(), c.font, format.tabSize, format.letterSpacing)
                c.boundRect.width = measureStringSnapped(&c.shaped, deviceScale: deviceScale)

                l.end           = cut + 1
                l.measure.width = accum + c.boundRect.width
            }
        }

        let x = text.layoutRect.x
        var y = text.layoutRect.y

        // Vertical
        //
        // A line stands as tall as the band the font reserves for it, whatever glyphs it
        // happens to carry, and a single line is no exception. Measured on its own ink
        // instead, a word holding a descender would be centered lower than one without and
        // a word holding an accent higher, so a menu bar or a column of labels would sit on
        // as many baselines as it has words.
        var totalHeight: f32
        for &l, idxLine in lines
        {
            totalHeight += l.height
            if idxLine != lines.count - 1
            {
                totalHeight += cast(f32) format.lineGap
                if l.hasEol do
                    totalHeight += cast(f32) format.paragraphGap
            }
        }

        switch format.vertAlignment
        {
        case .Bottom:
            y = pos.bottom() - totalHeight

        case .Center:
            y = pos.vertCenter() - (totalHeight * 0.5)

        // Centered on the capitals rather than on the line box, so the placement stops following
        // the internal leading of the face. See [[Pixel.Font.opticalLineTop]].
        case .OpticalCenter:
            y = pos.vertCenter() - (totalHeight * 0.5) - format.font.regular!.opticalOffset()
        }

        text.boundRect.x      = Swag.F32.Max
        text.boundRect.y      = y
        text.boundRect.width  = 0
        text.boundRect.height = totalHeight
        var boundRight = Swag.F32.NegInf

        // Layout
        for &l, idxLine in lines
        {
            var x1 = x
            let y1 = y

            switch format.horzAlignment
            {
            case .Left:   break
            case .Right:  x1 = pos.right() - l.measure.width
            case .Center: x1 = pos.horzCenter() - l.measure.width * 0.5
            }

            if l.end > l.start
            {
                for idx in l.start until l.end
                {
                    let c = &text.chunks[idx]
                    c.visible = true
                    c.pos.x   = x1
                    c.pos.y   = y1 + (l.fontAscent - c.font.ascent)

                    text.boundRect.x = Math.min(text.boundRect.x, c.pos.x)
                    boundRight       = Math.max(boundRight, c.pos.x + c.boundRect.width)

                    if c.isSpace and format.horzAlignment == .Justify and idxLine != lines.count - 1 and !l.hasEol
                    {
                        let spaceW = (pos.width - l.measure.width) / l.countSpaces
                        if spaceW < l.measure.height * format.justifyLimit do
                            x1 += spaceW
                        else do
                            x1 += c.boundRect.width
                    }
                    else do
                        x1 += c.boundRect.width
                }
            }

            y += l.height
            if idxLine != lines.count - 1
            {
                y += cast(f32) format.lineGap
                if l.hasEol do
                    y += cast(f32) format.paragraphGap
            }
        }

        if text.boundRect.x == Swag.F32.Max
        {
            text.boundRect.x = x
            boundRight       = x
        }

        text.boundRect.width = boundRight - text.boundRect.x
    }

    // Draws a laid-out rich string.
    //
    // A rich string can be multiline, and accepts private formats.
    // The layout will be computed at the first call, and each time 'pos' has changed.
    mtd drawRichString(pos: Math.Rectangle, text: *RichString, format: RichStringFormat, forceCompute = false)
    {
        text.compute()
        if text.chunks.isEmpty() do
            return

        // Recompute layout if the rectangle or the device scale has changed; the
        // layout measures with the scale's draw-font advances, so a cached layout
        // from another scale would no longer match the drawn glyphs.
        let deviceScale = .textTransformScale()
        if text.layoutRect != pos or text.layoutScale != deviceScale or forceCompute do
            computeLayout(pos, text, format, deviceScale)

        // Clipping
        if format.flags & .Clip
        {
            .pushClippingRect(pos)
            if .curState.clippingRect.isEmpty()
            {
                .popClippingRect()
                return
            }
        }

        // Draw
        var brush = format.brush
        for &c in text.chunks
        {
            if c.isEol or !c.visible do
                continue

            if c.isHotUrl do
                brush.color = format.colorHotUrl
            elif c.isUrl do
                brush.color = format.colorUrl
            else do
                brush.color = format.palette[c.colorIdx]

            var under = c.under
            if c.isHotUrl do
                under = .Underline

            .drawShapedRun(c.pos.x, c.pos.y, &c.shaped, c.font, brush, under)
        }

        // Restore clipping to its previous value
        if format.flags & .Clip do
            .popClippingRect()
    }
}
