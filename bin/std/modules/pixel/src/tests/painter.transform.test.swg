#global #if #command == Swag.CompilerCommand.Test
using Swag, Core, Win32

const TransformTestWindowStyle = WS_OVERLAPPED | WS_CAPTION | WS_SYSMENU | WS_MINIMIZEBOX | WS_CLIPSIBLINGS | WS_CLIPCHILDREN

func makeQuadrantTexture()->Image
{
    var image = Image.create(32, 32, .RGBA8)
    for y in image.height
    {
        var pix = image.pixels.buffer + y * image.width8
        for x in image.width
        {
            let left = x < image.width / 2
            let top  = y < image.height / 2

            if top and left
            {
                pix[0] = 255
                pix[1] = 0
                pix[2] = 0
                pix[3] = 255
            }
            elif top
            {
                pix[0] = 0
                pix[1] = 255
                pix[2] = 0
                pix[3] = 255
            }
            elif left
            {
                pix[0] = 0
                pix[1] = 0
                pix[2] = 255
                pix[3] = 255
            }
            else
            {
                pix[0] = 255
                pix[1] = 255
                pix[2] = 0
                pix[3] = 255
            }

            pix += image.bpp8
        }
    }

    return image
}

func renderRotatedTexture(angle: Math.Angle)->Image throw
{
    var window: Env.Window
    let className = Format.toString("PIXEL_TRANSFORM_TEST_WINDOW_%", angle.toDegrees())
    try Env.createWindow(&window, {className: className, title: "pixel transform test", width: 256, height: 256, style: TransformTestWindowStyle})
    try window.setClientSize(256, 256)

    var renderer: Pixel.RenderOgl
    let rc = try renderer.native.createContext(&window, 256, 256)
    renderer.setCurrentContext(rc)
    renderer.init()
    try window.show()

    let texture = renderer.addImage(makeQuadrantTexture())
    let rt      = renderer.getRenderTarget(256, 256)
    var painter: Pixel.Painter

    renderer.begin(rc)
    painter.begin()
    painter.bindRenderTarget(rt, true)
    painter.clear(Argb.White)
    painter.setInterpolationMode(.Pixel)
    painter.pushTransform()
    painter.rotateTransform(angle, 128, 128)
    painter.drawTexture(64, 64, 128, 128, texture)
    painter.popTransform()
    painter.unbindRenderTarget()
    painter.end()
    renderer.draw(&painter)
    renderer.end()

    let buffer = renderer.getTexturePixels(rt.colorBuffer, .BGRA8)
    let image  = Image.create(rt.colorBuffer.width, rt.colorBuffer.height, .BGRA8, buffer.toSlice())

    renderer.releaseRenderTarget(rt)
    renderer.native.dropContext(rc)
    return image
}

func dumpColor(label: string, color: Color)
{
    Console.printf("% => rgba(%, %, %, %)\n", label, color.r, color.g, color.b, color.a)
}

#test
{
    let baseline = catch renderRotatedTexture(0.0'deg)
    @assert(@err == null)
    Console.println("rotate 0")
    dumpColor("nw", baseline.getPixelColor(104, 104))
    dumpColor("ne", baseline.getPixelColor(152, 104))
    dumpColor("sw", baseline.getPixelColor(104, 152))
    dumpColor("se", baseline.getPixelColor(152, 152))

    let positive = catch renderRotatedTexture(10.0'deg)
    @assert(@err == null)
    Console.println("rotate +10")
    dumpColor("nw", positive.getPixelColor(104, 104))
    dumpColor("ne", positive.getPixelColor(152, 104))
    dumpColor("sw", positive.getPixelColor(104, 152))
    dumpColor("se", positive.getPixelColor(152, 152))

    let negative = catch renderRotatedTexture(-12.0'deg)
    @assert(@err == null)
    Console.println("rotate -12")
    dumpColor("nw", negative.getPixelColor(104, 104))
    dumpColor("ne", negative.getPixelColor(152, 104))
    dumpColor("sw", negative.getPixelColor(104, 152))
    dumpColor("se", negative.getPixelColor(152, 152))

    @assert(true)
}
