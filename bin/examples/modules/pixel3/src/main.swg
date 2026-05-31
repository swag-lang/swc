using Core, Pixel

const W = 980
const H = 640

var g_Window:   Env.Window
var g_Renderer: Pixel.RenderOgl
var g_Painter:  Pixel.Painter
var g_RC:       Pixel.RenderingContext

var g_FontBytes:   Array'u8
var g_TypeFace:    *Pixel.TypeFace
var g_TitleFont:   *Pixel.Font
var g_LabelFont:   *Pixel.Font
var g_Sdf14Font:   *Pixel.Font
var g_Sdf18Font:   *Pixel.Font
var g_Sdf26Font:   *Pixel.Font
var g_Sdf38Font:   *Pixel.Font
var g_Sdf54Font:   *Pixel.Font
var g_ZoomFont:    *Pixel.Font

func fontPath(fileName: string, loc = #callerlocation)->String
{
    let srcPath = Path.getDirectoryName(loc.fileName)
    return Path.combine(Path.combine(srcPath, "data"), fileName)
}

func loadFonts() throw
{
    let path = fontPath("segoeui.ttf")

    g_FontBytes = File.readAllBytes(path)
    g_TypeFace  = TypeFace.create(path, g_FontBytes.toSlice())

    g_TitleFont = Font.createSdf(g_TypeFace, 42, 10)
    g_LabelFont = Font.createSdf(g_TypeFace, 16, 6)
    g_Sdf14Font = Font.createSdf(g_TypeFace, 14, 5)
    g_Sdf18Font = Font.createSdf(g_TypeFace, 18, 6)
    g_Sdf26Font = Font.createSdf(g_TypeFace, 26, 8)
    g_Sdf38Font = Font.createSdf(g_TypeFace, 38, 10)
    g_Sdf54Font = Font.createSdf(g_TypeFace, 54, 12)
    g_ZoomFont  = Font.createSdf(g_TypeFace, 28, 10)
}

func drawSampleLine(painter: *Pixel.Painter, y: f32, label, text: string, font: *Pixel.Font, color: Color)
{
    painter.drawString(42, y + 4, label, g_LabelFont, Argb.LightSlateGray)
    painter.drawString(154, y, text, font, color)
}

func drawZoomSample(painter: *Pixel.Painter, y: f32, label: string, zoom: f32, color: Color)
{
    painter.drawString(550, y + 8, label, g_LabelFont, Argb.LightSlateGray)
    painter.drawString(652, y, "SDF", g_ZoomFont, color, .None, zoom)
}

func drawNativeSizes(painter: *Pixel.Painter)
{
    painter.drawString(42, 28, "SDF text rendering", g_TitleFont, Argb.MidnightBlue)
    painter.drawString(44, 80, "Separate SDF atlases at native sizes", g_LabelFont, Argb.DimGray)

    drawSampleLine(painter, 118, "14 px", "Small text stays readable: 0123456789", g_Sdf14Font, Argb.DarkSlateGray)
    drawSampleLine(painter, 154, "18 px", "The quick brown fox jumps.", g_Sdf18Font, Argb.Black)
    drawSampleLine(painter, 202, "26 px", "Mixed case, punctuation, accents.", g_Sdf26Font, Argb.SeaGreen)
    drawSampleLine(painter, 270, "38 px", "Sharp curves", g_Sdf38Font, Argb.Crimson)
    drawSampleLine(painter, 366, "54 px", "Large text", g_Sdf54Font, Argb.RoyalBlue)
}

func drawZoomSizes(painter: *Pixel.Painter)
{
    painter.drawString(550, 80, "Same SDF font, different draw zooms", g_LabelFont, Argb.DimGray)

    drawZoomSample(painter, 120, "1.0x", 1.0, Argb.DarkSlateGray)
    drawZoomSample(painter, 174, "1.6x", 1.6, Argb.SeaGreen)
    drawZoomSample(painter, 256, "2.4x", 2.4, Argb.Crimson)
    drawZoomSample(painter, 384, "3.4x", 3.4, Argb.RoyalBlue)

    painter.drawString(552, 552, "The shader reconstructs the glyph edge from the distance value.", g_Sdf18Font, Argb.DarkSlateGray)
}

func drawScene(painter: *Pixel.Painter)
{
    painter.clear(Argb.GhostWhite)
    painter.setParams(.Antialiased)

    drawNativeSizes(painter)
    drawZoomSizes(painter)

    painter.drawStringCenter(W * 0.5, 610, "Pixel SDF font atlas", g_Sdf26Font, Argb.DimGray)
}

func display()
{
    g_Renderer.begin(g_RC)
    g_Painter.begin()
    drawScene(&g_Painter)
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
    try Env.createWindow(&g_Window, {className: "PIXEL3_CLASS_NAME", title: "Pixel SDF font rendering", width: W, height: H})
    g_RC = try g_Renderer.native.createContext(&g_Window, W, H)
    g_Renderer.setCurrentContext(g_RC)
    g_Renderer.init()

    // RenderOgl.init clears font caches, so create Pixel fonts after it.
    try loadFonts()

    g_Window.callbacks.onResize = &onResize

    try g_Window.show()

    var loop: Env.WindowLoop
    while loop.next()
    {
        display()
    }

    g_Renderer.native.dropContext(g_RC)
}
