using Core, Pixel, Win32

const W = 1080
const H = 560

// Same text rendered with the three techniques, at many sizes (small sizes first).
const Sizes   = [8, 9, 10, 11, 12, 13, 14, 16, 18, 22, 28, 36]
const Sample  = "Hamburg agQ 012"

const ColPx     = 22.0
const ColBitmap = 120.0
const ColSdf    = 440.0
const ColMsdf   = 760.0

struct SceneLayout
{
    scale:      f32
    rect:       Math.Rectangle
}

var g_Window:   Env.Window
var g_Renderer: Pixel.RenderOgl
var g_Painter:  Pixel.Painter
var g_RC:       Pixel.RenderingContext

var g_FontBytes:   Array'u8
var g_TypeFace:    *Pixel.TypeFace
var g_HeaderFont:  *Pixel.Font

func fontPath(fileName: string, loc = #callerlocation)->String
{
    let srcPath = Path.getDirectoryName(loc.fileName)
    return Path.combine(Path.combine(srcPath, "data"), fileName)
}

func loadFonts() throw
{
    let path = fontPath("segoeui.ttf")

    g_FontBytes  = File.readAllBytes(path)
    g_TypeFace   = TypeFace.create(path, g_FontBytes.toSlice())
    g_HeaderFont = Font.createMsdf(g_TypeFace, 15, 6)
}

// The three fonts for a given size (all cached after the first call).
func fontsFor(size: u32)->{ bmp: *Pixel.Font, sdf: *Pixel.Font, msdf: *Pixel.Font }
{
    let spread = Math.max(2'u32, size / 4)

    var result: retval
    result.bmp  = Font.createBitmap(g_TypeFace, size)
    result.sdf  = Font.createSdf(g_TypeFace, size, spread)
    result.msdf = Font.createMsdf(g_TypeFace, size, spread)
    return result
}

func computeSceneLayout(width, height: s32)->SceneLayout
{
    let surfaceWidth  = Math.max(width, 1)
    let surfaceHeight = Math.max(height, 1)
    let scaleX        = cast(f32) surfaceWidth / cast(f32) W
    let scaleY        = cast(f32) surfaceHeight / cast(f32) H

    with var result: retval = undefined
    {
        .scale = Math.min(scaleX, scaleY)
        .rect  = {0, 0, cast(f32) W * .scale, cast(f32) H * .scale}
        .rect.x = Math.round((cast(f32) surfaceWidth - .rect.width) * 0.5)
        .rect.y = Math.round((cast(f32) surfaceHeight - .rect.height) * 0.5)
    }

    return result
}

func drawScene(painter: *Pixel.Painter, layout: SceneLayout)
{
    painter.clear(Argb.White)
    painter.setParams(.Antialiased)

    painter.pushClippingSurfaceRect(layout.rect)
    painter.pushTransform()
    painter.scaleTransform(layout.scale)
    painter.translateTransform(layout.rect.x, layout.rect.y)

    // Column headers
    painter.drawString(ColPx, 16, "px", g_HeaderFont, Argb.DimGray)
    painter.drawString(ColBitmap, 16, "Bitmap", g_HeaderFont, Argb.MidnightBlue)
    painter.drawString(ColSdf, 16, "SDF", g_HeaderFont, Argb.MidnightBlue)
    painter.drawString(ColMsdf, 16, "MSDF", g_HeaderFont, Argb.MidnightBlue)

    var y = 46.0
    foreach size in Sizes
    {
        let usize = cast(u32) size
        let fonts = fontsFor(usize)

        painter.drawString(ColPx, y, Format.toString("%", size), g_HeaderFont, Argb.DimGray)
        painter.drawString(ColBitmap, y, Sample, fonts.bmp, Argb.Black)
        painter.drawString(ColSdf, y, Sample, fonts.sdf, Argb.Black)
        painter.drawString(ColMsdf, y, Sample, fonts.msdf, Argb.Black)

        y += cast(f32) size + 12
    }

    painter.popTransform()
    painter.popClippingRect()
}

func display()
{
    let layout = computeSceneLayout(g_RC.width, g_RC.height)
    g_Renderer.begin(g_RC)
    g_Painter.begin()
    drawScene(&g_Painter, layout)
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
    try Env.createWindow(&g_Window, {className: "PIXEL3_CLASS_NAME", title: "Pixel font rendering: Bitmap vs SDF vs MSDF", width: W, height: H})
    try g_Window.setClientSize(W, H)
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
