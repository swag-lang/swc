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

private func fallbackTypeface(options: RenderOptions)->*TypeFace fail
{
    if @countof(options.fallbackFontFile) do
        return try TypeFace.load(options.fallbackFontFile)

    let names: [6] string = ["arial.ttf", "segoeui.ttf", "calibri.ttf", "DejaVuSans.ttf", "LiberationSans-Regular.ttf", "Arial.ttf"]
    for name in names
    {
        let result = catch loadTypeface(name) as loadError
        if loadError == null do
            return result!
    }

    fail Errors.UnsupportedFormatError{"no TrueType fallback font is available"}
}

private func itemTypeface(page: const *Page, item: const *Item, fallback: *TypeFace)->*TypeFace
{
    if item.fontIndex >= page.fonts.count do
        return fallback

    let resource = &page.fonts[item.fontIndex]
    if !resource.bytes.count do
        return fallback

    // A subset program is keyed by the PDF's character codes or CIDs, not by the Unicode
    // extracted through /ToUnicode. Feeding that Unicode back through the subset's incidental
    // cmap can select unrelated glyphs even when every lookup succeeds. Until the item model
    // carries original glyph identifiers, render extracted subset text with the fallback face.
    if resource.baseName.length > 7 and resource.baseName.toString()[6] == '+' do
        return fallback

    let key    = Format.toString("pdf-font-%{X08}", Hash.Crc32.compute(resource.bytes.toSlice()))
    let result = catch createTypeface(key.toString(), resource.bytes.toSlice()) as loadError
    return loadError == null ? result! : fallback
}

private func fontMapsText(font: *Font, text: string)->bool
{
    var result = true
    Utf8.visitRunes(text)
    {
        // Missing whitespace has no visible outline; its PDF advance still separates words.
        if c > ' ' and !font.glyphIndex(c) do
            result = false
    }

    return result
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

    var fallback: #null *TypeFace
    var textureIndex = 0'u64
    for item in page.items
    {
        painter.setTransform(item.transform)
        switch item.kind
        {
        case .Text:
            if item.text.isEmpty() do
                continue
            if !fallback do
                fallback = try fallbackTypeface(options)
            let fontSize = cast(u32) Math.max(1, Math.round(item.fontSize))
            var font     = renderer.fontCache().createFont(itemTypeface(page, item, fallback!), fontSize)
            if !fontMapsText(font, item.text.toString()) do
                font = renderer.fontCache().createFont(fallback!, fontSize)
            painter.drawString(0, 0, item.text.toString(), font, item.fillColor)

        case .Path:
            var paths = item.path
            if item.hasFill do
                painter.fillPath(&paths, item.fillColor)
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
