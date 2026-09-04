using Core, Pixel

const W                 = 1260
const H                 = 860
const GalleryCols       = 2
const GalleryRows       = 2
const CardsPerPage      = GalleryCols * GalleryRows
const PageCount         = 8
const TestFramesPerPage = 10
const CardHeaderHeight  = 78.0
const MaxSourceSide     = 192.0
const AlphaFadeStep     = 16

const PageBmp  = 0
const PageTga  = 1
const PageJpg  = 2
const PagePng  = 3
const PageGif  = 4
const PageTiff = 5
const PageIco  = 6
const PageWebp = 7

struct SceneLayout
{
    scale: f32
    rect:  Math.Rectangle
}

struct DecoderCard
{
    title:   String
    details: String
    texture: Texture
}

var g_Window:   Env.Window
var g_Renderer: Pixel.RenderOgl
var g_Render:   Pixel.IRenderer
var g_Painter:  Pixel.Painter
var g_RC:       Pixel.RenderContext
var g_Keyboard: Input.Keyboard

var g_TypeFace:  #null *Pixel.TypeFace
var g_TitleFont: #null *Pixel.Font
var g_LabelFont: #null *Pixel.Font
var g_HelpFont:  #null *Pixel.Font

var g_Page:      s32
var g_TestFrame: s32
var g_Cards:     [PageCount][CardsPerPage] DecoderCard

