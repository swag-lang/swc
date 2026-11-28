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
    }

    // What the document is made of. A shape is complete once it is added, so the elements
    // are assembled as they arrive; use 'addPath', 'setBackground', and 'setTitle'.
    body:          String     // Shape elements, in paint order.
    background:    Color      // Ground painted before the shapes.
    hasBackground: bool       // Whether a ground was requested.
    title:         String     // Accessible name of the document.
}

impl Document
{
    // Creates an empty document with positive dimensions.
    func create(width, height: f32)->Document
    {
        Swag.assert(width > 0 and height > 0, "invalid dimensions")

        var result: #returntype
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
        var data: ConcatBuffer
        for path in paths.paths
        {
            appendContour(&data, path, quality)
        }

        .addShape(&data, color, rule)
    }

    // Appends one filled shape built from a single contour.
    mtd addPath(path: LinePath, color: Color, rule = FillRule.NonZero, quality = PaintQuality.Normal)
    {
        var data: ConcatBuffer
        appendContour(&data, &path, quality)
        .addShape(&data, color, rule)
    }

    // Assembles one shape element from its already formatted commands.
    private mtd addShape(data: const *ConcatBuffer, color: Color, rule: FillRule)
    {
        if data.count() == 0
        {
            return
        }

        .body.appendFormat("<path fill=\"%\"", hex(color))
        if rule == .EvenOdd
        {
            .body += " fill-rule=\"evenodd\""
        }

        if color.a != 255
        {
            .body.appendFormat(" fill-opacity=\"%\"", opacityText(color.a))
        }

        .body += " d=\""
        for bucket in data
        {
            .body += Swag.makeString(bucket.data, bucket.count)
        }

        .body += "\"/>\n"
    }

    // Returns only the shape elements, without the enclosing `svg` element.
    //
    // Use this to embed the document's shapes in a larger hand-assembled file, for
    // example as one cell of an icon atlas grid.
    mtd const bodyText()->String
    {
        var result: #returntype = .body
        return result
    }

    // Returns the document as SVG text.
    mtd const toString()->String
    {
        var result: #returntype
        let width  = coordinateText(.width)
        let height = coordinateText(.height)
        result.appendFormat("<svg xmlns=\"http://www.w3.org/2000/svg\" viewBox=\"0 0 % %\" width=\"%\" height=\"%\"",
                            width, height, width, height)
        if .title.isEmpty()
        {
            result += " aria-hidden=\"true\">\n"
        }
        else
        {
            result.appendFormat(" role=\"img\" aria-label=\"%\">\n", escapeXml(.title.toString()))
        }

        if .hasBackground
        {
            result.appendFormat("<rect width=\"%\" height=\"%\" fill=\"%\"", width, height, hex(.background))
            if .background.a != 255
            {
                result.appendFormat(" fill-opacity=\"%\"", opacityText(.background.a))
            }

            result += "/>\n"
        }

        result += .body.toString()
        result += "</svg>\n"
        return result
    }

    // Writes the document as SVG text to `fileName`, replacing any existing file.
    //
    // File errors are reported through `fail`.
    mtd const save(fileName: string) fail
    {
        let text = .toString()
        try File.writeAllText(fileName, text.toString())
    }
}

// Appends the SVG commands of one path.
private func appendContour(data: *ConcatBuffer, path: const *LinePath, quality: PaintQuality)
{
    if usesExactCommands(path)
    {
        appendExactContour(data, path)
    }
    else
    {
        appendFlattenedContour(data, path, quality)
    }
}

// Reports whether every segment of the path has a direct SVG command.
private func usesExactCommands(path: const *LinePath)->bool
{
    for &element in path.elements
    {
        if element.type == .Arc or element.type == .Curve
        {
            return false
        }
    }

    return true
}

private func appendExactContour(data: *ConcatBuffer, path: const *LinePath)
{
    data.addNative('M'_u8)
    appendPoint(data, path.startPoint)
    for &element in path.elements
    {
        switch element.type
        {
        case .Line:
            data.addNative('L'_u8)
            appendPoint(data, element.position)

        case .Bezier1:
            data.addNative('Q'_u8)
            appendPoint(data, element.p1)
            data.addNative(' '_u8)
            appendPoint(data, element.position)

        case .Bezier2:
            data.addNative('C'_u8)
            appendPoint(data, element.p1)
            data.addNative(' '_u8)
            appendPoint(data, element.p2)
            data.addNative(' '_u8)
            appendPoint(data, element.position)

        default:
            break
        }
    }

    if path.isClosed
    {
        data.addNative('Z'_u8)
    }
}

private func appendFlattenedContour(data: *ConcatBuffer, path: const *LinePath, quality: PaintQuality)
{
    var copy = path[]
    copy.flatten(quality)
    let polygon = copy.flattenedPolygon()
    if polygon.points.count < 2
    {
        return
    }

    for &point, i in polygon.points
    {
        data.addNative(i == 0 ? 'M'_u8 : 'L'_u8)
        appendPoint(data, point[])
    }

    data.addNative('Z'_u8)
}

private func appendPoint(data: *ConcatBuffer, point: Vector2)
{
    appendCoordinate(data, point.x)
    data.addNative(' '_u8)
    appendCoordinate(data, point.y)
}

// SVG coordinates always use a decimal point. The shortest fixed spelling preserves
// integral zeros as well as the digits needed to reconstruct a fractional value.
private func appendCoordinate(data: *ConcatBuffer, value: f32)
{
    if value == Math.trunc(value) and Math.abs(value) < 1e9
    {
        let integer = cast(s64, value)
        if integer < 0
        {
            data.addNative('-'_u8)
        }

        StrConv.convertInt(data, cast(u64, Math.abs(integer)), {})
        return
    }

    StrConv.Dtoa.appendInvariant(data, value, 'f'_u8, -1, false)
}

private func coordinateText(value: f32)->String
{
    var data: ConcatBuffer
    appendCoordinate(&data, value)
    return data.toString()
}

private func opacityText(alpha: u8)->String
{
    let value = cast(f32, alpha) / 255.0
    var data: ConcatBuffer
    StrConv.Dtoa.appendInvariant(&data, value, 'f'_u8, 3, false)
    return data.toString()
}

private func hex(color: Color)->String => Format.toString("#%{X02}%{X02}%{X02}", color.r, color.g, color.b)

private func escapeXml(value: string)->String
{
    var result: #returntype
    for c in value
    {
        switch c
        {
        case '&'_u8:  result += "&amp;"
        case '<'_u8:  result += "&lt;"
        case '>'_u8:  result += "&gt;"
        case '"'_u8:  result += "&quot;"
        case '\''_u8: result += "&apos;"
        default:      result += c
        }
    }

    return result
}
