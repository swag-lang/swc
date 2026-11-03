#global if #command == Swag.CompilerCommand.Test

using Swag, Core

func makeTrianglePath()->LinePath
{
    var result: #returntype
    result.start(0, 0)
    result.lineTo(10, 0)
    result.lineTo(5, 8)
    result.close()
    return result
}

// A document declares its view box and writes straight segments as line commands.

// Whole coordinates lose their fraction and fractions lose their trailing zeros.

// A ground is painted before every shape, and a title names the document.

// Without a title the document declares itself decorative.

// The even-odd rule and a translucent color are carried by the shape.

// Bézier segments keep their own commands instead of being flattened.

// Every contour of a list joins the same shape element.

// An empty document still writes a well-formed root element.

// Painting a document on screen goes through the stroker, not the rasterizer, and asks it to
// measure a stroke's coverage from its centre line. A drawing is mostly stroke, so this is the
// path that decides both what a vector document costs and what it looks like.
#[Swag.TestTag("golden")]
#test
{
    const Source = """\
        <svg width='120' height='72' viewBox='0 0 120 72'>\
        <rect width='120' height='72' fill='#f6f2ea'/>\
        <path d='M8 60 L28 14 L48 60 L68 14 L88 60' fill='none' stroke='#23201c' stroke-width='1.5'/>\
        <path d='M8 8 Q60 40 112 8' fill='none' stroke='#c0392b' stroke-width='0.4'/>\
        <circle cx='96' cy='40' r='16' fill='none' stroke='#2b6cb0' stroke-width='3'/>\
        <path d='M8 66 H112' fill='none' stroke='#2f855a' stroke-width='6' stroke-linecap='round'/>\
        </svg>"""

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
