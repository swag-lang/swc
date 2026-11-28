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
#test
{
    var doc = Svg.Document.create(64, 32)
    doc.addPath(makeTrianglePath(), Color.fromRgb(0xF7, 0xF9, 0x00))

    let text = doc.toString()
    Swag.require(text.contains("viewBox=\"0 0 64 32\""))
    Swag.require(text.contains("width=\"64\""))
    Swag.require(text.contains("fill=\"#F7F900\""))
    Swag.require(text.contains("M0 0L10 0L5 8"))
    Swag.require(text.contains("Z\"/>"))
    Swag.require(text.endsWith("</svg>\n"))
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
    Swag.require(text.contains("M1.5 2L3.25 4"))
    Swag.require(not text.contains("1.500"))
}

// Fractional coordinates retain enough digits to round back to their source f32 values.
#test
{
    let x = 1.2345678_f32
    let y = 4.567891_f32
    var path: LinePath
    path.start(0, 0)
    path.lineTo(x, y)
    path.close()

    var doc = Svg.Document.create(8, 8)
    doc.addPath(path, Color.fromRgb(0, 0, 0))
    let text  = doc.toString()
    let xText = Format.toString("%", x)
    let yText = Format.toString("%", y)
    Swag.require(text.contains(Format.toString("L% %", xText, yText).toString()))
    Swag.require(expect StrConv.toF32(xText.toString()) == x)
    Swag.require(expect StrConv.toF32(yText.toString()) == y)
}

// A ground is painted before every shape, and a title names the document.
#test
{
    var doc = Svg.Document.create(10, 10)
    doc.setTitle("Swag & <co>")
    doc.setBackground(Color.fromArgb(128_u8, 0x0B_u8, 0x0B_u8, 0x0D_u8))
    doc.addPath(makeTrianglePath(), Color.fromRgb(255, 255, 255))

    let text = doc.toString()
    Swag.require(text.contains("aria-label=\"Swag &amp; &lt;co&gt;\""))
    Swag.require(text.contains("<rect width=\"10\" height=\"10\" fill=\"#0B0B0D\" fill-opacity=\"0.502\"/>"))
    Swag.require(text.indexOf("<rect") < text.indexOf("<path"))
}

// Without a title the document declares itself decorative.
#test
{
    var doc = Svg.Document.create(4, 4)
    Swag.require(doc.toString().contains("aria-hidden=\"true\""))
}

// The even-odd rule and a translucent color are carried by the shape.
#test
{
    var doc = Svg.Document.create(8, 8)
    doc.addPath(makeTrianglePath(), Color.fromArgb(128_u8, 10_u8, 20_u8, 30_u8), .EvenOdd)

    let text = doc.toString()
    Swag.require(text.contains("fill-rule=\"evenodd\""))
    Swag.require(text.contains("fill-opacity="))
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
    Swag.require(doc.toString().contains("Q2 0 4 4"))
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
    Swag.require(text.indexOf("<path") != Swag.U64.Max)
    Swag.require(text.indexOf("<path", text.indexOf("<path") + 1) == Swag.U64.Max)
    Swag.require(text.indexOf("M0 0", text.indexOf("M0 0") + 1) != Swag.U64.Max)
}

// An empty document still writes a well-formed root element.
#test
{
    let text = Svg.Document.create(4, 4).toString()
    Swag.require(text.contains("<svg "))
    Swag.require(not text.contains("<path"))
}

// SVG geometry and opacity keep a decimal point in every locale.
#test
{
    var doc = Svg.Document.create(8.5, 6.5)
    var path: LinePath
    path.start(-1, 1.5)
    path.lineTo(7.25, 1.5)
    path.lineTo(7.25, 5.5)
    path.lineTo(-1, 5.5)
    path.close()

    doc.setBackground(Color.fromArgb(64_u8, 20_u8, 60_u8, 100_u8))
    doc.addPath(path, Color.fromArgb(128_u8, 220_u8, 50_u8, 90_u8))

    var text: String
    scope
    {
        let culture = Globalization.currentCulture()
        let previous = culture.numberFormat
        defer culture.numberFormat = previous
        culture.numberFormat = Globalization.CultureInfo.fromName("fr-FR").numberFormat
        culture.numberFormat.negativeSign = '~'

        Swag.require(culture.numberFormat.decimalSeparator == ',')
        text = doc.toString()
    }

    const Reference = """
        <svg viewBox="0 0 8.5 6.5" width="8.5" height="6.5">
        <rect width="8.5" height="6.5" fill="#143C64" fill-opacity="0.251"/>
        <path fill="#DC325A" fill-opacity="0.502" d="M-1 1.5L7.25 1.5L7.25 5.5L-1 5.5Z"/>
        </svg>
        """
    let drawing   = expect Svg.Drawing.parse(text.toString())
    let reference = expect Svg.Drawing.parse(Reference)
    let image     = drawing.rasterize(17, 13, 1)
    let expected  = reference.rasterize(17, 13, 1)

    Swag.require(image.isValid() and expected.isValid())
    Swag.require(image.pixelColor(0, 0).a > 0)
    Swag.require(image.pixelColor(7, 5).a > image.pixelColor(0, 0).a)
    let cmp = Memory.compare(image.pixels.storage(), expected.pixels.storage(), expected.byteCount)
    Swag.require(cmp == 0)
}

// Zeros at the end of a large integral coordinate are part of the value.
#test
{
    var doc = Svg.Document.create(1_000_000_000, 1_000_000_000)
    var path: LinePath
    path.start(-1_000_000_000, 250_000_000)
    path.lineTo(1_000_000_000, 250_000_000)
    path.lineTo(1_000_000_000, 750_000_000)
    path.lineTo(-1_000_000_000, 750_000_000)
    path.close()

    let color = Color.fromRgb(32, 104, 176)
    doc.addPath(path, color)
    let text = doc.toString()
    Swag.require(text.contains("viewBox=\"0 0 1000000000 1000000000\""))
    Swag.require(text.contains("M-1000000000 250000000L1000000000 250000000"))

    let drawing = expect Svg.Drawing.parse(text.toString())
    let image   = drawing.rasterize(16, 16, 1)
    Swag.require(image.isValid())
    Swag.require(image.pixelColor(14, 2).a == 0)
    Swag.require(image.pixelColor(14, 8).argb == color.argb)
}

// A smoothed curve is exported as a filled contour through its flattened points.
#test
{
    var path: LinePath
    path.start(3, 7)
    path.curveTo(7, 3)
    path.curveTo(13, 7)
    path.lineTo(13, 13)
    path.lineTo(3, 13)
    path.close()

    let color = Color.fromRgb(64, 120, 200)
    var doc   = Svg.Document.create(16, 16)
    doc.addPath(path, color)
    let text = doc.toString()
    Swag.require(text.contains("d=\"M3 7L"))

    let drawing = expect Svg.Drawing.parse(text.toString())
    let image   = drawing.rasterize(16, 16, 1)
    Swag.require(image.isValid())
    Swag.require(image.pixelColor(8, 8).argb == color.argb)
    Swag.require(image.pixelColor(1, 1).a == 0)
}
