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
        fallbackFontFile: string = ""                             // Optional TrueType font used when a PDF font cannot be decoded.
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

    let key    = Format.toString("pdf-font-%{X08}", Hash.Crc32.compute(resource.bytes.toSlice()))
    let result = catch createTypeface(key.toString(), resource.bytes.toSlice()) as loadError
    return loadError == null ? result! : fallback
}

private func scaledTransform(transform: Transform2, scale: f32)->Transform2
{
    var result = transform
    result.multiply(Transform2.createScale(scale, scale, 0, 0))
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
    painter.begin()
    painter.bindRenderTarget(&target, true)
    painter.setColorMaskFull()
    painter.clear(options.background)
    painter.setColorMaskColor()

    var fallback: #null *TypeFace
    var textureIndex = 0'u64
    for item in page.items
    {
        painter.setTransform(scaledTransform(item.transform, options.scale))
        switch item.kind
        {
        case .Text:
            if item.text.isEmpty() do
                continue
            if !fallback do
                fallback = try fallbackTypeface(options)
            let typeface = itemTypeface(page, item, fallback!)
            let fontSize = cast(u32) Math.max(1, Math.round(item.fontSize))
            let font     = renderer.fontCache().createFont(typeface, fontSize)
            painter.drawString(0, 0, item.text.toString(), font, item.fillColor)

        case .Path:
            var paths = item.path
            if item.hasFill do
                painter.fillPath(&paths, item.fillColor)
            if item.hasStroke do
                painter.drawPath(&paths, Pen.createSolid(item.strokeColor, item.strokeWidth), .Separate)

        case .Image:
            painter.drawTexture(0, 0, 1, 1, textures[textureIndex])
            textureIndex += 1
        }
    }

    painter.resetTransform()
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
