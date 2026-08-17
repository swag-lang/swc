#global public

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
private func substituteTypeface(options: RenderOptions, resource: #null const *FontResource)->*TypeFace fail
{
    if @countof(options.fallbackFontFile) do
        return try TypeFace.load(options.fallbackFontFile)

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

// Returns the face built from an embedded font program, or nothing when it cannot be read.
private func embeddedTypeface(resource: const *FontResource)->#null *TypeFace
{
    if resource.bytes.isEmpty() do
        return null

    let key    = Format.toString("pdf-font-%{X08}", Hash.Crc32.compute(resource.bytes.toSlice()))
    let result = catch createTypeface(key.toString(), resource.bytes.toSlice()) as loadError
    return loadError == null ? result : null
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
private func drawSubstitutedRun(painter: *Painter, item: const *Item, resource: #null const *FontResource, font: *Font)
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
        let text  = resource!.codeText(code)
        var group: SubstitutedGroup
        group.first   = shaped.glyphs.count
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
    transform.multiply(item.transform)
    painter.setTransform(transform)
    painter.drawShapedRun(0, baselineOffset(item, font), &shaped, font, Brush.createSolid(item.fillColor))
    painter.setTransform(item.transform)
}

// Draws one text item, preferring the embedded program and falling back to a matching face.
private func drawTextItem(painter: *Painter, cache: *FontCache, page: const *Page, item: const *Item, options: RenderOptions) fail
{
    let fontSize = cast(u32) Math.max(1, Math.round(item.fontSize))
    let resource = item.fontIndex < page.fonts.count ? &page.fonts[item.fontIndex] : null

    if resource
    {
        let embedded = embeddedTypeface(resource!)
        if embedded
        {
            let font = cache.createFont(embedded!, fontSize)
            if drawEmbeddedRun(painter, item, resource!, font) do
                return
        }
    }

    let substitute = try substituteTypeface(options, resource)
    drawSubstitutedRun(painter, item, resource, cache.createFont(substitute, fontSize))
}

private func pathPen(item: const *Item, scale: f32)->Pen
{
    let strokeWidth   = item.strokeWidth ? item.strokeWidth : 1 / scale
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

internal func renderPage(page: const *Page, options: RenderOptions)->Image fail
{
    if options.scale <= 0 or !Math.isFinite(options.scale) do
        fail Errors.BadParameterError{}
    if options.maxDimension <= 0 or !options.maxPixels do
        fail Errors.BadParameterError{}

    let scaledWidth  = Math.ceil(page.width * options.scale)
    let scaledHeight = Math.ceil(page.height * options.scale)
    if !Math.isFinite(scaledWidth) or !Math.isFinite(scaledHeight) or scaledWidth > cast(f32) options.maxDimension or scaledHeight > cast(f32) options.maxDimension do
        fail Errors.UnsupportedFormatError{"rendered PDF page exceeds the configured dimension limit"}
    let width  = cast(s32) Math.max(1, scaledWidth)
    let height = cast(s32) Math.max(1, scaledHeight)
    if cast(u64) width * cast(u64) height > options.maxPixels do
        fail Errors.UnsupportedFormatError{"rendered PDF page exceeds the configured pixel limit"}

    var cpu:      RenderCpu
    let renderer: IRenderer = &cpu
    var context             = try renderer.createContext(null, width, height)
    defer renderer.deleteContext(&context)

    renderer.begin(context)
    renderer.init()
    var target = renderer.createRenderTarget(width, height)
    var textures: Array'Texture
    textures.reserve(page.items.count)
    for item in page.items
    {
        if item.kind == .Image do
            textures.add(renderer.addImage(item.image))
    }

    renderer.end()

    var painter = Painter.create(renderer)
    painter.setContentScale(options.scale)
    painter.begin()
    painter.bindRenderTarget(&target, true)
    painter.setColorMaskFull()
    painter.clear(options.background)
    painter.setColorMaskColor()

    var textureIndex = 0'u64
    for item in page.items
    {
        painter.setTransform(item.transform)

        // The clip is stated in page coordinates, so it must not pick up the item's own
        // transform on the way to the painter.
        if item.hasClip do
            painter.pushClippingSurfaceRect(item.clip)
        defer if item.hasClip do
            painter.popClippingRect()

        switch item.kind
        {
        case .Text:
            if item.text.isEmpty() and item.textCodes.isEmpty() do
                continue
            try drawTextItem(&painter, renderer.fontCache(), page, item, options)

        case .Path:
            var paths = item.path

            // A page states its fill rule over the winding count, so the fill has to be
            // named rather than left to the winding direction of whatever the writer emitted.
            if item.hasFill do
                painter.fillPath(&paths, item.fillColor, item.evenOddFill ? PathFillRule.EvenOdd : PathFillRule.NonZero)
            if item.hasStroke do
                painter.drawPath(&paths, pathPen(item, options.scale), .Separate)

        case .Image:
            painter.drawTexture(0, 0, 1, 1, textures[textureIndex])
            textureIndex += 1
        }
    }

    painter.resetTransform()

    // Antialiased drawing resolves its coverage through the target alpha channel and therefore
    // replaces the alpha written by the initial clear. Restore an opaque page ground after the
    // content, just as ImageCanvas does, while preserving coverage for transparent renders.
    if options.background.a == 255
    {
        painter.setBlendingMode(.Copy)
        painter.setColorMaskAlpha()
        painter.fillRect({0, 0, page.width, page.height}, options.background)
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
