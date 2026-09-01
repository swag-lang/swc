#global if #command == Swag.CompilerCommand.Test

using Swag, Core

func makeTrianglePath()->LinePath
{
    var result: retval
    result.start(0, 0)
    result.lineTo(10, 0)
    result.lineTo(5, 8)
    result.close()
    return result
}

// A document declares its view box and writes straight segments as line commands.
#test
{
    var doc = Svg.Document.create(64, 32)
    doc.addPath(makeTrianglePath(), Color.fromRgb(0xF7, 0xF9, 0x00))

    let text = doc.toString()
    Swag.assert(text.contains("viewBox=\"0 0 64 32\""))
    Swag.assert(text.contains("width=\"64\""))
    Swag.assert(text.contains("fill=\"#F7F900\""))
    Swag.assert(text.contains("M0 0L10 0L5 8"))
    Swag.assert(text.contains("Z\"/>"))
    Swag.assert(text.endsWith("</svg>\n"))
}

// Whole coordinates lose their fraction and fractions lose their trailing zeros.
#test
{
    var path: LinePath
    path.start(1.5, 2)
    path.lineTo(3.25, 4)
    path.close()

    var doc = Svg.Document.create(8, 8)
    doc.addPath(path, Color.fromRgb(0, 0, 0))

    let text = doc.toString()
    Swag.assert(text.contains("M1.5 2L3.25 4"))
    Swag.assert(!text.contains("1.500"))
}

// A ground is painted before every shape, and a title names the document.
#test
{
    var doc = Svg.Document.create(10, 10)
    doc.setTitle("Swag & <co>")
    doc.setBackground(Color.fromRgb(0x0B, 0x0B, 0x0D))
    doc.addPath(makeTrianglePath(), Color.fromRgb(255, 255, 255))

    let text = doc.toString()
    Swag.assert(text.contains("aria-label=\"Swag &amp; &lt;co&gt;\""))
    Swag.assert(text.contains("<rect width=\"10\" height=\"10\" fill=\"#0B0B0D\"/>"))
    Swag.assert(text.indexOf("<rect") < text.indexOf("<path"))
}

// Without a title the document declares itself decorative.
#test
{
    var doc = Svg.Document.create(4, 4)
    Swag.assert(doc.toString().contains("aria-hidden=\"true\""))
}

// The even-odd rule and a translucent color are carried by the shape.
#test
{
    var doc = Svg.Document.create(8, 8)
    doc.addPath(makeTrianglePath(), Color.fromArgb(128'u8, 10'u8, 20'u8, 30'u8), .EvenOdd)

    let text = doc.toString()
    Swag.assert(text.contains("fill-rule=\"evenodd\""))
    Swag.assert(text.contains("fill-opacity="))
}

// Bézier segments keep their own commands instead of being flattened.
#test
{
    var path: LinePath
    path.start(0, 0)
    path.bezierTo(4, 4, 2, 0)
    path.close()

    var doc = Svg.Document.create(8, 8)
    doc.addPath(path, Color.fromRgb(0, 0, 0))
    Swag.assert(doc.toString().contains("Q2 0 4 4"))
}

// Every contour of a list joins the same shape element.
#test
{
    var list: LinePathList
    var first = list.newPath()
    first[] = makeTrianglePath()
    var second = list.newPath()
    second[] = makeTrianglePath()

    var doc = Svg.Document.create(16, 16)
    doc.addPath(list, Color.fromRgb(1, 2, 3))

    let text = doc.toString()
    Swag.assert(text.indexOf("<path") != Swag.U64.Max)
    Swag.assert(text.indexOf("<path", text.indexOf("<path") + 1) == Swag.U64.Max)
    Swag.assert(text.indexOf("M0 0", text.indexOf("M0 0") + 1) != Swag.U64.Max)
}

// An empty document still writes a well-formed root element.
#test
{
    let text = Svg.Document.create(4, 4).toString()
    Swag.assert(text.contains("<svg "))
    Swag.assert(!text.contains("<path"))
}

// Painting a document on screen goes through the stroker, not the rasterizer, and asks it to
// measure a stroke's coverage from its centre line. A drawing is mostly stroke, so this is the
// path that decides both what a vector document costs and what it looks like.
#[Swag.TestTag("golden")]
#test
{
    const Source = "<svg width='120' height='72' viewBox='0 0 120 72'>" ++
                   "<rect width='120' height='72' fill='#f6f2ea'/>" ++
                   "<path d='M8 60 L28 14 L48 60 L68 14 L88 60' fill='none' stroke='#23201c' stroke-width='1.5'/>" ++
                   "<path d='M8 8 Q60 40 112 8' fill='none' stroke='#c0392b' stroke-width='0.4'/>" ++
                   "<circle cx='96' cy='40' r='16' fill='none' stroke='#2b6cb0' stroke-width='3'/>" ++
                   "<path d='M8 66 H112' fill='none' stroke='#2f855a' stroke-width='6' stroke-linecap='round'/>" ++
                   "</svg>"

    let drawing = expect Svg.Drawing.parse(Source)

    var cpu:      RenderCpu
    let renderer: IRenderer = &cpu
    renderer.init()

    var target = renderer.createRenderTarget(120, 72)
    defer renderer.deleteRenderTarget(&target)

    var painter = Painter.create(renderer)
    painter.begin()
    painter.bindRenderTarget(&target)
    painter.setColorMaskFull()
    painter.setBlendingMode(.Copy)
    painter.clear(Color.fromArgb(Argb.White))
    painter.setBlendingMode(.Alpha)
    painter.setAntialiased(true)
    drawing.paint(&painter, 0, 0)
    painter.unbindRenderTarget()
    painter.end()
    renderer.draw(&painter)

    let image = renderer.readRenderTarget(&target, 0, 0, 120, 72)
    Testing.assertImageGolden(&image, "svg.document.paint")
}
