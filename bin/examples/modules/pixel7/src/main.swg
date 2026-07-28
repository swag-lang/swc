using Core, Pixel, Win32

const W          = 1260
const H          = 820
const CardCount  = 8
const TestFrames = 30

const FixedWindowStyle = WS_OVERLAPPED | WS_CAPTION | WS_SYSMENU | WS_MINIMIZEBOX | WS_CLIPSIBLINGS | WS_CLIPCHILDREN

struct SceneLayout
{
    scale: f32
    rect:  Math.Rectangle
}

struct DecoderCard
{
    #[Swag.Late]
    format: string
    #[Swag.Late]
    fileName: string
    texture: Texture
    width:   s32
    height:  s32
}

var g_Window:   Env.Window
var g_Renderer: Pixel.RenderOgl
var g_Painter:  Pixel.Painter
var g_RC:       Pixel.RenderingContext

var g_TypeFace:  #null *Pixel.TypeFace
var g_TitleFont: #null *Pixel.Font
var g_LabelFont: #null *Pixel.Font
var g_HelpFont:  #null *Pixel.Font

var g_Cards: [CardCount] DecoderCard

func dataPath(fileName: string, loc = #callerlocation)->String
{
    let srcPath = Path.getDirectoryName(loc.fileName) orelse ""
    return Path.combine(Path.combine(srcPath, "data"), fileName)
}

func loadFonts() fail
{
    g_TypeFace  = TypeFace.load("segoeui.ttf")
    g_TitleFont = Font.create(notnull g_TypeFace, 34)
    g_LabelFont = Font.create(notnull g_TypeFace, 18)
    g_HelpFont  = Font.create(notnull g_TypeFace, 14)
}

func loadCard(card: *DecoderCard, format, fileName: string) fail
{
    let image    = Image.load(dataPath(fileName))
    card.format  = format
    card.fileName = fileName
    card.width   = image.width
    card.height  = image.height
    card.texture = g_Renderer.addImage(image)
}

func loadCards() fail
{
    try loadCard(&g_Cards[0], "BMP", "rocket.bmp")
    try loadCard(&g_Cards[1], "TGA", "sailboat.tga")
    try loadCard(&g_Cards[2], "JPEG", "fox.jpg")
    try loadCard(&g_Cards[3], "PNG", "succulent.png")
    try loadCard(&g_Cards[4], "GIF", "jellyfish.gif")
    try loadCard(&g_Cards[5], "TIFF", "mountain.tiff")
    try loadCard(&g_Cards[6], "ICO", "controller.ico")
    try loadCard(&g_Cards[7], "WebP", "robot.webp")
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
    const Cols = 4
    const Rows = 2

    let gap        = 18.0
    let top        = 112.0
    let bottom     = 42.0
    let cardWidth  = (W - 56.0 - (Cols - 1) * gap) / cast(f32) Cols
    let cardHeight = (H - top - bottom - (Rows - 1) * gap) / cast(f32) Rows
    let col        = index % Cols
    let row        = index / Cols
    return {28 + col * (cardWidth + gap), top + row * (cardHeight + gap), cardWidth, cardHeight}
}

func fitTextureRect(bounds: Math.Rectangle, texture: Texture)->Math.Rectangle
{
    let scale  = Math.min(bounds.width / cast(f32) texture.width, bounds.height / cast(f32) texture.height)
    let width  = cast(f32) texture.width * scale
    let height = cast(f32) texture.height * scale
    return {bounds.horzCenter() - width * 0.5, bounds.vertCenter() - height * 0.5, width, height}
}

func drawCard(painter: *Pixel.Painter, rect: Math.Rectangle, card: const &DecoderCard)
{
    let headerRect  = Math.Rectangle{rect.x, rect.y, rect.width, 58}
    let previewRect = Math.Rectangle{rect.x + 14, rect.y + 72, rect.width - 28, rect.height - 86}
    let details     = Format.toString("% - % x %", card.fileName, card.width, card.height)

    painter.fillRoundRect(rect, 18, 18, Argb.White)
    painter.drawRoundRect(rect, 18, 18, Color.fromArgb(72, Argb.SlateGray), 2)
    painter.fillRoundRect(headerRect, 18, 18, Color.fromArgb(22, Argb.MidnightBlue))
    painter.fillRoundRect(previewRect, 14, 14, Color.fromArgb(255, 239, 242, 247))

    painter.drawString(rect.x + 14, rect.y + 10, card.format, notnull g_LabelFont, Argb.DarkSlateBlue)
    painter.drawString(rect.x + 14, rect.y + 36, details, notnull g_HelpFont, Argb.DimGray)

    painter.pushClippingRect(previewRect)
    painter.drawTexture(fitTextureRect(previewRect, card.texture), card.texture)
    painter.popClippingRect()
}

func drawScene(painter: *Pixel.Painter)
{
    painter.clear(Color.fromArgb(255, 245, 246, 249))
    painter.setParams(.Antialiased)
    painter.drawString(28, 22, "Pixel image decoders", notnull g_TitleFont, Argb.MidnightBlue)
    painter.drawString(30, 70, "Eight distinct files loaded through Image.load, one for each registered decoder.", notnull g_HelpFont, Argb.DimGray)

    for [i] in CardCount do
        drawCard(painter, getCardRect(i), g_Cards[i])

    painter.drawString(28, H - 22, "BMP, TGA, JPEG, PNG, GIF, TIFF, ICO and WebP", notnull g_HelpFont, Argb.DimGray)
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

#main
{
    try Env.createWindow(&g_Window, {className: "PIXEL7_CLASS_NAME", title: "Pixel example - image decoders", width: W, height: H, style: FixedWindowStyle})
    try g_Window.setClientSize(W, H)
    g_RC = try g_Renderer.native.createContext(&g_Window, W, H)
    g_Renderer.setCurrentContext(g_RC)
    g_Renderer.init()

    try loadFonts()
    try loadCards()

    g_Window.callbacks.onResize = &onResize
    try g_Window.show()

    var loop: Env.WindowLoop
    if Env.hasArg("swag.test") do
        loop.maxTestFrames = TestFrames
    while loop.next()
    {
        display()
    }

    g_Renderer.native.dropContext(g_RC)
}