func dataPath(fileName: string, loc = #callerlocation)->String
{
    let srcPath = Path.directoryName(loc.fileName) orelse ""
    return Path.combine(Path.combine(srcPath, "data"), fileName)
}

func loadFonts() fail
{
    g_TypeFace  = TypeFace.load("segoeui.ttf")
    g_TitleFont = g_Renderer.fonts.createFont(g_TypeFace!, 34)
    g_LabelFont = g_Renderer.fonts.createFont(g_TypeFace!, 18)
    g_HelpFont  = g_Renderer.fonts.createFont(g_TypeFace!, 14)
}

func normalizeSource(image: Image)->Image
{
    let maxSide = cast(f32) Math.max(image.width, image.height)
    if maxSide <= MaxSourceSide do
        return Image.create(image.width, image.height, image.pixelFormat, image.pixels.toSlice())

    let scale     = MaxSourceSide / maxSide
    let newWidth  = Math.max(cast(s32) Math.round(cast(f32) image.width * scale), 1)
    let newHeight = Math.max(cast(s32) Math.round(cast(f32) image.height * scale), 1)
    return image.resized(newWidth, newHeight, .Quadratic)
}

func loadSource(fileName: string)->Image fail
{
    let image = Image.load(dataPath(fileName))
    return normalizeSource(image)
}

func sourceVariant(source: Image, pixelFormat: PixelFormat, withAlphaBorder = false)->Image
{
    let converted = source.convertedTo(pixelFormat)
    var result    = Image.create(converted.width, converted.height, converted.pixelFormat, converted.pixels.toSlice())
    if !withAlphaBorder do
        return result

    Debug.assert(pixelFormat.hasAlpha())
    var pixel = result.pixels.buffer!
    for y in result.height
    {
        for x in result.width
        {
            let edgeDistance = Math.min(Math.min(x, result.width - x - 1), Math.min(y, result.height - y - 1))
            let borderAlpha  = cast(u8) Math.min(edgeDistance * AlphaFadeStep, 255)
            pixel[3] = cast(u8) ((cast(u16) pixel[3] * borderAlpha + 127) / 255)
            pixel    += 4
        }
    }

    return result
}

func paletteVariant(source: Image, withAlpha: bool)->Image
{
    var result      = sourceVariant(source, withAlpha ? .RGBA8 : .RGB8)
    var pixel       = result.pixels.buffer!
    let borderWidth = Math.max(Math.min(result.width, result.height) / 12, 1)
    for y in result.height
    {
        for x in result.width
        {
            pixel[0] = (pixel[0] >> 6) * 85
            pixel[1] = (pixel[1] >> 6) * 85
            pixel[2] = (pixel[2] >> 6) * 85
            if withAlpha
            {
                let edgeDistance = Math.min(Math.min(x, result.width - x - 1), Math.min(y, result.height - y - 1))
                if edgeDistance < borderWidth do
                    pixel[3] = 0
            }

            pixel += result.bytesPerPixel
        }
    }

    return result
}

func nonNullBytes(bytes: #null [..] u8)->const [..] u8
{
    Debug.assert(bytes != null)
    return Swag.makeSlice(cast([*] u8) bytes.buffer!, bytes.count)
}

func setCard(card: *DecoderCard, title, encoding: string, image: Image, encodedSize: u64)
{
    card.title   = title
    card.details = Format.toString("% | % x % | % bytes", encoding, image.width, image.height, encodedSize)
    card.texture = g_Render.addImage(image)
}

func encodeCard(card: *DecoderCard, fileName, title, encoding: string, source: Image, options: #null any = null) fail
{
    var encoded = source.encode(fileName, options)
    encoded.makeLinear()

    let bytes   = nonNullBytes(encoded.toSlice())
    let decoded = Image.decode(fileName, bytes)
    setCard(card, title, encoding, decoded, bytes.count)
}

func buildPages() fail
{
    buildBmpPage()
    buildTgaPage()
    buildJpgPage()
    buildPngPage()
    buildGifPage()
    buildTiffPage()
    buildIcoPage()
    buildWebpPage()
}

func pageTitle(page: s32)->string
{
    switch page
    {
    case PageBmp:  return "BMP encoder and decoder"
    case PageTga:  return "TGA encoder and decoder"
    case PageJpg:  return "JPEG encoder and decoder"
    case PagePng:  return "PNG encoder and decoder"
    case PageGif:  return "GIF encoder and decoder"
    case PageTiff: return "TIFF encoder and decoder"
    case PageIco:  return "ICO encoder and decoder"
    case PageWebp: return "WebP encoder and decoder"
    default:       unreachable
    }

    return ""
}

func pageDescription(page: s32)->string
{
    switch page
    {
    case PageBmp:  return "The bundled BMP is decoded, converted to four pixel layouts, encoded by Swag, then decoded again."
    case PageTga:  return "The bundled TGA is regenerated as raw and RLE-compressed true-color images from RGB and BGR layouts."
    case PageJpg:  return "The bundled JPEG is regenerated at four quality levels and each encoded buffer is decoded for display."
    case PagePng:  return "The bundled PNG is regenerated with filtered, Adam7-interlaced, stored and alpha-bearing encodings."
    case PageGif:  return "The bundled GIF is regenerated with exact, transparent and quantized palettes before LZW decoding."
    case PageTiff: return "The bundled TIFF is regenerated as uncompressed, PackBits and LZW-compressed RGB and RGBA data."
    case PageIco:  return "The bundled icon is regenerated as four 32-bit DIB entries with different sizes and alpha layouts."
    case PageWebp: return "The bundled WebP is regenerated as lossless VP8L data from RGB, BGR and alpha-bearing layouts."
    default:       unreachable
    }

    return ""
}

func drawWrappedText(painter: *Pixel.Painter, rect: Math.Rectangle, text: string, font: *Pixel.Font, color: Color)
{
    var richText: RichString = text
    var format:   RichStringFormat
    format.font.regular = font
    format.palette[0]   = color
    format.lineGap      = 0
    format.flags        = .WordWrap | .Clip
    painter.drawRichString(rect, &richText, format)
}

func computeSceneLayout(width, height: s32)->SceneLayout
{
    let surfaceWidth  = Math.max(width, 1)
    let surfaceHeight = Math.max(height, 1)
    let scaleX        = cast(f32) surfaceWidth / cast(f32) W
    let scaleY        = cast(f32) surfaceHeight / cast(f32) H

    with var result: retval
    {
        .scale  = Math.min(scaleX, scaleY)
        .rect   = {0, 0, cast(f32) W * .scale, cast(f32) H * .scale}
        .rect.x = Math.round((cast(f32) surfaceWidth - .rect.width) * 0.5)
        .rect.y = Math.round((cast(f32) surfaceHeight - .rect.height) * 0.5)
    }

    return result
}

func getCardRect(index: s32)->Math.Rectangle
{
    let gap         = 18.0
    let top         = 118.0
    let bottomInset = 42.0
    let cardWidth   = (W - 56.0 - (GalleryCols - 1) * gap) / cast(f32) GalleryCols
    let cardHeight  = (H - top - bottomInset - (GalleryRows - 1) * gap) / cast(f32) GalleryRows
    let col         = index % GalleryCols
    let row         = index / GalleryCols
    return {28 + col * (cardWidth + gap), top + row * (cardHeight + gap), cardWidth, cardHeight}
}

func fitTextureRect(bounds: Math.Rectangle, texture: Texture)->Math.Rectangle
{
    let scale  = Math.min(bounds.width / cast(f32) texture.width, bounds.height / cast(f32) texture.height)
    let width  = cast(f32) texture.width * scale
    let height = cast(f32) texture.height * scale
    return {bounds.horzCenter() - width * 0.5, bounds.vertCenter() - height * 0.5, width, height}
}

func drawCard(painter: *Pixel.Painter, rect: Math.Rectangle, card: DecoderCard)
{
    let headerRect  = Math.Rectangle{rect.x, rect.y, rect.width, CardHeaderHeight}
    let detailsRect = Math.Rectangle{rect.x + 14, rect.y + 38, rect.width - 28, CardHeaderHeight - 42}
    let previewRect = Math.Rectangle{rect.x + 14, rect.y + CardHeaderHeight + 14, rect.width - 28, rect.height - CardHeaderHeight - 28}

    painter.fillRoundRect(rect, 18, 18, Argb.White)
    painter.drawRoundRect(rect, 18, 18, Color.fromArgb(72, Argb.SlateGray), 2)
    painter.fillRoundRect(headerRect, 18, 18, Color.fromArgb(22, Argb.MidnightBlue))
    painter.fillRoundRect(previewRect, 14, 14, Color.fromArgb(255, 239, 242, 247))

    painter.drawString(rect.x + 14, rect.y + 11, card.title, g_LabelFont!, Argb.DarkSlateBlue)
    drawWrappedText(painter, detailsRect, card.details, g_HelpFont!, Argb.DimGray)

    painter.pushClippingRect(previewRect)
    painter.drawTexture(fitTextureRect(previewRect, card.texture), card.texture)
    painter.popClippingRect()
}

func drawScene(painter: *Pixel.Painter)
{
    painter.setColorMaskFull()
    painter.clear(Color.fromArgb(255, 245, 246, 249))
    painter.setColorMaskColor()
    painter.setParams(.Antialiased)
    painter.drawString(28, 22, pageTitle(g_Page), g_TitleFont!, Argb.MidnightBlue)
    drawWrappedText(painter, {30, 64, W - 60, 42}, pageDescription(g_Page), g_HelpFont!, Argb.DimGray)

    for i in CardsPerPage do
        drawCard(painter, getCardRect(i), g_Cards[g_Page][i])

    let footer = Format.toString("F1 : next codec (%/%). BMP, TGA, JPEG, PNG, GIF, TIFF, ICO and WebP.", g_Page + 1, PageCount)
    painter.drawString(28, H - 22, footer, g_HelpFont!, Argb.DimGray)
}

func display()
{
    // The render context is physical device pixels; the fit is computed in logical
    // units, and the painter maps them to device pixels on scaled displays.
    let scale  = g_Painter.contentScale()
    let layout = computeSceneLayout(cast(s32) Math.round(g_RC.width / scale), cast(s32) Math.round(g_RC.height / scale))

    g_Render.begin(g_RC)
    g_Painter.begin()
    g_Painter.pushClippingSurfaceRect(layout.rect)
    g_Painter.pushTransform()
    g_Painter.scaleTransform(layout.scale)
    g_Painter.translateTransform(layout.rect.x, layout.rect.y)
    drawScene(&g_Painter)
    g_Painter.popTransform()
    g_Painter.popClippingRect()
    g_Painter.end()
    g_Painter.render()
    g_Render.end()
}

func onResize(window: *Env.Window, width, height: s32)
{
    g_RC.width  = width
    g_RC.height = height
    g_Painter.setContentScale(window.dpiScale())
}

func nextPage()
{
    g_Page = (g_Page + 1) % PageCount
}

func updateShortcuts()
{
    g_Keyboard.update()
    if g_Keyboard.isKeyJustPressed(Input.Key.F1) do
        nextPage()
}

func updateTestMode()
{
    if !Env.isSmokeRun() do
        return

    g_TestFrame += 1
    if g_TestFrame < TestFramesPerPage do
        return

    g_TestFrame = 0
    if g_Page + 1 >= PageCount do
        Env.exit(0)

    nextPage()
}

#main
{
    g_Window = try Env.createWindow({identifier: "pixel7", title: "Pixel image codec showcase", width: W, height: H, flags: .Minimizable})
    try g_Window.setClientSize(W, H)
    g_Render  = &g_Renderer
    g_Painter = Pixel.Painter.create(g_Render)
    g_RC      = try g_Render.createContext(g_Window.nativeRenderHandle(), W, H)
    defer g_Render.deleteContext(&g_RC)
    g_Render.setCurrentContext(g_RC)
    g_Render.init()

    try Jobs.initialize()
    try loadFonts()
    try buildPages()

    g_Window.callbacks.onResize = &onResize
    try g_Window.show()

    var loop: Env.WindowLoop
    if Env.isSmokeRun() do
        loop.smokeFrames = cast(u32) PageCount * cast(u32) TestFramesPerPage
    while loop.next()
    {
        updateShortcuts()
        display()
        updateTestMode()
    }
}
