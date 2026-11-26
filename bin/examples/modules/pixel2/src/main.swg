using Core, Pixel, TrueType

const W = 800
const H = 388

var g_Window:      Env.Window
var g_Renderer:    Pixel.RenderOgl
late var g_Render: Pixel.IRenderer
var g_Painter:     Pixel.Painter
var g_RC:          Pixel.RenderContext

late var g_TitleFont: *Pixel.Font
late var g_BodyFont:  *Pixel.Font
late var g_InfoFont:  *Pixel.Font
var g_FontInfo:       String

func loadFonts() fail
{
    const Bytes = #include("../../../assets/segoeui.ttf")
    let face = try Face.load(Bytes)
    defer face.destroy()

    g_FontInfo = Format.toString("% %  /  % glyphs  /  % bytes",
                                 face.familyName,
                                 face.styleName,
                                 face.glyphCount,
                                 Bytes.count)

    let typeface = try TypeFace.create("segoeui.ttf", Bytes)
    g_TitleFont = g_Renderer.fonts.createFont(typeface, 54)
    g_BodyFont  = g_Renderer.fonts.createFont(typeface, 34)
    g_InfoFont  = g_Renderer.fonts.createFont(typeface, 18)
}

func drawScene(painter: *Pixel.Painter)
{
    painter.setColorMaskFull()
    painter.clear(Argb.WhiteSmoke)
    painter.setColorMaskColor()
    painter.setParams(.Antialiased)

    painter.fillRoundRect(36, 36, W - 72, H - 72, 18, 18, Argb.MidnightBlue)
    painter.drawString(64, 60, "TrueType text", g_TitleFont, Argb.White)
    painter.drawString(64, 154, "Sphinx of black quartz, judge my vow.", g_BodyFont, Argb.LightCyan)

    painter.fillRect(64, 223, W - 128, 1, Argb.SlateBlue)
    painter.drawString(64, 246, "Bundled font  /  segoeui.ttf", g_InfoFont, Argb.LightSteelBlue)
    painter.drawString(64, 276, g_FontInfo, g_InfoFont, Argb.PaleGoldenrod)
}

func display() fail
{
    g_Render.begin(g_RC)
    g_Painter.begin()
    drawScene(&g_Painter)
    g_Painter.end()
    try g_Painter.render()
    g_Render.end()
}

func onResize(window: *Env.Window, width, height: s32)
{
    // The client size is physical device pixels; the scene keeps drawing in logical
    // W x H units, so the painter maps them to device pixels on scaled displays.
    g_RC.width  = width
    g_RC.height = height
    g_Painter.setContentScale(window.dpiScale())
}

#main
{
    g_Window = try Env.createWindow({
        identifier: "pixel2",
        title: "Pixel TrueType example",
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

    // RenderOgl.init clears font caches, so create Pixel fonts after it.
    try loadFonts()

    g_Window.callbacks.onResize = &onResize

    try g_Window.show()

    var loop: Env.WindowLoop
    while loop.next()
    {
        try display()
    }
}
