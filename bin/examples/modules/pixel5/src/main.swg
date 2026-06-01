using Core, Pixel, Win32

const W = 1260
const H = 860

const GalleryCols  = 4
const GalleryRows  = 2
const CardsPerPage = GalleryCols * GalleryRows
const MaxPages     = 4

const FixedWindowStyle = WS_OVERLAPPED | WS_CAPTION | WS_SYSMENU | WS_MINIMIZEBOX | WS_CLIPSIBLINGS | WS_CLIPCHILDREN

struct SceneLayout
{
    scale:      f32
    rect:       Math.Rectangle
}

struct CardOptions
{
    angle:           Math.Angle = 0.0'deg
    scale:           f32 = 1.0
    interpolation:   InterpolationMode = .Linear
    sourceRect:      Math.Rectangle
    offsetX:         f32 = 0
    offsetY:         f32 = 0
}

struct TextureCard
{
    title:           string
    subtitle:        string
    texture:         Texture
    options:         CardOptions
}

var g_Window:       Env.Window
var g_Renderer:     Pixel.RenderOgl
var g_Painter:      Pixel.Painter
var g_RC:           Pixel.RenderingContext
var g_Keyboard:     Input.Keyboard

var g_FontBytes:    Array'u8
var g_TypeFace:     *Pixel.TypeFace
var g_TitleFont:    *Pixel.Font
var g_SubTitleFont: *Pixel.Font
var g_LabelFont:    *Pixel.Font
var g_HelpFont:     *Pixel.Font

var g_Page:         s32
var g_TestFrame:    s32

var g_SourceTexture: Texture

var g_TonalCards:     [CardsPerPage] TextureCard
var g_KernelCards:    [CardsPerPage] TextureCard
var g_TransformCards: [CardsPerPage] TextureCard
var g_PainterCards:   [CardsPerPage] TextureCard

