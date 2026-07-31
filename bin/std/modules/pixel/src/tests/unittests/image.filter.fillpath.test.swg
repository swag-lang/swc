#global if #command == Swag.CompilerCommand.Test

using Swag, Core

// Builds an axis-aligned rectangle, whose coverage is exact at every pixel.
func makeRectPath(x0, y0, x1, y1: f32)->LinePath
{
    var result: retval
    result.start(x0, y0)
    result.lineTo(x1, y0)
    result.lineTo(x1, y1)
    result.lineTo(x0, y1)
    result.close()
    return result
}

// A rectangle on pixel boundaries covers exactly the pixels it encloses.
#test
{
    var img = Image.create(4, 4, .RGBA8)
    img.clear()

    let color = Color.fromRgb(247, 249, 0)
    img.fillPath(makeRectPath(1, 1, 3, 3), color)

    assertPixel(img, 1, 1, color)
    assertPixel(img, 2, 2, color)
    assertPixel(img, 0, 0, Color.fromArgb(0'u8, 0'u8, 0'u8, 0'u8))
    assertPixel(img, 3, 3, Color.fromArgb(0'u8, 0'u8, 0'u8, 0'u8))
    assertPixel(img, 0, 1, Color.fromArgb(0'u8, 0'u8, 0'u8, 0'u8))
}

// Half a pixel of horizontal coverage is half the opacity: the edges are antialiased.
#test
{
    var img = Image.create(2, 1, .RGBA8)
    img.clear()

    img.fillPath(makeRectPath(0, 0, 0.5, 1), Color.fromRgb(255, 255, 255))

    let left = img.getPixelColor(0, 0)
    @assert(left.a > 100 and left.a < 155)
    @assert(img.getPixelColor(1, 0).a == 0)
}

// Filling over an opaque ground blends toward the new color.
#test
{
    var img = Image.create(2, 2, .RGBA8)
    img.fill(Color.fromRgb(0, 0, 0))
    img.fillPath(makeRectPath(0, 0, 2, 2), Color.fromRgb(255, 255, 255))

    assertPixel(img, 0, 0, Color.fromRgb(255, 255, 255))
    assertPixel(img, 1, 1, Color.fromRgb(255, 255, 255))
}

// The fill rule decides what two nested contours enclose.
#test
{
    var nested: LinePathList

    // Both contours turn the same way, so the inner one is a hole only under 'EvenOdd'.
    var outer = nested.newPath()
    dref outer = makeRectPath(0, 0, 6, 6)
    var inner = nested.newPath()
    dref inner = makeRectPath(2, 2, 4, 4)

    let color = Color.fromRgb(255, 255, 255)

    var nonZero = Image.create(6, 6, .RGBA8)
    nonZero.clear()
    nonZero.fillPath(nested, color)
    @assert(nonZero.getPixelColor(3, 3).a == 255)

    var evenOdd = Image.create(6, 6, .RGBA8)
    evenOdd.clear()
    evenOdd.fillPath(nested, color, {rule: .EvenOdd})
    @assert(evenOdd.getPixelColor(3, 3).a == 0)
    @assert(evenOdd.getPixelColor(1, 1).a == 255)
}

// A BGRA image receives the same color, in its own channel order.
#test
{
    var img = Image.create(2, 2, .BGRA8)
    img.clear()
    img.fillPath(makeRectPath(0, 0, 2, 2), Color.fromRgb(10, 20, 30))

    assertPixel(img, 0, 0, Color.fromRgb(10, 20, 30))
    @assert((notnull img.pixels.buffer)[0] == 30'u8)     // B comes first on disk
    @assert((notnull img.pixels.buffer)[2] == 10'u8)     // R comes last
}

// A path with fewer than three points encloses nothing.
#test
{
    var degenerate: LinePath
    degenerate.start(0, 0)
    degenerate.lineTo(4, 4)

    var img = Image.create(4, 4, .RGBA8)
    img.clear()
    img.fillPath(degenerate, Color.fromRgb(255, 255, 255))
    @assert(img.getPixelColor(2, 2).a == 0)
}
