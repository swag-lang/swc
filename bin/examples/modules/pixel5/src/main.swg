using Core, Pixel

const NavigationWidth = 112.0
const NavigationGap   = 8.0

const W = 1260
const H = 860

const GalleryCols      = 4
const GalleryRows      = 2
const CardsPerPage     = GalleryCols * GalleryRows
const MaxPages         = 4
const CardHeaderHeight = 68.0

struct SceneLayout
{
    scale: f32
    rect:  Math.Rectangle
}

struct CardOptions
{
    angle:         Math.Angle        = 0.0'deg
    scale:         f32               = 1.0
    interpolation: InterpolationMode = .Linear
    sourceRect:    Math.Rectangle
    offsetX:       f32               = 0
    offsetY:       f32               = 0
}

struct TextureCard
{
    late title:    string
    late subtitle: string
    texture:       Texture
    options:       CardOptions
}

var g_Window:      Env.Window
var g_Renderer:    Pixel.RenderOgl
late var g_Render: Pixel.IRenderer
var g_Painter:     Pixel.Painter
var g_RC:          Pixel.RenderContext
var g_Keyboard:    Input.Keyboard

late var g_TitleFont:    *Pixel.Font
late var g_SubTitleFont: *Pixel.Font
late var g_LabelFont:    *Pixel.Font
late var g_HelpFont:     *Pixel.Font

var g_NeedsPaint = true
var g_Page: s32

var g_SourceTexture: Texture

var g_TonalCards:     [CardsPerPage] TextureCard
var g_KernelCards:    [CardsPerPage] TextureCard
var g_TransformCards: [CardsPerPage] TextureCard
var g_PainterCards:   [CardsPerPage] TextureCard

