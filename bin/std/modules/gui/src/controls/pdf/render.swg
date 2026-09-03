#global public
#global namespace Pdf

using Core, Pixel

// Controls page rasterization.
struct RenderOptions
{
    public
    {
        scale:            f32    = 1                              // Output pixels per PDF point.
        background:       Color  = Color.fromArgb(Argb.White)     // Ground painted before page content.
        maxDimension:     s32    = 16_384                         // Largest accepted output width or height in pixels.
        maxPixels:        u64    = 67_108_864                     // Largest accepted output pixel count.
        fallbackFontFile: string = ""                             // Optional TrueType font used when a PDF font cannot be decoded or safely addressed.

        // Page region to rasterize, in PDF points from the page's top-left corner. An empty
        // rectangle renders the complete page. A viewer zooming into one part of a page renders
        // that part alone, so the cost of a deep zoom is the visible region, never the page.
        sourceRect: Math.Rectangle
    }
}

using Core.Math

private func loadTypeface(name: string)->#null *TypeFace fail => try TypeFace.load(name)
private func createTypeface(name: string, bytes: const [..] u8)->#null *TypeFace fail => try TypeFace.create(name, bytes)

// Faces a page falls back to, grouped by the shape of the font the document asked for.
//
// A substitute that ignores the requested shape is what makes a rendered page read as the
// wrong document: a serif paper set in a sans face changes every line of it. Each row is
// tried in order, so a machine missing the first name still gets the closest match it has.
private const SubstituteSerif: [4] [4] string = [
    ["times.ttf", "DejaVuSerif.ttf", "LiberationSerif-Regular.ttf", "georgia.ttf"],
    ["timesbd.ttf", "DejaVuSerif-Bold.ttf", "LiberationSerif-Bold.ttf", "georgiab.ttf"],
    ["timesi.ttf", "DejaVuSerif-Italic.ttf", "LiberationSerif-Italic.ttf", "georgiai.ttf"],
    ["timesbi.ttf", "DejaVuSerif-BoldItalic.ttf", "LiberationSerif-BoldItalic.ttf", "georgiaz.ttf"]]

private const SubstituteSans: [4] [4] string = [
    ["arial.ttf", "segoeui.ttf", "DejaVuSans.ttf", "LiberationSans-Regular.ttf"],
    ["arialbd.ttf", "segoeuib.ttf", "DejaVuSans-Bold.ttf", "LiberationSans-Bold.ttf"],
    ["ariali.ttf", "segoeuii.ttf", "DejaVuSans-Oblique.ttf", "LiberationSans-Italic.ttf"],
    ["arialbi.ttf", "segoeuiz.ttf", "DejaVuSans-BoldOblique.ttf", "LiberationSans-BoldItalic.ttf"]]

private const SubstituteMono: [4] [4] string = [
    ["cour.ttf", "consola.ttf", "DejaVuSansMono.ttf", "LiberationMono-Regular.ttf"],
    ["courbd.ttf", "consolab.ttf", "DejaVuSansMono-Bold.ttf", "LiberationMono-Bold.ttf"],
    ["couri.ttf", "consolai.ttf", "DejaVuSansMono-Oblique.ttf", "LiberationMono-Italic.ttf"],
    ["courbi.ttf", "consolaz.ttf", "DejaVuSansMono-BoldOblique.ttf", "LiberationMono-BoldItalic.ttf"]]

