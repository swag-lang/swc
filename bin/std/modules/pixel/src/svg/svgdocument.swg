#global public
#global namespace Svg

using Core, Core.Errors, Core.Math

// Decides which points a set of contours encloses.
enum FillRule
{
    NonZero     // Inside where the signed crossing count differs from zero; overlapping contours merge.
    EvenOdd     // Inside where the crossing count is odd; overlapping contours punch holes.
}

// Builds a vector document and writes it as SVG text.
//
// The document holds filled paths in the coordinate space it was created with; nothing is
// rasterized, so the result stays sharp at any size. Straight and Bézier segments are written
// as their exact SVG commands, while a path holding an arc or a smoothed curve is written from
// its flattened contour, so the file always describes the same shape the rasterizer draws.
//
// ## Example
//
// ```swag
// var path: LinePath
// path.start(8, 8)
// path.lineTo(56, 8)
// path.lineTo(32, 56)
// path.close()
//
// var doc = Svg.Document.create(64, 64)
// doc.setBackground(Color.fromRgb(11, 11, 13))
// doc.addPath(path, Color.fromRgb(247, 249, 0))
// try doc.save("mark.svg")
// ```
struct Document
{
    public
    {
        width:  f32     // Width of the view box, in user units.
        height: f32     // Height of the view box, in user units.

        // What the document is made of. A shape is complete once it is added, so the elements
        // are assembled as they arrive; use 'addPath', 'setBackground', and 'setTitle'.
        internal
        {
            body:          String     // Shape elements, in paint order.
            background:    Color      // Ground painted before the shapes.
            hasBackground: bool       // Whether a ground was requested.
            title:         String     // Accessible name of the document.
        }
    }
}

impl Document
{
    // Creates an empty document with positive dimensions.
    func create(width, height: f32)->Document
    {
        Debug.assert(width > 0 and height > 0, "invalid dimensions")

        var result: retval
        result.width  = width
        result.height = height
        return result
    }

    // Paints a solid ground over the whole view box, before every shape.
    mtd setBackground(color: Color)
    {
        .background    = color
        .hasBackground = true
    }

    // Sets the accessible name reported by the document.
    //
    // A reader that cannot see the image is told this instead. Without one, the document
    // declares itself decorative.
    mtd setTitle(title: string)
    {
        .title = title
    }

    // Appends one filled shape built from every contour of `paths`.
    mtd addPath(paths: LinePathList, color: Color, rule = FillRule.NonZero, quality = PaintQuality.Normal)
    {
        var data: String
        for path in paths.paths do
            appendContour(&data, path, quality)
        .addShape(data.toString(), color, rule)
    }

    // Appends one filled shape built from a single contour.
    mtd addPath(path: LinePath, color: Color, rule = FillRule.NonZero, quality = PaintQuality.Normal)
    {
        var data: String
        appendContour(&data, &path, quality)
        .addShape(data.toString(), color, rule)
    }

    // Assembles one shape element from its already formatted commands.
    private mtd addShape(data: string, color: Color, rule: FillRule)
    {
        if @countof(data) == 0 do
            return

        .body.appendFormat("<path fill=\"%\"", hex(color))
        if rule == .EvenOdd do
            .body += " fill-rule=\"evenodd\""
        if color.a != 255 do
            .body.appendFormat(" fill-opacity=\"%{f3}\"", cast(f32) color.a / 255.0)
        .body.appendFormat(" d=\"%\"/>\n", data)
    }

    // Returns only the shape elements, without the enclosing `svg` element.
    //
    // Use this to embed the document's shapes in a larger hand-assembled file, for
    // example as one cell of an icon atlas grid.
    mtd const bodyText()->String
    {
        var result: retval = .body
        return result
    }

    // Returns the document as SVG text.
    mtd const toString()->String
    {
        var result: retval
        result.appendFormat("<svg xmlns=\"http://www.w3.org/2000/svg\" viewBox=\"0 0 % %\" width=\"%\" height=\"%\"", num(.width), num(.height), num(.width), num(.height))
        if .title.isEmpty() do
            result += " aria-hidden=\"true\">\n"
        else do
            result.appendFormat(" role=\"img\" aria-label=\"%\">\n", escapeXml(.title.toString()))

        if .hasBackground do
            result.appendFormat("<rect width=\"%\" height=\"%\" fill=\"%\"/>\n", num(.width), num(.height), hex(.background))

        result += .body.toString()
        result += "</svg>\n"
        return result
    }

    // Writes the document next to the other publication assets.
    mtd const save(fileName: string) fail
    {
        let text = .toString()
        discard try File.writeAllBytes(fileName, cast(const [..] u8) text)
    }
}

// Appends the SVG commands of one path.
private func appendContour(data: *String, path: const *LinePath, quality: PaintQuality)
{
    if usesExactCommands(path) do
        appendExactContour(data, path)
    else do
        appendFlattenedContour(data, path, quality)
}

// Reports whether every segment of the path has a direct SVG command.
private func usesExactCommands(path: const *LinePath)->bool
{
    for &element in path.elements
    {
        if element.type == .Arc or element.type == .Curve do
            return false
    }

    return true
}

private func appendExactContour(data: *String, path: const *LinePath)
{
    data.appendFormat("M% %", num(path.startPoint.x), num(path.startPoint.y))
    for &element in path.elements
    {
        switch element.type
        {
        case .Line:    data.appendFormat("L% %", num(element.position.x), num(element.position.y))
        case .Bezier1: data.appendFormat("Q% % % %", num(element.p1.x), num(element.p1.y), num(element.position.x), num(element.position.y))
        case .Bezier2: data.appendFormat("C% % % % % %", num(element.p1.x), num(element.p1.y), num(element.p2.x), num(element.p2.y), num(element.position.x), num(element.position.y))
        default:       break
        }
    }

    if path.isClosed do
        data[] += "Z"
}

private func appendFlattenedContour(data: *String, path: const *LinePath, quality: PaintQuality)
{
    var copy = path[]
    copy.flatten(quality)
    let polygon = copy.flattenedPolygon()
    if polygon.points.count < 2 do
        return

    for &point, i in polygon.points do
        data.appendFormat("%% %", i == 0 ? "M" : "L", num(point.x), num(point.y))
    data[] += "Z"
}

// Formats a coordinate with the shortest exact spelling: a whole number loses its fraction and
// a fraction loses its trailing zeros, which keeps a generated document readable and small.
private func num(value: f32)->String
{
    var result: retval
    if value == Math.trunc(value) and Math.abs(value) < 1e9
    {
        result.appendFormat("%", cast(s64) value)
        return result
    }

    result.appendFormat("%{f3}", value)
    while result.endsWith("0") do
        result.removeBack(1)
    if result.endsWith(".") do
        result.removeBack(1)
    return result
}

private func hex(color: Color)->String
{
    return Format.toString("#%{X02}%{X02}%{X02}", color.r, color.g, color.b)
}

private func escapeXml(value: string)->String
{
    var result: retval
    for c in value
    {
        switch c
        {
        case '&'u8:  result += "&amp;"
        case '<'u8:  result += "&lt;"
        case '>'u8:  result += "&gt;"
        case '"'u8:  result += "&quot;"
        case '\''u8: result += "&apos;"
        default:     result += c
        }
    }

    return result
}
