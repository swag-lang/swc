using Core, Pixel

const W = 1080
const H = 560

// Same text rendered with the three techniques, at many sizes (small sizes first).
const Sizes  = [8, 9, 10, 11, 12, 13, 14, 16, 18, 22, 28, 36]
const Sample = "Hamburg agQ 012"

const ColPx     = 22.0
const ColBitmap = 120.0
const ColMsdf   = 440.0
const ColAuto   = 760.0

struct SceneLayout
{
    scale: f32
    rect:  Math.Rectangle
}

var g_Window:   Env.Window
var g_Renderer: Pixel.RenderOgl
#[Swag.Late]
var g_Render:  Pixel.IRenderer
var g_Painter: Pixel.Painter
var g_RC:      Pixel.RenderContext

var g_FontPath:   String
var g_FontBytes:  Array'u8
var g_TypeFace:   #null *Pixel.TypeFace
var g_HeaderFont: #null *Pixel.Font

func fontPath(fileName: string, loc = #callerlocation)->String
{
    let srcPath = Path.directoryName(loc.fileName)
    return Path.combine(Path.combine(srcPath, "data"), fileName)
}

func loadFonts() fail
{
    g_FontPath = fontPath("segoeui.ttf")
    let path = g_FontPath.toString()

    g_FontBytes  = File.readAllBytes(path)
    g_TypeFace   = TypeFace.create(path, g_FontBytes.toSlice())
    g_HeaderFont = g_Renderer.fonts.createFont(g_TypeFace!, 15)
}

// The three fonts for a given size (all cached after the first call).
func fontsFor(size: u32)->{ bmp, msdf, auto: *Pixel.Font }
{
    var result: retval
    result.bmp  = g_Renderer.fonts.createFont(g_TypeFace!, size, .Bitmap)
    result.msdf = g_Renderer.fonts.createFont(g_TypeFace!, size, .Msdf)
    result.auto = g_Renderer.fonts.createFont(g_TypeFace!, size, .Auto)
    return result
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

func drawScene(painter: *Pixel.Painter, layout: SceneLayout)
{
    painter.setColorMaskFull()
    painter.clear(Argb.White)
    painter.setColorMaskColor()
    painter.setParams(.Antialiased)

    painter.pushClippingSurfaceRect(layout.rect)
    painter.pushTransform()
    painter.scaleTransform(layout.scale)
    painter.translateTransform(layout.rect.x, layout.rect.y)

    // Column headers
    painter.drawString(ColPx, 16, "px", g_HeaderFont!, Argb.DimGray)
    painter.drawString(ColBitmap, 16, "Bitmap", g_HeaderFont!, Argb.MidnightBlue)
    painter.drawString(ColMsdf, 16, "MSDF", g_HeaderFont!, Argb.MidnightBlue)
    painter.drawString(ColAuto, 16, "Auto", g_HeaderFont!, Argb.DarkGreen)

    var y = 46.0
    for size in Sizes
    {
        let usize = cast(u32) size
        let fonts = fontsFor(usize)

        painter.drawString(ColPx, y, Format.toString("%", size), g_HeaderFont!, Argb.DimGray)
        painter.drawString(ColBitmap, y, Sample, fonts.bmp, Argb.Black)
        painter.drawString(ColMsdf, y, Sample, fonts.msdf, Argb.Black)
        painter.drawString(ColAuto, y, Sample, fonts.auto, Argb.Black)

        y += cast(f32) size + 12
    }

    painter.popTransform()
    painter.popClippingRect()
}

func display()
{
    // The render context is physical device pixels; the fit is computed in logical
    // units, and the painter maps them to device pixels on scaled displays.
    let scale  = g_Painter.contentScale()
    let layout = computeSceneLayout(cast(s32) Math.round(g_RC.width / scale), cast(s32) Math.round(g_RC.height / scale))
    g_Render.begin(g_RC)
    g_Painter.begin()
    drawScene(&g_Painter, layout)
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

#main
{
    g_Window = try Env.createWindow({identifier: "pixel3", title: "Pixel font rendering: Bitmap vs MSDF vs Auto", width: W, height: H})
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
        display()
    }
}