func dataPath(fileName: string, loc = #callerlocation)->String
{
    let srcPath = Path.getDirectoryName(loc.fileName) orelse ""
    return Path.combine(Path.combine(srcPath, "data"), fileName)
}

func loadFonts() throw
{
    let path = dataPath("segoeui.ttf")
    g_FontBytes    = File.readAllBytes(path)
    g_TypeFace     = TypeFace.create(path, g_FontBytes.toSlice())
    g_TitleFont    = Font.create(g_TypeFace, 34)
    g_SubTitleFont = Font.create(g_TypeFace, 18)
    g_LabelFont    = Font.create(g_TypeFace, 15)
    g_HelpFont     = Font.create(g_TypeFace, 13)
}

func cloneImage(image: const &Image)->Image
{
    return Image.create(image.width, image.height, image.pf, image.pixels.toSlice())
}

func normalizeShowcaseImage(image: const &Image)->Image
{
    var result = cloneImage(image)
    let maxSide = cast(f32) Math.max(result.width, result.height)
    if maxSide > 760.0
    {
        let scale     = 760.0 / maxSide
        let newWidth  = Math.max(cast(s32) Math.round(cast(f32) result.width * scale), 1)
        let newHeight = Math.max(cast(s32) Math.round(cast(f32) result.height * scale), 1)
        result.resize(newWidth, newHeight, .Quadratic)
    }

    return result
}

func setTextureCard(card: *TextureCard, title, subtitle: string, texture: Texture, options: CardOptions = {})
{
    card.title    = title
    card.subtitle = subtitle
    card.texture  = texture
    card.options  = options
}

func setImageCard(card: *TextureCard, title, subtitle: string, image: const &Image, options: CardOptions = {})
{
    setTextureCard(card, title, subtitle, g_Renderer.addImage(image), options)
}

func loadShowcase() throw
{
    let loaded = Image.load(dataPath("joconde.jpg"))
    let source = normalizeShowcaseImage(loaded)

    g_SourceTexture = g_Renderer.addImage(source)

    buildTonalCards(source)
    buildKernelCards(source)
    buildTransformCards(source)
    buildPainterCards(source)
}

func insetRect(rect: Math.Rectangle, left, top, right, bottom: f32)->Math.Rectangle
{
    var result = rect
    result.x += left
    result.y += top
    result.width -= left + right
    result.height -= top + bottom
    return result
}

func nextPage()
{
    g_Page = (g_Page + 1) % MaxPages
}

func drawPageHeader(painter: *Pixel.Painter, title, subtitle: string)
{
    painter.drawString(28, 22, title, g_TitleFont, Argb.MidnightBlue)
    painter.drawString(30, 64, subtitle, g_SubTitleFont, Argb.DimGray)
}

func drawFooter(painter: *Pixel.Painter)
{
    let pageText = Format.toString("F1 : next page (%/%). Pages : tonal filters, kernels and grading, image transforms, painter transforms.", g_Page + 1, MaxPages)
    painter.drawString(28, H - 24, pageText, g_HelpFont, Argb.DimGray)
}

func computeSceneLayout(width, height: s32)->SceneLayout
{
    let surfaceWidth  = Math.max(width, 1)
    let surfaceHeight = Math.max(height, 1)
    let scaleX        = cast(f32) surfaceWidth / cast(f32) W
    let scaleY        = cast(f32) surfaceHeight / cast(f32) H

    with var result: retval = undefined
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
    let top         = 112.0
    let bottomInset = 42.0
    let cardWidth   = (W - 56.0 - (GalleryCols - 1) * gap) / cast(f32) GalleryCols
    let cardHeight  = (H - top - bottomInset - (GalleryRows - 1) * gap) / cast(f32) GalleryRows
    let col         = index % GalleryCols
    let row         = index / GalleryCols

    return {28 + col * (cardWidth + gap), top + row * (cardHeight + gap), cardWidth, cardHeight}
}

func getCardSourceRect(card: const &TextureCard)->Math.Rectangle
{
    if card.options.sourceRect.isEmpty() do
        return {0, 0, cast(f32) card.texture.width, cast(f32) card.texture.height}
    return card.options.sourceRect
}

func fitTextureRect(bounds: Math.Rectangle, sourceWidth, sourceHeight: f32, angle: Math.Angle)->Math.Rectangle
{
    let absCos        = Math.abs(Math.cos(angle.rad))
    let absSin        = Math.abs(Math.sin(angle.rad))
    let rotatedWidth  = sourceWidth * absCos + sourceHeight * absSin
    let rotatedHeight = sourceWidth * absSin + sourceHeight * absCos
    let fitScale      = Math.min(bounds.width / rotatedWidth, bounds.height / rotatedHeight)
    let width         = sourceWidth * fitScale
    let height        = sourceHeight * fitScale
    let x             = bounds.x + (bounds.width - width) * 0.5
    let y             = bounds.y + (bounds.height - height) * 0.5
    return {x, y, width, height}
}

func drawCardTexture(painter: *Pixel.Painter, rect: Math.Rectangle, card: const &TextureCard)
{
    if !card.texture.isValid() do
        return

    let srcRect = getCardSourceRect(card)
    var textureRect = fitTextureRect(rect, srcRect.width, srcRect.height, card.options.angle)
    let centerX = textureRect.horzCenter()
    let centerY = textureRect.vertCenter()
    textureRect.width *= card.options.scale
    textureRect.height *= card.options.scale
    textureRect.x = centerX - textureRect.width * 0.5 + card.options.offsetX
    textureRect.y = centerY - textureRect.height * 0.5 + card.options.offsetY

    painter.pushClippingRect(rect)
    painter.setInterpolationMode(card.options.interpolation)
    if !Math.isZeroEpsilon(card.options.angle.rad)
    {
        painter.pushTransform()
        painter.rotateTransform(card.options.angle, textureRect.horzCenter(), textureRect.vertCenter())
        painter.drawTexture(textureRect, srcRect, card.texture)
        painter.popTransform()
    }
    else
    {
        painter.drawTexture(textureRect, srcRect, card.texture)
    }

    painter.setInterpolationMode(.Linear)
    painter.popClippingRect()
}

func drawCard(painter: *Pixel.Painter, rect: Math.Rectangle, card: const &TextureCard)
{
    let titleBarRect = {rect.x, rect.y, rect.width, 54}
    let previewRect  = insetRect(rect, 14, 68, 14, 14)

    painter.fillRoundRect(rect, 18, 18, Argb.White)
    painter.drawRoundRect(rect, 18, 18, Color.fromArgb(82, Argb.SlateGray), 2)
    painter.fillRoundRect(titleBarRect, 18, 18, Color.fromArgb(18, Argb.MidnightBlue))
    painter.fillRoundRect(previewRect, 16, 16, Color.fromArgb(255, 246, 248, 250))
    painter.drawRoundRect(previewRect, 16, 16, Color.fromArgb(36, Argb.SlateGray), 1)

    painter.drawString(rect.x + 14, rect.y + 12, card.title, g_LabelFont, Argb.DarkSlateBlue)
    painter.drawString(rect.x + 14, rect.y + 34, card.subtitle, g_HelpFont, Argb.DimGray)
    drawCardTexture(painter, previewRect, card)
}

func drawScene(painter: *Pixel.Painter)
{
    painter.clear(Color.fromArgb(255, 245, 246, 249))
    painter.setParams(.Antialiased)

    switch g_Page
    {
    case 0:
        drawTonalPage(painter)
    case 1:
        drawKernelPage(painter)
    case 2:
        drawTransformPage(painter)
    case 3:
        drawPainterPage(painter)
    default:
        unreachable
    }

    drawFooter(painter)
}

func display()
{
    let layout = computeSceneLayout(g_RC.width, g_RC.height)

    g_Renderer.begin(g_RC)
    g_Painter.begin()
    g_Painter.pushClippingSurfaceRect(layout.rect)
    g_Painter.pushTransform()
    g_Painter.scaleTransform(layout.scale)
    g_Painter.translateTransform(layout.rect.x, layout.rect.y)
    drawScene(&g_Painter)
    g_Painter.popTransform()
    g_Painter.popClippingRect()
    g_Painter.end()
    g_Renderer.draw(&g_Painter)
    g_Renderer.end()
}

func onResize(_window: *Env.Window, width, height: s32)
{
    g_RC.width  = width
    g_RC.height = height
}

func updateShortcuts()
{
    g_Keyboard.update()
    if g_Keyboard.isKeyJustPressed(Input.Key.F1) do
        nextPage()

    if Env.hasArg("swag.test")
    {
        g_TestFrame += 1
        if g_TestFrame % 30 == 0 do
            nextPage()
    }
}

#main
{
    try Env.createWindow(&g_Window, {className: "PIXEL5_CLASS_NAME", title: "Pixel filters and transforms showcase", width: W, height: H, style: FixedWindowStyle})
    try g_Window.setClientSize(W, H)
    g_RC = try g_Renderer.native.createContext(&g_Window, W, H)
    g_Renderer.setCurrentContext(g_RC)
    g_Renderer.init()

    try loadFonts()
    try loadShowcase()

    g_Window.callbacks.onResize = &onResize
    try g_Window.show()

    var loop: Env.WindowLoop
    while loop.next()
    {
        updateShortcuts()
        display()
    }

    g_Renderer.native.dropContext(g_RC)
}