func loadFonts() fail
{
    let typeface = try TypeFace.create("segoeui.ttf", #include("../../../assets/segoeui.ttf"))
    g_TitleFont    = g_Renderer.fonts.createFont(typeface, 34)
    g_SubTitleFont = g_Renderer.fonts.createFont(typeface, 18)
    g_LabelFont    = g_Renderer.fonts.createFont(typeface, 15)
    g_HelpFont     = g_Renderer.fonts.createFont(typeface, 13)
}

func cloneImage(image: Image)->Image => Image.create(image.width, image.height, image.pixelFormat, image.pixels.toSlice())

func normalizeShowcaseImage(image: Image)->Image
{
    var result  = cloneImage(image)
    let maxSide = cast(f32, Math.max(result.width, result.height))
    if maxSide > 760.0
    {
        let scale     = 760.0 / maxSide
        let newWidth  = Math.max(cast(s32, Math.round(cast(f32, result.width) * scale)), 1)
        let newHeight = Math.max(cast(s32, Math.round(cast(f32, result.height) * scale)), 1)
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

func setImageCard(card: *TextureCard, title, subtitle: string, image: Image, options: CardOptions = {})
{
    setTextureCard(card, title, subtitle, g_Render.addImage(image), options)
}

func loadShowcase() fail
{
    let loaded = try Image.decode(".jpg", #include("../../../assets/balloon.jpg"))
    let source = normalizeShowcaseImage(loaded)

    g_SourceTexture = g_Render.addImage(source)

    buildTonalCards(source)
    buildKernelCards(source)
    buildTransformCards(source)
    buildPainterCards(source)
}

func insetRect(rect: Math.Rectangle, left, top, right, bottom: f32)->Math.Rectangle
{
    var result = rect
    result.x      += left
    result.y      += top
    result.width  -= left + right
    result.height -= top + bottom
    return result
}

func changePage(step: s32)
{
    g_Page       = (g_Page + step + MaxPages) % MaxPages
    g_NeedsPaint = true
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

func drawPageHeader(painter: *Pixel.Painter, title, subtitle: string)
{
    painter.drawString(28, 22, title, g_TitleFont, Argb.MidnightBlue)
    drawWrappedText(painter, {30, 62, W - 60, 36}, subtitle, g_SubTitleFont, Argb.DimGray)
}

func navigationRect(index: s32)->Math.Rectangle
{
    let right = W - 28.0
    let width = NavigationWidth * 2 + NavigationGap
    return {right - width + index * (NavigationWidth + NavigationGap), H - 36, NavigationWidth, 28}
}

func drawFooter(painter: *Pixel.Painter)
{
    painter.drawString(28, H - 30, Format.toString("Page % of %", g_Page + 1, MaxPages), g_HelpFont, Argb.DimGray)
    const Labels = ["Previous · F2", "Next · F1"]
    for label, index in Labels
    {
        let rect = navigationRect(cast(s32, index))
        painter.fillRoundRect(rect, 6, 6, Argb.White)
        painter.drawRoundRect(rect, 6, 6, Color.fromArgb(72, Argb.SlateGray), 1)
        painter.drawStringCenter(rect.horzCenter(), rect.vertCenter(), label, g_HelpFont, Argb.DarkSlateGray)
    }
}

func computeSceneLayout(width, height: s32)->SceneLayout
{
    let surfaceWidth  = Math.max(width, 1)
    let surfaceHeight = Math.max(height, 1)
    let scaleX        = cast(f32, surfaceWidth) / cast(f32, W)
    let scaleY        = cast(f32, surfaceHeight) / cast(f32, H)

    with var result: #returntype
    {
        .scale  = Math.min(scaleX, scaleY)
        .rect   = Math.Rectangle{0, 0, cast(f32, W) * .scale, cast(f32, H) * .scale}
        .rect.x = Math.round((cast(f32, surfaceWidth) - .rect.width) * 0.5)
        .rect.y = Math.round((cast(f32, surfaceHeight) - .rect.height) * 0.5)
    }

    return result
}

func getCardRect(index: s32)->Math.Rectangle
{
    let gap         = 18.0
    let top         = 112.0
    let bottomInset = 42.0
    let cardWidth   = (W - 56.0 - (GalleryCols - 1) * gap) / cast(f32, GalleryCols)
    let cardHeight  = (H - top - bottomInset - (GalleryRows - 1) * gap) / cast(f32, GalleryRows)
    let col         = index % GalleryCols
    let row         = index / GalleryCols

    return Math.Rectangle{28 + col * (cardWidth + gap), top + row * (cardHeight + gap), cardWidth, cardHeight}
}

func fitTextureRect(bounds: Math.Rectangle, sourceWidth, sourceHeight: f32, angle: Math.Angle)->Math.Rectangle
{
    let absCos        = Math.abs(Math.cos(angle.radians))
    let absSin        = Math.abs(Math.sin(angle.radians))
    let rotatedWidth  = sourceWidth * absCos + sourceHeight * absSin
    let rotatedHeight = sourceWidth * absSin + sourceHeight * absCos
    let fitScale      = Math.min(bounds.width / rotatedWidth, bounds.height / rotatedHeight)
    let width         = sourceWidth * fitScale
    let height        = sourceHeight * fitScale
    let x             = bounds.x + (bounds.width - width) * 0.5
    let y             = bounds.y + (bounds.height - height) * 0.5
    return Math.Rectangle{x, y, width, height}
}

func drawCardTexture(painter: *Pixel.Painter, rect: Math.Rectangle, card: TextureCard)
{
    if not card.texture.isValid() do
        return

    let srcRect      = card.options.sourceRect
    let sourceWidth  = srcRect.isEmpty() ? cast(f32, card.texture.width) : srcRect.width
    let sourceHeight = srcRect.isEmpty() ? cast(f32, card.texture.height) : srcRect.height
    var textureRect  = fitTextureRect(rect, sourceWidth, sourceHeight, card.options.angle)
    let centerX      = textureRect.horzCenter()
    let centerY      = textureRect.vertCenter()
    textureRect.width  *= card.options.scale
    textureRect.height *= card.options.scale
    textureRect.x      = centerX - textureRect.width * 0.5 + card.options.offsetX
    textureRect.y      = centerY - textureRect.height * 0.5 + card.options.offsetY

    painter.pushClippingRect(rect)
    painter.setInterpolationMode(card.options.interpolation)
    if not Math.isZeroEpsilon(card.options.angle.radians)
    {
        painter.pushTransform()
        painter.rotateTransform(card.options.angle, textureRect.horzCenter(), textureRect.vertCenter())
        if srcRect.isEmpty() do
            painter.drawTexture(textureRect, card.texture)
        else do
            painter.drawTexture(textureRect, srcRect, card.texture)
        painter.popTransform()
    }
    else
    {
        if srcRect.isEmpty() do
            painter.drawTexture(textureRect, card.texture)
        else do
            painter.drawTexture(textureRect, srcRect, card.texture)
    }

    painter.setInterpolationMode(.Linear)
    painter.popClippingRect()
}

func drawCard(painter: *Pixel.Painter, rect: Math.Rectangle, card: TextureCard)
{
    let titleBarRect = Math.Rectangle{rect.x, rect.y, rect.width, CardHeaderHeight}
    let previewRect  = insetRect(rect, 14, CardHeaderHeight + 14, 14, 14)
    let subtitleRect = Math.Rectangle{rect.x + 14, rect.y + 30, rect.width - 28, CardHeaderHeight - 36}

    painter.fillRoundRect(rect, 18, 18, Argb.White)
    painter.drawRoundRect(rect, 18, 18, Color.fromArgb(82, Argb.SlateGray), 2)
    painter.fillRoundRect(titleBarRect, 18, 18, Color.fromArgb(18, Argb.MidnightBlue))
    painter.fillRoundRect(previewRect, 16, 16, Color.fromArgb(255, 246, 248, 250))
    painter.drawRoundRect(previewRect, 16, 16, Color.fromArgb(36, Argb.SlateGray), 1)

    painter.drawString(rect.x + 14, rect.y + 12, card.title, g_LabelFont, Argb.DarkSlateBlue)
    drawWrappedText(painter, subtitleRect, card.subtitle, g_HelpFont, Argb.DimGray)
    drawCardTexture(painter, previewRect, card)
}

func drawScene(painter: *Pixel.Painter)
{
    painter.setColorMaskFull()
    painter.clear(Color.fromArgb(255, 245, 246, 249))
    painter.setColorMaskColor()
    painter.setParams(.Antialiased)

    switch g_Page
    {
    case 0:  drawTonalPage(painter)
    case 1:  drawKernelPage(painter)
    case 2:  drawTransformPage(painter)
    case 3:  drawPainterPage(painter)
    default: unreachable
    }

    drawFooter(painter)
}

func sceneLayout()->SceneLayout
{
    let scale = g_Painter.contentScale()
    return computeSceneLayout(cast(s32, Math.round(g_RC.width / scale)),
                              cast(s32, Math.round(g_RC.height / scale)))
}

func display() fail
{
    let layout = sceneLayout()
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
    try g_Painter.render()
    g_Render.end()
}

func onResize(window: *Env.Window, width, height: s32)
{
    g_RC.width  = width
    g_RC.height = height
    g_Painter.setContentScale(window.dpiScale())
    g_NeedsPaint = true
}

func onPaint(_: *Env.Window)
{
    g_NeedsPaint = true
}

func onPointer(_: *Env.Window, event: Env.WindowPointerEvent)
{
    if event.kind != .ButtonUp or event.button != .Left do
        return

    let scale  = g_Painter.contentScale()
    let layout = sceneLayout()
    let x      = (event.x / scale - layout.rect.x) / layout.scale
    let y      = (event.y / scale - layout.rect.y) / layout.scale
    if navigationRect(0).contains(x, y) do
        changePage(-1)
    elif navigationRect(1).contains(x, y) do
        changePage(1)
}

func updateShortcuts()
{
    g_Keyboard.update()
    if g_Keyboard.isKeyJustPressed(.F1) do
        changePage(1)
    elif g_Keyboard.isKeyJustPressed(.F2) do
        changePage(-1)
}

#main
{
    g_Window = try Env.createWindow({identifier: "pixel5",
                                     title: "Pixel filters and transforms showcase",
                                     width: W,
                                     height: H,
                                     flags: .Minimizable})
    defer catch g_Window.close()
    try g_Window.setClientSize(W, H)
    g_Render  = &g_Renderer
    g_Painter = Pixel.Painter.create(g_Render)
    g_RC      = try g_Render.createContext(g_Window.nativeRenderHandle(), W, H)
    defer g_Render.deleteContext(&g_RC)
    g_Render.setCurrentContext(g_RC)
    g_Render.init()

    Swag.startWorkers()
    try loadFonts()
    try loadShowcase()

    g_Window.callbacks.onResize  = &onResize
    g_Window.callbacks.onPointer = &onPointer
    g_Window.callbacks.onPaint   = &onPaint
    try g_Window.show()

    let smoke = Env.isSmokeRun()
    var loop: Env.WindowLoop
    if smoke do
        loop.smokeFrames = MaxPages

    while loop.next()
    {
        updateShortcuts()
        if g_NeedsPaint
        {
            try display()
            g_NeedsPaint = false
        }

        if smoke and g_Page + 1 < MaxPages do
            changePage(1)
        elif not smoke do
            Threading.Thread.sleep(Time.Duration.fromMilliseconds(8))
    }
}
