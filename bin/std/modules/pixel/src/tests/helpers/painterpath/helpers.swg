#global if #command == Swag.CompilerCommand.Test
#global internal

using Swag, Core, Core.Math

// Returns the total darkness a horizontal stroke of `size` lays over a white ground.
func strokeDarkness(size: f32, contentScale = 1.0'f32)->u64
{
    const Side = 64's32

    var path: LinePath
    path.start(8, 32)
    path.lineTo(56, 32)

    var painter: Painter
    painter.begin()
    painter.setColorMaskFull()
    painter.setContentScale(contentScale)
    painter.clear(Color.fromArgb(Argb.White))
    painter.drawPath(&path, Color.fromArgb(Argb.Black), size)
    painter.end()

    var renderer: RenderCpu
    renderer.begin(cast(s32, (cast(f32, Side) * contentScale)), cast(s32, (cast(f32, Side) * contentScale)))
    let render: IRenderer = &renderer
    expect render.draw(&painter)
    render.end()

    let image  = renderer.surfaceImage()
    var result = 0'u64
    for y in image.height
    {
        for x in image.width do
            result += cast(u64, (255 - image.pixelColor(x, y).r))
    }

    return result
}

// A stroke thinner than one device pixel is drawn one pixel wide with the width it lost moved
// into its opacity, instead of being dropped: a vector drawing shown small is mostly such
// strokes, and losing them reads as missing geometry rather than as a light line.