// Returns the face standing in for a font whose program cannot be drawn.
private func substituteTypeface(fallbackFontFile: string, resource: #null const *FontResource)->*TypeFace fail
{
    if fallbackFontFile.count do
        return try TypeFace.load(fallbackFontFile)

    var serif      = false
    var fixedPitch = false
    var style      = 0'u64
    if resource
    {
        serif      = resource!.serif
        fixedPitch = resource!.fixedPitch
        if resource!.bold do
            style |= 1
        if resource!.italic do
            style |= 2
    }

    var family = SubstituteSans
    if fixedPitch do
        family = SubstituteMono
    elif serif do
        family = SubstituteSerif

    // The requested style first, then the regular weight of the same family, then anything
    // at all: a missing italic must not cost the reader the serif shape as well.
    for candidate in family[style]
    {
        let result = catch loadTypeface(candidate) as loadError
        if loadError == null do
            return result!
    }

    for candidate in family[0]
    {
        let result = catch loadTypeface(candidate) as loadError
        if loadError == null do
            return result!
    }

    for candidate in SubstituteSans[0]
    {
        let result = catch loadTypeface(candidate) as loadError
        if loadError == null do
            return result!
    }

    fail Errors.UnsupportedFormatError{"no substitute font is available"}
}

// How far a substituted run may be condensed or expanded to fit the widths the document
// declared. Beyond this the substitute is so far from the requested face that distorting it
// further would read worse than letting it overflow.
private const MinSubstituteCondense = 0.5'f32
private const MaxSubstituteCondense = 2.0'f32

// Typefaces resolved once per page rather than once per text item.
//
// Resolving an embedded face hashes the complete font program to key the process-wide
// typeface cache, so a page with thousands of runs must not pay it per run: at one hash per
// item, re-rendering a dense page reads hundreds of megabytes of font bytes before it draws
// a single glyph, which is what a viewer experiences as a freeze on every zoom step. An
// offline render owns one for its lifetime; [[Gui.PdfView]] keeps one per displayed page, so
// no paint resolves a face the previous paint already resolved.
//
// Dependency-visible backing type required by the concrete [[Gui.PdfView]] layout.
#[Swag.Opaque, Swag.NoDoc]
struct RenderFontCache
{
    embedded:           Array'(#null *TypeFace)     // Per page font index, once resolution was attempted.
    embeddedResolved:   Array'bool
    substitute:         Array'(#null *TypeFace)     // Substitute face per page font index.
    substituteResolved: Array'bool
    fallback:           #null *TypeFace     // Substitute face for text with no font resource.
    fallbackResolved:   bool
}

internal impl RenderFontCache
{
    mtd prepare(count: u64)
    {
        .embedded.resize(count)
        .embeddedResolved.resize(count)
        .substitute.resize(count)
        .substituteResolved.resize(count)
    }

    // Forgets every resolution, then sizes the cache for a page's font table.
    //
    // The typefaces themselves live in the process-wide table and are not owned here, so
    // dropping the views is enough when the displayed page changes.
    mtd reset(count: u64)
    {
        .embedded.clear()
        .embeddedResolved.clear()
        .substitute.clear()
        .substituteResolved.clear()
        .fallback         = null
        .fallbackResolved = false
        .prepare(count)
    }

    // Returns the face built from an embedded font program, or nothing when it cannot be read.
    mtd embeddedFace(index: u32, resource: const *FontResource)->#null *TypeFace
    {
        if index >= .embedded.count do
            return null
        if !.embeddedResolved[index]
        {
            .embeddedResolved[index] = true
            if !resource.bytes.isEmpty()
            {
                let result = catch createTypeface(resource.programKey.toString(), resource.bytes.toSlice()) as loadError
                if loadError == null do
                    .embedded[index] = result
            }
        }

        return .embedded[index]
    }

    // Returns the face standing in for a font whose program cannot be drawn.
    mtd substituteFace(fallbackFontFile: string, index: u32, resource: #null const *FontResource)->*TypeFace fail
    {
        if !resource or index >= .substitute.count
        {
            if !.fallbackResolved
            {
                .fallback         = try substituteTypeface(fallbackFontFile, null)
                .fallbackResolved = true
            }

            return .fallback!
        }

        if !.substituteResolved[index]
        {
            .substitute[index]         = try substituteTypeface(fallbackFontFile, resource)
            .substituteResolved[index] = true
        }

        return .substitute[index]!
    }
}

// One PDF character code and the glyphs a substitute face spells it with.
private struct SubstitutedGroup
{
    first:    u64     // Index of the code's first glyph in the run.
    count:    u64     // Glyphs the code expanded into.
    declared: f32     // Advance the document gave the code.
    natural:  f32     // Advance the substitute's own glyphs would take.
}

// Returns the local vertical offset that puts a run on the baseline the page declares.
//
// A decoded text item places its origin one em above the baseline, because that is where a
// run drawn from its top-left corner has to start. How far below the top the baseline
// actually falls is a property of the face, not of the size, so a run drawn at zero would
// sit wherever the chosen face happens to put its ascender — and two runs of one line drawn
// with different faces would not share a baseline at all.
private func baselineOffset(item: const *Item, font: *Font)->f32
{
    return item.fontSize - font.ascent
}

// Draws a run through the embedded font program, addressed the way the document keys it.
//
// The PDF advances stay authoritative rather than the font's own: they are what the writer
// laid the line out with, so honouring them is what makes a justified paragraph meet its
// right margin and a run split across `TJ` entries join without a seam.
//
// Returns false when any code fails to reach a glyph, which leaves the whole run to the
// substitute face rather than drawing a line with holes in it.
private func drawEmbeddedRun(painter: *Painter, item: const *Item, resource: const *FontResource, font: *Font)->bool
{
    if item.textCodes.isEmpty() or item.textCodes.count != item.textAdvances.count do
        return false

    let info = Painter.computeTextDrawInfo(font, 1, painter.textTransformScale())
    var shaped: ShapedRun
    shaped.font = info.drawFont
    shaped.glyphs.reserve(item.textCodes.count)
    for code, index in item.textCodes
    {
        let mapped = resource.glyphFor(info.drawFont, code)
        if !mapped.found do
            return false
        var glyph: ShapedGlyph
        glyph.desc       = info.drawFont.getGlyphDescByIndex(mapped.index)
        glyph.glyphIndex = mapped.index
        glyph.cluster    = index
        glyph.advanceX   = item.textAdvances[index] / info.scale
        shaped.glyphs.add(glyph)
    }

    painter.drawShapedRun(0, baselineOffset(item, font), &shaped, font, Brush.createSolid(item.fillColor))
    return true
}

// Draws a run with a substitute face, keeping every character on the position the document
// gave it.
//
// The substitute has metrics of its own, and letting them drive the run is what collapses
// the spaces between words and walks the line off its margin. Each code is drawn inside the
// advance the PDF declared for it instead: one character usually, several when the code
// stands for a ligature the substitute spells out, and their widths are scaled to fill
// exactly that advance.
private func drawSubstitutedRun(painter: *Painter, item: const *Item, base: Transform2, resource: #null const *FontResource, font: *Font)
{
    let info = Painter.computeTextDrawInfo(font, 1, painter.textTransformScale())
    if !resource or item.textCodes.isEmpty() or item.textCodes.count != item.textAdvances.count
    {
        painter.drawString(0, baselineOffset(item, font), item.text.toString(), font, item.fillColor)
        return
    }

    // What each code contributed, so the run can be fitted once its full width is known.
    var groups: Array'SubstitutedGroup
    var shaped: ShapedRun
    shaped.font = info.drawFont
    shaped.glyphs.reserve(item.textCodes.count)
    groups.reserve(item.textCodes.count)

    var declaredTotal = 0.0'f32
    var naturalTotal  = 0.0'f32
    for code, index in item.textCodes
    {
        let text = resource!.codeText(code)
        var group: SubstitutedGroup
        group.first    = shaped.glyphs.count
        group.declared = item.textAdvances[index] / info.scale

        Utf8.visitRunes(text.toString())
        {
            let glyphIndex = info.drawFont.glyphIndex(c)
            var glyph: ShapedGlyph
            glyph.desc       = info.drawFont.getGlyphDescByIndex(glyphIndex)
            glyph.glyphIndex = glyphIndex
            glyph.cluster    = index
            glyph.advanceX   = glyph.desc.advanceX
            group.natural    += glyph.desc.advanceX
            shaped.glyphs.add(glyph)
        }

        if shaped.glyphs.count == group.first
        {
            // A code with no character at all still separates what surrounds it.
            var blank: ShapedGlyph
            blank.desc     = info.drawFont.getGlyphDescByIndex(0)
            blank.cluster  = index
            blank.advanceX = group.declared
            shaped.glyphs.add(blank)
        }

        group.count   = shaped.glyphs.count - group.first
        declaredTotal += group.declared
        naturalTotal  += group.natural
        groups.add(group)
    }

    // A substitute is only ever approximately the face the document asked for, and its
    // letters are usually the wider ones. Placing each code at the position the PDF gave it
    // is not enough on its own: a letter wider than the space reserved for it runs into the
    // next one, which is what turns a diagram label into a smudge. Condensing the whole run
    // by the ratio of the two widths makes the glyphs fit the room the writer left them,
    // and leaves a well-matched substitute untouched.
    var condense = 1.0'f32
    if naturalTotal > 0 and declaredTotal > 0 do
        condense = Math.clamp(declaredTotal / naturalTotal, MinSubstituteCondense, MaxSubstituteCondense)

    for group in groups
    {
        // Spread the declared advance over the characters the code expanded into, in
        // proportion to their own widths so a ligature still reads as one shape.
        let target = group.declared / condense
        if group.natural > 0
        {
            let ratio = target / group.natural
            for i in group.first until group.first + group.count do
                shaped.glyphs[i].advanceX *= ratio
        }
        elif group.count
        {
            shaped.glyphs[group.first].advanceX = target
        }
    }

    var transform = Transform2.createScale(condense, 1, 0, 0)
    transform.multiply(base)
    painter.setTransform(transform)
    painter.drawShapedRun(0, baselineOffset(item, font), &shaped, font, Brush.createSolid(item.fillColor))
    painter.setTransform(base)
}

// Draws one text item, preferring the embedded program and falling back to a matching face.
private func drawTextItem(painter: *Painter, fonts: *RenderFontCache, cache: *FontCache, page: const *Page, item: const *Item, base: Transform2, fallbackFontFile: string) fail
{
    let fontSize = cast(u32) Math.max(1, Math.round(item.fontSize))
    let resource = item.fontIndex < page.fonts.count ? &page.fonts[item.fontIndex] : null

    if resource
    {
        let embedded = fonts.embeddedFace(item.fontIndex, resource!)
        if embedded
        {
            let font = cache.createFont(embedded!, fontSize)
            if drawEmbeddedRun(painter, item, resource!, font) do
                return
        }
    }

    let substitute = try fonts.substituteFace(fallbackFontFile, item.fontIndex, resource)
    drawSubstitutedRun(painter, item, base, resource, cache.createFont(substitute, fontSize))
}

private func pathPen(item: const *Item, scale: f32)->Pen
{
    let strokeWidth    = item.strokeWidth ? item.strokeWidth : 1 / scale
    var result: retval = Pen.createSolid(item.strokeColor, strokeWidth)
    switch item.strokeStyle.cap
    {
    case .Butt:
        result.begCapStyle     = .None
        result.endCapStyle     = .None
        result.dashBegCapStyle = .None
        result.dashEndCapStyle = .None

    case .Round:
        result.begCapStyle     = .Round
        result.endCapStyle     = .Round
        result.dashBegCapStyle = .Round
        result.dashEndCapStyle = .Round

    case .Square:
        result.begCapStyle     = .Square
        result.endCapStyle     = .Square
        result.dashBegCapStyle = .Square
        result.dashEndCapStyle = .Square
    }

    switch item.strokeStyle.join
    {
    case .Miter: result.joinStyle = .MiterBevel
    case .Round: result.joinStyle = .Round
    case .Bevel: result.joinStyle = .Bevel
    }

    result.joinMiterLimit = item.strokeStyle.miterLimit
    result.dashOffset     = item.strokeStyle.dashPhase
    if item.strokeStyle.dashPattern.count
    {
        result.dashStyle = .Pattern
        result.pattern.reserve(item.strokeStyle.dashPattern.count)
        for length in item.strokeStyle.dashPattern do
            result.pattern.add(length / strokeWidth)
    }

    return result
}

// Returns the rule a clip shape is filled under.
private func clipFillRule(clip: const *ClipPath)->PathFillRule => clip.evenOdd ? PathFillRule.EvenOdd : PathFillRule.NonZero

// Returns how many page points the longer side of an image's unit square spans.
private func unitSquareScale(transform: Transform2)->f32
{
    let width  = Math.sqrt(transform.m11 * transform.m11 + transform.m12 * transform.m12)
    let height = Math.sqrt(transform.m21 * transform.m21 + transform.m22 * transform.m22)
    return Math.max(width, height)
}

// Writes one clip shape into the painter's clipping region, in page coordinates.
//
// The region carries coverage, so the shape is filled the way any shape is: its antialiased
// edge becomes the edge of every mark cut by it.
private func writeClipRegion(painter: *Painter, clip: *ClipPath, pageToSurface: Transform2)
{
    if painter.transform() != pageToSurface do
        painter.setTransform(pageToSurface)

    painter.startClippingRegion(.Set)
    painter.fillPath(&clip.path, Color.fromArgb(Argb.White), clipFillRule(clip))
    painter.endClippingRegion()
}

// Draws the decoded items of a page through a painter, in paint order.
//
// This is the one drawing path: [[Pdf.Page.render]] runs it against an offline CPU target,
// and [[Gui.PdfView]] runs it against the frame being painted, so a page looks the same on
// both. `pageToSurface` maps page points to the painter's surface space and must only scale
// and translate, because item clips are axis-aligned page rectangles. `devicePerPoint` is
// how many device pixels one PDF point covers on the target; it sizes hairline strokes,
// never the geometry. `textures` carries one entry per image item in paint order, and an
// invalid entry skips its image. An item consumes one entry when it carries an image of its own
// or a soft mask coverage, which are the two things this drawing needs a texture for.
//
// Fills cache their tessellation inside the page items, which is what makes drawing the same
// page again cheap. The caller owns the painter's transform state and restores it afterwards.
internal func drawPageItems(painter: *Painter, page: *Page, pageToSurface: Transform2, devicePerPoint: f32, fonts: *RenderFontCache, fallbackFontFile: string, textures: const [..] Texture) fail
{
    let previousBlend = painter.blendingMode()
    defer painter.setBlendingMode(previousBlend)

    // A page's rasters are photographs and scans placed at whatever size the document chose, never
    // pixel art the reader is meant to see the texels of, so they are sampled smoothly. The
    // painter defaults to nearest, which is right for an icon and wrong for a picture: it turns
    // the fine detail of a downscaled illustration into a moiré of the texels that happened to
    // land under a pixel centre.
    let previousInterpolation = painter.interpolationMode()
    painter.setInterpolationMode(.Linear)
    defer painter.setInterpolationMode(previousInterpolation)

    // Curves are flattened in page units, so the zoom has to reach the tolerance for a
    // magnified page to stay smooth; the painter buckets it so the caches re-key rarely.
    let previousFlattenScale = painter.flattenScale()
    painter.setFlattenScale(devicePerPoint)
    defer painter.setFlattenScale(previousFlattenScale)

    let fontCache    = painter.renderer().fontCache()
    var textureIndex = 0'u64

    // Consecutive items usually share one clip — a paragraph inside a text box states it once per
    // show operation — so the region is pushed when it changes and held across the run rather than
    // pushed and popped around every mark.
    var activeClip:    Math.Rectangle
    var hasActiveClip: bool
    defer if hasActiveClip do
        painter.popClippingRect()

    // A shaped clip is a clipping region, and consecutive items usually share one the same way
    // they share a rectangle, so it is written when the shape changes and held across the run.
    var activeRegion = InvalidClipPath
    defer if activeRegion != InvalidClipPath do
        painter.resetClippingRegion()

    // What is being repainted, in the painter's own space. A page holds thousands of marks and a
    // frame usually shows a band of it, so a mark that cannot land in that band is worth naming
    // here rather than tessellating it and letting the renderer clip it away.
    let repainted = painter.clippingRect()

    for &item in page.items
    {
        // Text is the one kind whose extent the page cannot state on its own, so it is always
        // recorded; everything else answers for the box its marks cannot leave.
        if item.kind != .Text
        {
            let local = item.paintBounds()
            var mapped: Math.Rectangle
            mapped.x      = local.x * pageToSurface.m11 + pageToSurface.tx
            mapped.y      = local.y * pageToSurface.m22 + pageToSurface.ty
            mapped.width  = local.width * pageToSurface.m11
            mapped.height = local.height * pageToSurface.m22
            if !mapped.intersects(repainted)
            {
                if item.kind == .Image or item.hasMask do
                    textureIndex += 1
                continue
            }
        }

        // An image is cut by its own shape rather than through a region, so it names none here.
        // The region is written with no rectangle in force: two items sharing a shape need not
        // share a rectangle, and a region cut to the first item's rectangle would cut the second.
        let region = item.kind == .Image ? InvalidClipPath : item.clipPath
        if region != activeRegion
        {
            if hasActiveClip
            {
                painter.popClippingRect()
                hasActiveClip = false
            }

            if activeRegion != InvalidClipPath do
                painter.resetClippingRegion()
            if region != InvalidClipPath do
                writeClipRegion(painter, page.clipPaths[region]!, pageToSurface)
            activeRegion = region
        }

        // Almost every mark of a page is stated in page coordinates and shares one transform with
        // the marks around it, and stating it again is a command the renderer has to walk past.
        // The painter is asked what it currently holds rather than trusting a copy, because a
        // text run states a transform of its own and restores this one.
        var placed = item.transform
        placed.multiply(pageToSurface)
        if placed != painter.transform() do
            painter.setTransform(placed)

        // The clip is stated in page coordinates, so it maps through the page transform
        // rather than through the item's own.
        var clip: Math.Rectangle
        if item.hasClip
        {
            clip.x      = item.clip.x * pageToSurface.m11 + pageToSurface.tx
            clip.y      = item.clip.y * pageToSurface.m22 + pageToSurface.ty
            clip.width  = item.clip.width * pageToSurface.m11
            clip.height = item.clip.height * pageToSurface.m22
        }

        if hasActiveClip and (!item.hasClip or clip != activeClip)
        {
            painter.popClippingRect()
            hasActiveClip = false
        }

        if item.hasClip and !hasActiveClip
        {
            painter.pushClippingSurfaceRect(clip)
            activeClip    = clip
            hasActiveClip = true
        }

        // A blend mode is graphics state on the painter, so it is stated when it changes rather
        // than pushed and popped around every mark; almost every page is one mode throughout.
        if item.blend != painter.blendingMode() do
            painter.setBlendingMode(item.blend)

        // A soft mask covers a region of the page, not the shape sampling it, so the coverage is
        // anchored to the rectangle it was rasterized over. The mark's own colour is the tint, so
        // the brush produces exactly that colour at the coverage the mask states.
        //
        // A brush is anchored in the space the path states its own points in, which the painter's
        // transform then maps to the surface. For a decoded path that space is the page, so the
        // mask rectangle travels as it was recorded: mapping it here would move the mask with the
        // zoom while the shape it covers stayed put.
        var maskBrush: Brush
        if item.hasMask and textures[textureIndex].isValid()
        {
            maskBrush = Brush.createTexture(textures[textureIndex])
            maskBrush.mapOver(item.maskRect)
        }

        switch item.kind
        {
        case .Text:
            if item.text.isEmpty() and item.textCodes.isEmpty() do
                continue
            try drawTextItem(painter, fonts, fontCache, page, item, placed, fallbackFontFile)

        case .Path:

            // A page states its fill rule over the winding count, so the fill has to be
            // named rather than left to the winding direction of whatever the writer emitted.
            let rule = item.evenOddFill ? PathFillRule.EvenOdd : PathFillRule.NonZero
            if item.hasFill and maskBrush.type == .Texture
            {
                maskBrush.setTint(item.fillColor)
                painter.fillPath(&item.path, maskBrush, rule)
            }
            elif item.hasFill do
                painter.fillPath(&item.path, item.fillColor, rule)

            if item.hasStroke
            {
                var pen = pathPen(item, devicePerPoint)
                if maskBrush.type == .Texture
                {
                    maskBrush.setTint(item.strokeColor)
                    pen.brush = maskBrush
                }

                painter.drawPath(&item.path, pen, .Separate)
            }

        case .Image:
            if !textures[textureIndex].isValid() do
                break
            if item.clipPath == InvalidClipPath
            {
                painter.drawTexture(0, 0, 1, 1, textures[textureIndex], item.fillColor)
                break
            }

            // The image is drawn as its clip shape filled with its texture: the fill a rectangle
            // gets, over the shape the author cut, with an antialiased edge. The shape lives in the
            // image's unit square, where a segment is as many times shorter than on the page as
            // the image is wide in points, so the flattening tolerance follows the image's scale.
            var brush = Brush.createTexture(textures[textureIndex])
            brush.mapOver({0, 0, 1, 1})
            brush.setTint(item.fillColor)
            let clip = page.clipPaths[item.clipPath]!
            painter.setFlattenScale(devicePerPoint * unitSquareScale(item.transform))
            painter.fillPath(&item.imageClip, brush, clipFillRule(clip))
            painter.setFlattenScale(devicePerPoint)
        }

        if item.kind == .Image or item.hasMask do
            textureIndex += 1
    }
}

internal func renderPage(page: *Page, options: RenderOptions)->Image fail
{
    if options.scale <= 0 or !Math.isFinite(options.scale) do
        fail Errors.BadParameterError{}
    if options.maxDimension <= 0 or !options.maxPixels do
        fail Errors.BadParameterError{}

    var region = Math.Rectangle{0, 0, page.width, page.height}
    if options.sourceRect.width > 0 and options.sourceRect.height > 0
    {
        if !Math.isFinite(options.sourceRect.x) or !Math.isFinite(options.sourceRect.y) or !Math.isFinite(options.sourceRect.width) or !Math.isFinite(options.sourceRect.height) do
            fail Errors.BadParameterError{}
        region = options.sourceRect
    }

    let scaledWidth  = Math.ceil(region.width * options.scale)
    let scaledHeight = Math.ceil(region.height * options.scale)
    if !Math.isFinite(scaledWidth) or !Math.isFinite(scaledHeight) or scaledWidth > cast(f32) options.maxDimension or scaledHeight > cast(f32) options.maxDimension do
        fail Errors.UnsupportedFormatError{"rendered PDF page exceeds the configured dimension limit"}
    let width  = cast(s32) Math.max(1, scaledWidth)
    let height = cast(s32) Math.max(1, scaledHeight)
    if cast(u64) width * cast(u64) height > options.maxPixels do
        fail Errors.UnsupportedFormatError{"rendered PDF page exceeds the configured pixel limit"}

    var cpu:      RenderCpu
    let renderer: IRenderer = &cpu
    var context             = #move try renderer.createContext(null, width, height)
    defer renderer.deleteContext(&context)

    renderer.begin(context)
    renderer.init()
    var target = renderer.createRenderTarget(width, height)
    var textures: Array'Texture
    textures.reserve(page.items.count)
    for item in page.items
    {
        // A soft mask coverage is already stated over a page-space rectangle; an image states
        // the unit square its transform maps onto the page.
        var bounds = item.maskRect
        if item.kind == .Image
        {
            let corners: [4] Vector2 = [
                item.transform.transformPoint({0, 0}),
                item.transform.transformPoint({1, 0}),
                item.transform.transformPoint({1, 1}),
                item.transform.transformPoint({0, 1})]
            var minX = corners[0].x
            var minY = corners[0].y
            var maxX = corners[0].x
            var maxY = corners[0].y
            for corner in corners
            {
                minX = Math.min(minX, corner.x)
                minY = Math.min(minY, corner.y)
                maxX = Math.max(maxX, corner.x)
                maxY = Math.max(maxY, corner.y)
            }

            bounds = {minX, minY, maxX - minX, maxY - minY}
        }
        elif !item.hasMask do
            continue

        // A region render leaves the textures it cannot show on the CPU side.
        if !bounds.intersects(region)
        {
            textures.add(Texture{})
            continue
        }

        textures.add(renderer.addImage(item.kind == .Image ? item.image : item.maskImage))
    }

    renderer.end()

    var painter = Painter.create(renderer)
    painter.setContentScale(options.scale)
    painter.begin()

    // A resolved alpha channel costs a second rasterization of the whole page in the
    // renderer's scalar path, and an opaque ground then overwrites every byte it produced.
    // Ask for it only when the caller wants the page's own coverage back.
    painter.bindRenderTarget(&target, options.background.a != 255)
    painter.setColorMaskFull()
    painter.clear(options.background)
    painter.setColorMaskColor()

    var fonts: RenderFontCache
    fonts.prepare(page.fonts.count)

    // A region render shifts every mark by the region origin; the whole page is the identity
    // region, so the same path serves both.
    try drawPageItems(&painter, page, Transform2.createTranslation(-region.x, -region.y), options.scale, &fonts, options.fallbackFontFile, textures.toSlice())

    painter.resetTransform()

    // Antialiased drawing resolves its coverage through the target alpha channel and therefore
    // replaces the alpha written by the initial clear. Restore an opaque page ground after the
    // content, just as ImageCanvas does, while preserving coverage for transparent renders.
    if options.background.a == 255
    {
        painter.setBlendingMode(.Copy)
        painter.setColorMaskAlpha()
        painter.fillRect({0, 0, region.width, region.height}, options.background)
        painter.setColorMaskColor()
        painter.setBlendingMode(.Alpha)
    }

    painter.unbindRenderTarget()
    painter.end()

    renderer.begin(context)
    painter.render()
    var result: retval = renderer.readRenderTarget(&target, 0, 0, width, height)
    for &texture in textures do
        renderer.removeTexture(texture)
    renderer.deleteRenderTarget(&target)
    renderer.end()
    return result
}
