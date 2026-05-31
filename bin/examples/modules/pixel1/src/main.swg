using Core, Pixel, Core.Math

const W = 640
const H = 480

var g_Window:   Env.Window
var g_Renderer: Pixel.RenderOgl
var g_Painter:  Pixel.Painter
var g_RC:       Pixel.RenderingContext
var g_IsReady   = false

func drawScene(painter: *Pixel.Painter)
{
    painter.clear(Argb.WhiteSmoke)
    painter.setParams(.Antialiased)

    painter.fillRoundRect(48, 48, 240, 160, 18, 18, Argb.SteelBlue)
    painter.drawRoundRect(48, 48, 240, 160, 18, 18, Argb.MidnightBlue, 4)

    painter.fillCircle(414, 132, 72, Argb.Tomato)
    painter.drawCircle(414, 132, 72, Argb.Firebrick, 5)

    painter.fillRect(96, 310, 448, 72, Argb.MediumSeaGreen)
    painter.drawRect(96, 310, 448, 72, Argb.DarkGreen, 4)

    var pen = Pen.createSolid(Argb.Goldenrod, 10)
    pen.begCapStyle = .Round
    pen.endCapStyle = .Round
    painter.drawLine(80, 240, 560, 240, pen)
}

func display()
{
    if !g_IsReady do
        return

    g_Renderer.begin(g_RC)
    g_Painter.begin()
    drawScene(&g_Painter)
    g_Painter.end()
    g_Renderer.draw(&g_Painter)
    g_Renderer.end()
}

func onPaint(_window: *Env.Window)
{
    display()
}

func onResize(_window: *Env.Window, width, height: s32)
{
    if !g_IsReady do
        return

    g_RC.width  = width
    g_RC.height = height
    g_Window.requestPaint()
}

func createWindow() throw
{
    try Env.createWindow(&g_Window, {className: "PIXEL1_CLASS_NAME", title: "Pixel example", width: W, height: H})
}

func messageLoop()
{
    var loop: Env.WindowLoop
    while loop.next()
    {
        display()
    }
}

#main
{
    try createWindow()

    g_RC = try g_Renderer.native.createContext(&g_Window, W, H)
    g_Renderer.setCurrentContext(g_RC)
    g_Renderer.init()
    g_IsReady = true
    g_Window.callbacks.onPaint  = &onPaint
    g_Window.callbacks.onResize = &onResize

    display()
    try g_Window.show()

    messageLoop()

    g_IsReady = false
    g_Renderer.native.dropContext(g_RC)
}
