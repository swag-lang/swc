using Core, Core.Errors, Core.Math, Pixel

// Everything a content stream can set before it paints.
//
// `q` and `Q` push and pop a whole value of this type, which is why it owns its color
// spaces rather than pointing at them.
private struct GraphicsState
{
    ctm:         Transform2 = Transform2.Identity
    fillColor:   Color      = Color.fromArgb(Argb.Black)
    strokeColor: Color      = Color.fromArgb(Argb.Black)
    strokeWidth: f32        = 1
    strokeStyle: PathStrokeStyle
    fillSpace:   ImageSpace
    strokeSpace: ImageSpace

    fontName:    String
    fontSize:    f32 = 12
    charSpacing: f32
    wordSpacing: f32
    horizScale:  f32 = 1
    leading:     f32
    rise:        f32
    renderMode:  s64

    textMatrix: Transform2 = Transform2.Identity
    lineMatrix: Transform2 = Transform2.Identity

    // Region every mark is confined to, in the page's own top-left coordinates.
    //
    // A clip is bounded by its enclosing rectangle, which is exact for the axis-aligned
    // rectangles clip paths and form bounding boxes are almost always written as, and
    // conservative otherwise: it can leave a mark that a shaped clip would have removed,
    // and never removes one the page meant to show.
    clip:    Math.Rectangle
    hasClip: bool
}

impl GraphicsState
{
    // Narrows the clip to `rect`, which is what nesting a clip inside another means.
    mtd intersectClip(rect: Math.Rectangle)
    {
        if !.hasClip
        {
            .clip    = rect
            .hasClip = true
            return
        }

        .clip.intersect(rect)
    }
}

// Returns the page-space rectangle enclosing a form's bounding box under `state`.
private func transformedBounds(state: const *GraphicsState, page: const *Page, x0, y0, x1, y1: f32)->Math.Rectangle
{
    let corners: [4] Vector2 = [
        transformPoint(state, page, x0, y0),
        transformPoint(state, page, x1, y0),
        transformPoint(state, page, x1, y1),
        transformPoint(state, page, x0, y1)]

    var minX = corners[0].x
    var minY = corners[0].y
    var maxX = corners[0].x
    var maxY = corners[0].y
    for corner in corners
    {
        minX = Math.min(minX, corner.x)
        minY = Math.min(minY, corner.y)
        maxX = Math.max(maxX, corner.x)
        maxY = Math.max(maxY, corner.y)
    }

    return {minX, minY, maxX - minX, maxY - minY}
}

private func transformPoint(state: const *GraphicsState, page: const *Page, x, y: f32)->Vector2
{
    let point = state.ctm.transformPoint({x, y})
    return {point.x, page.height - point.y}
}

private func operandNumber(parser: const *PdfParser, operands: Array'u32, index: u64)->f32
{
    if index >= @countof(operands) do
        return 0
    let value = parser.number(operands[index])
    return value < 0 ? -cast(f32) (-value) : cast(f32) value
}

private func nodeNumber(parser: const *PdfParser, nodeId: u32)->f32
{
    let value = parser.number(nodeId)
    return value < 0 ? -cast(f32) (-value) : cast(f32) value
}

// Collects the trailing numeric operands of a color operator.
private func colorComponents(parser: const *PdfParser, operands: Array'u32, target: [..] f32)->u32
{
    var count = 0'u64
    while count < @countof(operands) and count < @countof(target)
    {
        let id = parser.resolve(operands[@countof(operands) - count - 1])
        if id == InvalidNode or (parser.nodes[id].kind != .Integer and parser.nodes[id].kind != .Real) do
            break
        count += 1
    }

    for i in count do
        target[i] = cast(f32) parser.number(operands[@countof(operands) - count + i])
    return cast(u32) count
}

private func currentPath(path: *LinePathList, current: *#null *LinePath, start: Vector2)->*LinePath
{
    let result = path.newPath()
    result.start(start.x, start.y)
    current[] = result
    return result
}

// Narrows the graphics state to the path a `W` operator marked as the next clip.
private func applyPendingClip(state: *GraphicsState, path: const *LinePathList, pending: *bool)
{
    if !pending[] do
        return
    pending[] = false
    if !path.count() do
        return

    state.intersectClip(path.controlBounds())
}

private func appendPathItem(page: *Page, path: *LinePathList, state: const *GraphicsState, fill, stroke, close: bool, evenOdd = false)
{
    if !path.count() do
        return
    if close
    {
        let paths = path.toSlice()
        if @countof(paths) do
            paths[@countof(paths) - 1].close()
    }

    var item = Item.createPath()
    item.path        = #move path[]
    item.hasFill     = fill
    item.hasStroke   = stroke
    item.evenOddFill = evenOdd
    item.fillColor   = state.fillColor
    item.strokeColor = state.strokeColor
    item.strokeWidth = state.strokeWidth
    item.strokeStyle = state.strokeStyle
    item.clip        = state.clip
    item.hasClip     = state.hasClip
    page.appendItem(#move item)
    @init(path, 1)
}

private func fontIndex(parser: const *PdfParser, page: const *Page, resourcesId: u32, name: string)->u32
{
    let fonts = parser.dict(resourcesId, "Font")
    let raw   = parser.dictRaw(fonts, name)
    let id    = parser.resolve(raw)
    if id != InvalidNode
    {
        for font, index in page.fonts where font.objectId == id do
            return cast(u32) index
    }

    for font, index in page.fonts where font.name == name do
        return cast(u32) index
    return Swag.U32.Max
}

// Moves the text position along the baseline of the current line.
private func advanceText(state: *GraphicsState, amount: f32)
{
    var moved = Transform2.createTranslation(amount, 0)
    moved.multiply(state.textMatrix)
    state.textMatrix = moved
}

// Starts a new line relative to the current one, which is what `Td`, `TD`, `T*` all do.
private func moveTextLine(state: *GraphicsState, x, y: f32)
{
    var moved = Transform2.createTranslation(x, y)
    moved.multiply(state.lineMatrix)
    state.lineMatrix = moved
    state.textMatrix = moved
}

private func appendText(parser: const *PdfParser, page: *Page, resourcesId: u32, state: *GraphicsState, bytes: string)
{
    let index = fontIndex(parser, page, resourcesId, state.fontName.toString())
    let font  = index < page.fonts.count ? &page.fonts[index] : null

    var advance = 0.0'f32
    if font do
        advance = font.runAdvance(bytes, state.fontSize, state.charSpacing, state.wordSpacing)
    else do
        advance = cast(f32) @countof(bytes) * state.fontSize * 0.5

    // Render modes 3 and 7 add no marks; the text still moves the position, which is how
    // an invisible layer over a scanned page stays aligned with what it transcribes.
    let invisible = state.renderMode == 3 or state.renderMode == 7
    let text      = font ? font.decodeText(bytes) : Text.decode(cast(const [..] u8) bytes, .Windows1252)
    if !invisible and !text.isEmpty()
    {
        var combined = Transform2{state.horizScale, 0, 0, 1, 0, state.rise}
        combined.multiply(state.textMatrix)
        combined.multiply(state.ctm)

        let baseline  = combined.translation()
        let m21       = -combined.m21
        let m22       = combined.m22
        let baselineY = page.height - baseline.y

        var item = Item.createText()
        item.text = #move text
        if font
        {
            item.textCodes    = font.decodeCodes(bytes)
            item.textAdvances = font.codeAdvances(bytes, state.fontSize, state.charSpacing, state.wordSpacing)
        }

        item.fontSize  = state.fontSize
        item.fillColor = state.fillColor
        item.fontIndex = index
        item.transform = Transform2{combined.m11, -combined.m12, m21, m22, baseline.x - state.fontSize * m21, baselineY - state.fontSize * m22}
        item.clip      = state.clip
        item.hasClip   = state.hasClip
        if font and font.hasStandard do
            item.standardFont = font.standard
        page.appendItem(#move item)
    }

    advanceText(state, advance * state.horizScale)
}

private func appendImageItem(parser: *PdfParser, page: *Page, state: const *GraphicsState, imageId, resourcesId: u32) fail
{
    var item = Item.createImage()
    item.image = try decodeImage(parser, imageId, resourcesId, state.fillColor)
    let top    = transformPoint(state, page, 0, 1)
    let right  = transformPoint(state, page, 1, 1)
    let bottom = transformPoint(state, page, 0, 0)
    item.transform = Transform2{right.x - top.x, right.y - top.y, bottom.x - top.x, bottom.y - top.y, top.x, top.y}
    item.clip      = state.clip
    item.hasClip   = state.hasClip
    page.appendItem(#move item)
}

private func appendXObject(parser: *PdfParser, page: *Page, resourcesId: u32, state: const *GraphicsState, name: string, depth: u32) fail
{
    let xobjects = parser.dict(resourcesId, "XObject")
    if xobjects == InvalidNode do
        return
    let raw = parser.dictRaw(xobjects, name)
    let id  = parser.resolve(raw)
    if id == InvalidNode do
        return

    let subtype = parser.name(parser.dict(id, "Subtype"))
    if subtype == "Form"
    {
        if depth >= 32 do
            fail UnsupportedFormatError{"PDF form nesting exceeds the supported depth"}

        var formState = state[]
        let matrixId  = parser.dict(id, "Matrix")
        if matrixId != InvalidNode and parser.nodes[matrixId].kind == .Array and parser.nodes[matrixId].values.count >= 6
        {
            let values = parser.nodes[matrixId].values
            var matrix = Transform2{nodeNumber(parser, values[0]), nodeNumber(parser, values[1]), nodeNumber(parser, values[2]), nodeNumber(parser, values[3]), nodeNumber(parser, values[4]), nodeNumber(parser, values[5])}
            matrix.multiply(formState.ctm)
            formState.ctm = matrix
        }

        // A form's bounding box is part of what it means, not a hint: the form paints
        // nothing outside it, and content built to be trimmed by it would otherwise reach
        // the page as stray marks.
        let boxId = parser.dict(id, "BBox")
        if boxId != InvalidNode and parser.nodes[boxId].kind == .Array and parser.nodes[boxId].values.count >= 4
        {
            let box = parser.nodes[boxId].values
            let x0  = nodeNumber(parser, box[0])
            let y0  = nodeNumber(parser, box[1])
            let x1  = nodeNumber(parser, box[2])
            let y1  = nodeNumber(parser, box[3])
            formState.intersectClip(transformedBounds(&formState, page, x0, y0, x1, y1))
        }

        let ownResources = parser.dict(id, "Resources")
        let resources    = ownResources != InvalidNode ? ownResources : resourcesId
        if resources != InvalidNode do
            try decodeFonts(parser, page, resources)
        let bytes = try parser.decodeStream(id)
        try parseContent(parser, page, resources, bytes.toSlice(), &formState, depth + 1)
        return
    }

    if subtype != "Image" do
        return
    try appendImageItem(parser, page, state, id, resourcesId)
}

// Expands the abbreviated key an inline image dictionary uses.
private func inlineImageKey(key: string)->string
{
    switch key
    {
    case "BPC": return "BitsPerComponent"
    case "CS":  return "ColorSpace"
    case "D":   return "Decode"
    case "DP":  return "DecodeParms"
    case "F":   return "Filter"
    case "H":   return "Height"
    case "IM":  return "ImageMask"
    case "I":   return "Interpolate"
    case "W":   return "Width"
    case "L":   return "Length"
    }

    return key
}

// Reads one `BI ... ID ... EI` inline image and paints it.
//
// The dictionary is rebuilt inside the document parser so a named color space still
// resolves through the page resources, and so the image decoder sees one representation.
private func appendInlineImage(parser: *PdfParser, content: *PdfParser, page: *Page, resourcesId: u32, state: const *GraphicsState) fail
{
    var node: Node
    node.kind = .Dictionary
    var imported: HashTable'(u32, u32)
    for
    {
        content.skip()
        if content.pos >= @countof(content.bytes) do
            fail InvalidFormatError{"PDF inline image has no data marker"}
        if content.consumeWord("ID") do
            break
        if content.bytes[content.pos] != '/' do
            fail InvalidFormatError{"PDF inline image dictionary needs a name key"}
        let keyNode     = try content.parseName()
        var key: String = inlineImageKey(content.nodes[keyNode].text.toString())
        let value       = try content.parseValue()
        node.entries[key] = parser.importNode(content, value, &imported)
    }

    // Exactly one whitespace byte separates ID from the samples.
    if content.pos < @countof(content.bytes) and isWhite(content.bytes[content.pos]) do
        content.pos += 1
    let start = content.pos

    let imageId = parser.addNode(#move node)
    var length  = parser.integer(parser.dict(imageId, "Length"), -1)
    if length < 0 and !parser.streamFilters(imageId).count
    {
        // Unfiltered samples have a length the dictionary already implies.
        let width   = parser.integer(parser.dict(imageId, "Width"))
        let height  = parser.integer(parser.dict(imageId, "Height"))
        let bits    = parser.boolean(parser.dict(imageId, "ImageMask")) ? 1's64 : parser.integer(parser.dict(imageId, "BitsPerComponent"), 8)
        let space   = try resolveImageSpace(parser, parser.dictRaw(imageId, "ColorSpace"), resourcesId, 0)
        let rowBits = cast(s64) space.components * bits * width
        if width > 0 and height > 0 and bits > 0 do
            length = (rowBits + 7) / 8 * height
    }

    var end = Swag.U64.Max
    if length >= 0 and start + cast(u64) length <= @countof(content.bytes) do
        end = start + cast(u64) length
    else do
        end = findInlineImageEnd(content.bytes, start)
    if end == Swag.U64.Max do
        fail InvalidFormatError{"PDF inline image has no EI marker"}

    parser.nodes[imageId].stream = @mkslice(@dataof(content.bytes) + start, end - start)
    content.pos = end
    discard content.consumeWord("EI")
    try appendImageItem(parser, page, state, imageId, resourcesId)
}

// Finds the `EI` that closes an inline image whose length cannot be computed.
private func findInlineImageEnd(bytes: const [..] u8, start: u64)->u64
{
    var pos = start
    while pos + 2 <= @countof(bytes)
    {
        if bytes[pos] == 'E' and bytes[pos + 1] == 'I' and pos > start and isWhite(bytes[pos - 1])
        {
            if pos + 2 == @countof(bytes) or isDelimiter(bytes[pos + 2]) do
                return pos - 1
        }

        pos += 1
    }

    return Swag.U64.Max
}

// Reads the parts of an ExtGState that change how later operators paint.
private func applyExtGState(parser: const *PdfParser, page: const *Page, resourcesId: u32, state: *GraphicsState, name: string)
{
    let states = parser.dict(resourcesId, "ExtGState")
    let entry  = parser.dict(states, name)
    if entry == InvalidNode do
        return

    let lineWidth = parser.dict(entry, "LW")
    if lineWidth != InvalidNode do
        state.strokeWidth = nodeNumber(parser, lineWidth)

    let font = parser.dict(entry, "Font")
    if font != InvalidNode and parser.nodes[font].kind == .Array and parser.nodes[font].values.count >= 2
    {
        let fontId = parser.resolve(parser.nodes[font].values[0])
        for resource in page.fonts where resource.objectId == fontId
        {
            state.fontName = resource.name
            break
        }

        state.fontSize = nodeNumber(parser, parser.nodes[font].values[1])
    }
}

private func parseContent(parser: *PdfParser, page: *Page, resourcesId: u32, bytes: const [..] u8, initialState: #null const *GraphicsState = null, depth = 0'u32) fail
{
    var content = PdfParser{bytes: bytes}
    var operands: Array'u32
    var state   = initialState ? initialState![] : GraphicsState{}
    var stack:    Array'GraphicsState
    var path:     LinePathList
    var current:  #null *LinePath

    // A `W` operator names the path under construction as the next clip, and the painting
    // operator that ends the path is what puts it into effect.
    var pendingClip: bool
    var values:      [8] f32

    while content.pos < @countof(bytes)
    {
        content.skip()
        if content.pos >= @countof(bytes) do
            break
        let c = bytes[content.pos]
        if c == '/' or c == '(' or c == '[' or c == '<' or isDigit(c) or c == '+' or c == '-' or c == '.'
        {
            operands.add(try content.parseValue())
            continue
        }

        let start = content.pos
        while content.pos < @countof(bytes) and !isDelimiter(bytes[content.pos]) do
            content.pos += 1
        if content.pos == start
        {
            content.pos += 1
            continue
        }

        let op = cast(string) @mkslice(@dataof(bytes) + start, content.pos - start)
        switch op
        {
        case "q":
            stack.add(state)

        case "Q":
            if stack.count do
                state = stack.popBack()

        case "cm":
            if operands.count >= 6
            {
                let n      = operands.count - 6
                let a      = operandNumber(&content, operands, n)
                let b      = operandNumber(&content, operands, n + 1)
                let c      = operandNumber(&content, operands, n + 2)
                let d      = operandNumber(&content, operands, n + 3)
                let e      = operandNumber(&content, operands, n + 4)
                let f      = operandNumber(&content, operands, n + 5)
                var matrix = Transform2{a, b, c, d, e, f}
                matrix.multiply(state.ctm)
                state.ctm = matrix
            }

        case "w":
            if operands.count
            {
                let width = operandNumber(&content, operands, operands.count - 1)
                if width < 0 or !Math.isFinite(width) do
                    fail InvalidFormatError{"PDF line width needs a non-negative finite number"}
                state.strokeWidth = width
            }

        case "J":
            if operands.count
            {
                let valueId = content.resolve(operands.back())
                if valueId == InvalidNode or content.nodes[valueId].kind != .Integer do
                    fail InvalidFormatError{"PDF line cap needs an integer from 0 to 2"}
                switch content.nodes[valueId].integer
                {
                case 0:  state.strokeStyle.cap = .Butt
                case 1:  state.strokeStyle.cap = .Round
                case 2:  state.strokeStyle.cap = .Square
                default: fail InvalidFormatError{"PDF line cap accepts values from 0 to 2"}
                }
            }

        case "j":
            if operands.count
            {
                let valueId = content.resolve(operands.back())
                if valueId == InvalidNode or content.nodes[valueId].kind != .Integer do
                    fail InvalidFormatError{"PDF line join needs an integer from 0 to 2"}
                switch content.nodes[valueId].integer
                {
                case 0:  state.strokeStyle.join = .Miter
                case 1:  state.strokeStyle.join = .Round
                case 2:  state.strokeStyle.join = .Bevel
                default: fail InvalidFormatError{"PDF line join accepts values from 0 to 2"}
                }
            }

        case "M":
            if operands.count
            {
                let limit = operandNumber(&content, operands, operands.count - 1)
                if limit < 1 or !Math.isFinite(limit) do
                    fail InvalidFormatError{"PDF miter limit needs a finite number of at least 1"}
                state.strokeStyle.miterLimit = limit
            }

        case "d":
            if operands.count >= 2
            {
                let arrayId = content.resolve(operands[operands.count - 2])
                let phase   = operandNumber(&content, operands, operands.count - 1)
                if arrayId == InvalidNode or content.nodes[arrayId].kind != .Array do
                    fail InvalidFormatError{"PDF dash pattern needs an array"}
                if !Math.isFinite(phase) do
                    fail InvalidFormatError{"PDF dash phase needs a finite number"}

                var pattern: Array'f32
                var hasPositiveLength = false
                for valueId in content.nodes[arrayId].values
                {
                    let value = nodeNumber(&content, valueId)
                    if value < 0 or !Math.isFinite(value) do
                        fail InvalidFormatError{"PDF dash lengths need non-negative finite numbers"}
                    pattern.add(value)
                    hasPositiveLength = hasPositiveLength or value > 0
                }

                if pattern.count and !hasPositiveLength do
                    fail InvalidFormatError{"PDF dash pattern needs a positive length"}
                if pattern.count & 1
                {
                    let count = pattern.count
                    for i in count do
                        pattern.add(pattern[i])
                }

                state.strokeStyle.dashPattern = #move pattern
                state.strokeStyle.dashPhase   = phase
            }

        case "gs":
            if operands.count do
                applyExtGState(parser, page, resourcesId, &state, content.name(operands.back()))

        case "g":
            if operands.count
            {
                state.fillSpace = deviceSpace(.Gray, 1)
                state.fillColor = grayColor(content.number(operands.back()))
            }

        case "G":
            if operands.count
            {
                state.strokeSpace = deviceSpace(.Gray, 1)
                state.strokeColor = grayColor(content.number(operands.back()))
            }

        case "rg":
            if operands.count >= 3
            {
                state.fillSpace = deviceSpace(.Rgb, 3)
                state.fillColor = rgbColor(content.number(operands[operands.count - 3]), content.number(operands[operands.count - 2]), content.number(operands[operands.count - 1]))
            }

        case "RG":
            if operands.count >= 3
            {
                state.strokeSpace = deviceSpace(.Rgb, 3)
                state.strokeColor = rgbColor(content.number(operands[operands.count - 3]), content.number(operands[operands.count - 2]), content.number(operands[operands.count - 1]))
            }

        case "k":
            if operands.count >= 4
            {
                state.fillSpace = deviceSpace(.Cmyk, 4)
                state.fillColor = cmykColor(content.number(operands[operands.count - 4]), content.number(operands[operands.count - 3]), content.number(operands[operands.count - 2]), content.number(operands[operands.count - 1]))
            }

        case "K":
            if operands.count >= 4
            {
                state.strokeSpace = deviceSpace(.Cmyk, 4)
                state.strokeColor = cmykColor(content.number(operands[operands.count - 4]), content.number(operands[operands.count - 3]), content.number(operands[operands.count - 2]), content.number(operands[operands.count - 1]))
            }

        case "cs", "CS":
            if operands.count
            {
                // The operand is a name parsed by the content scanner, so it is resolved
                // against the page resources rather than through a document node.
                var picked = deviceSpace(.Gray, 1)
                let space  = catch resolveNamedColorSpace(parser, content.name(operands.back()), resourcesId, 0) as spaceError
                if spaceError == null do
                    picked = space
                if op == "cs"
                {
                    state.fillColor = initialSpaceColor(&picked)
                    state.fillSpace = #move picked
                }
                else
                {
                    state.strokeColor = initialSpaceColor(&picked)
                    state.strokeSpace = #move picked
                }
            }

        case "sc", "scn", "SC", "SCN":
            let count = colorComponents(&content, operands, values)
            if count
            {
                let stroke = op == "SC" or op == "SCN"
                let space  = stroke ? &state.strokeSpace : &state.fillSpace
                let color  = spaceColor(space, values[0 until count])
                if stroke do
                    state.strokeColor = color
                else do
                    state.fillColor = color
            }

        case "m":
            if operands.count >= 2 do
                currentPath(&path, &current, transformPoint(&state, page, operandNumber(&content, operands, operands.count - 2), operandNumber(&content, operands, operands.count - 1)))

        case "l":
            if current and operands.count >= 2
            {
                let p = transformPoint(&state, page, operandNumber(&content, operands, operands.count - 2), operandNumber(&content, operands, operands.count - 1))
                current!.lineTo(p.x, p.y)
            }

        case "c":
            if current and operands.count >= 6
            {
                let n  = operands.count - 6
                let c1 = transformPoint(&state, page, operandNumber(&content, operands, n), operandNumber(&content, operands, n + 1))
                let c2 = transformPoint(&state, page, operandNumber(&content, operands, n + 2), operandNumber(&content, operands, n + 3))
                let p  = transformPoint(&state, page, operandNumber(&content, operands, n + 4), operandNumber(&content, operands, n + 5))
                current!.bezierTo(p.x, p.y, c1.x, c1.y, c2.x, c2.y)
            }

        case "v":

            // The first control point of `v` is the current point itself.
            if current and operands.count >= 4
            {
                let n  = operands.count - 4
                let c1 = current!.endPoint
                let c2 = transformPoint(&state, page, operandNumber(&content, operands, n), operandNumber(&content, operands, n + 1))
                let p  = transformPoint(&state, page, operandNumber(&content, operands, n + 2), operandNumber(&content, operands, n + 3))
                current!.bezierTo(p.x, p.y, c1.x, c1.y, c2.x, c2.y)
            }

        case "y":

            // The second control point of `y` is its own end point.
            if current and operands.count >= 4
            {
                let n  = operands.count - 4
                let c1 = transformPoint(&state, page, operandNumber(&content, operands, n), operandNumber(&content, operands, n + 1))
                let p  = transformPoint(&state, page, operandNumber(&content, operands, n + 2), operandNumber(&content, operands, n + 3))
                current!.bezierTo(p.x, p.y, c1.x, c1.y, p.x, p.y)
            }

        case "h":
            if current do
                current!.close()

        case "re":
            if operands.count >= 4
            {
                let n    = operands.count - 4
                let x    = operandNumber(&content, operands, n)
                let y    = operandNumber(&content, operands, n + 1)
                let w    = operandNumber(&content, operands, n + 2)
                let h    = operandNumber(&content, operands, n + 3)
                let p0   = transformPoint(&state, page, x, y)
                let p1   = transformPoint(&state, page, x + w, y)
                let p2   = transformPoint(&state, page, x + w, y + h)
                let p3   = transformPoint(&state, page, x, y + h)
                let rect = currentPath(&path, &current, p0)
                rect.lineTo(p1.x, p1.y)
                rect.lineTo(p2.x, p2.y)
                rect.lineTo(p3.x, p3.y)
                rect.close()
            }

        case "W", "W*":

            // The operator only marks the path as the next clip; the painting operator that
            // follows is what ends the path and puts the clip into effect.
            pendingClip = true

        case "S":
            applyPendingClip(&state, &path, &pendingClip)
            appendPathItem(page, &path, &state, false, true, false)
            current = null

        case "s":
            applyPendingClip(&state, &path, &pendingClip)
            appendPathItem(page, &path, &state, false, true, true)
            current = null

        // A star names the alternating rule, under which two overlapping contours cancel
        // instead of merging; without it a ring drawn as two circles fills solid.
        case "f", "F", "f*":
            applyPendingClip(&state, &path, &pendingClip)
            appendPathItem(page, &path, &state, true, false, false, op == "f*")
            current = null

        case "B", "B*":
            applyPendingClip(&state, &path, &pendingClip)
            appendPathItem(page, &path, &state, true, true, false, op == "B*")
            current = null

        case "b", "b*":
            applyPendingClip(&state, &path, &pendingClip)
            appendPathItem(page, &path, &state, true, true, true, op == "b*")
            current = null

        case "n":
            applyPendingClip(&state, &path, &pendingClip)
            path.clear()
            current = null

        case "BT":
            state.textMatrix = Transform2.Identity
            state.lineMatrix = Transform2.Identity

        case "Tf":
            if operands.count >= 2
            {
                state.fontName = content.name(operands[operands.count - 2])
                state.fontSize = operandNumber(&content, operands, operands.count - 1)
            }

        case "Tc":
            if operands.count do
                state.charSpacing = operandNumber(&content, operands, operands.count - 1)

        case "Tw":
            if operands.count do
                state.wordSpacing = operandNumber(&content, operands, operands.count - 1)

        case "Tz":
            if operands.count do
                state.horizScale = operandNumber(&content, operands, operands.count - 1) / 100.0

        case "TL":
            if operands.count do
                state.leading = operandNumber(&content, operands, operands.count - 1)

        case "Ts":
            if operands.count do
                state.rise = operandNumber(&content, operands, operands.count - 1)

        case "Tr":
            if operands.count do
                state.renderMode = content.integer(operands.back())

        case "Tm":
            if operands.count >= 6
            {
                let n = operands.count - 6
                state.textMatrix = Transform2{operandNumber(&content, operands, n), operandNumber(&content, operands, n + 1), operandNumber(&content, operands, n + 2), operandNumber(&content, operands, n + 3), operandNumber(&content, operands, n + 4), operandNumber(&content, operands, n + 5)}
                state.lineMatrix = state.textMatrix
            }

        case "Td":
            if operands.count >= 2 do
                moveTextLine(&state, operandNumber(&content, operands, operands.count - 2), operandNumber(&content, operands, operands.count - 1))

        case "TD":
            if operands.count >= 2
            {
                let y = operandNumber(&content, operands, operands.count - 1)
                state.leading = -y
                moveTextLine(&state, operandNumber(&content, operands, operands.count - 2), y)
            }

        case "T*":
            moveTextLine(&state, 0, -state.leading)

        case "Tj":
            if operands.count do
                appendText(parser, page, resourcesId, &state, content.stringValue(operands.back()))

        case "'":
            if operands.count
            {
                moveTextLine(&state, 0, -state.leading)
                appendText(parser, page, resourcesId, &state, content.stringValue(operands.back()))
            }

        case "\"":
            if operands.count >= 3
            {
                state.wordSpacing = operandNumber(&content, operands, operands.count - 3)
                state.charSpacing = operandNumber(&content, operands, operands.count - 2)
                moveTextLine(&state, 0, -state.leading)
                appendText(parser, page, resourcesId, &state, content.stringValue(operands.back()))
            }

        case "TJ":
            if operands.count
            {
                let arrayId = content.resolve(operands.back())
                if arrayId != InvalidNode and content.nodes[arrayId].kind == .Array
                {
                    for value in content.nodes[arrayId].values
                    {
                        let id = content.resolve(value)
                        if id != InvalidNode and content.nodes[id].kind == .String do
                            appendText(parser, page, resourcesId, &state, content.nodes[id].text.toString())
                        elif id != InvalidNode do
                            advanceText(&state, -cast(f32) content.number(id) * state.fontSize * state.horizScale / 1000.0)
                    }
                }
            }

        case "Do":
            if operands.count do
                try appendXObject(parser, page, resourcesId, &state, content.name(operands.back()), depth)

        case "BI":
            try appendInlineImage(parser, &content, page, resourcesId, &state)

        default:
            break
        }

        operands.clear()
    }
}

private func decodeFonts(parser: *PdfParser, page: *Page, resourcesId: u32) fail
{
    let fontsId = parser.dict(resourcesId, "Font")
    if fontsId == InvalidNode or parser.nodes[fontsId].kind != .Dictionary do
        return
    for name, raw in parser.nodes[fontsId].entries
    {
        let fontId = parser.resolve(raw)
        if fontId == InvalidNode do
            continue
        var found = false
        for font in page.fonts where font.objectId == fontId
        {
            found = true
            break
        }

        if found do
            continue
        page.fonts.add(try decodeFontResource(parser, fontId, name.toString()))
    }
}

internal func decodePage(parser: *PdfParser, pageId, inheritedResources, inheritedMediaBox: u32, rotate: s64)->Page fail
{
    let mediaId = parser.dict(pageId, "MediaBox")
    let media   = mediaId != InvalidNode ? mediaId : inheritedMediaBox
    if media == InvalidNode or parser.nodes[media].kind != .Array or parser.nodes[media].values.count < 4 do
        fail InvalidFormatError{"PDF page has no valid MediaBox"}
    let values      = parser.nodes[media].values
    let x0          = nodeNumber(parser, values[0])
    let y0          = nodeNumber(parser, values[1])
    let x1          = nodeNumber(parser, values[2])
    let y1          = nodeNumber(parser, values[3])
    let mediaWidth  = Math.abs(x1 - x0)
    let mediaHeight = Math.abs(y1 - y0)
    if mediaWidth <= 0 or mediaHeight <= 0 or !Math.isFinite(mediaWidth) or !Math.isFinite(mediaHeight) do
        fail InvalidFormatError{"PDF page has invalid dimensions"}
    let normalizedRotate = ((rotate % 360) + 360) % 360
    if normalizedRotate != 0 and normalizedRotate != 90 and normalizedRotate != 180 and normalizedRotate != 270 do
        fail UnsupportedFormatError{"PDF page rotation is not a multiple of 90 degrees"}
    var result: retval = normalizedRotate == 90 or normalizedRotate == 270 ? Page.create(mediaHeight, mediaWidth) : Page.create(mediaWidth, mediaHeight)

    let ownResources = parser.dict(pageId, "Resources")
    let resources    = ownResources != InvalidNode ? ownResources : inheritedResources
    if resources != InvalidNode do
        try decodeFonts(parser, &result, resources)

    let contents = parser.dict(pageId, "Contents")
    if contents != InvalidNode
    {
        var contentBytes: Array'u8
        if parser.nodes[contents].kind == .Array
        {
            for value in parser.nodes[contents].values
            {
                let stream = try parser.decodeStream(value)
                contentBytes.add(stream.toSlice())
                contentBytes.add('\n')
            }
        }
        else
        {
            let stream = try parser.decodeStream(contents)
            contentBytes = #move stream
        }

        var pageState: GraphicsState
        pageState.ctm = Transform2.createTranslation(-x0, -y0)
        switch normalizedRotate
        {
        case 90:  pageState.ctm.multiply(Transform2{0, -1, 1, 0, 0, mediaWidth})
        case 180: pageState.ctm.multiply(Transform2{-1, 0, 0, -1, mediaWidth, mediaHeight})
        case 270: pageState.ctm.multiply(Transform2{0, 1, -1, 0, mediaHeight, 0})
        default:  break
        }

        try parseContent(parser, &result, resources, contentBytes.toSlice(), &pageState)
    }

    return result
}

private func collectPages(parser: *PdfParser, pages: *Array'PageSource, nodeId, inheritedResources, inheritedMediaBox: u32, inheritedRotate: s64, depth: u32) fail
{
    if depth >= 64 do
        fail UnsupportedFormatError{"PDF page tree nesting exceeds the supported depth"}
    let id = parser.resolve(nodeId)
    if id == InvalidNode do
        return
    let resources     = parser.dict(id, "Resources")
    let mediaBox      = parser.dict(id, "MediaBox")
    let rotateId      = parser.dict(id, "Rotate")
    let nextResources = resources != InvalidNode ? resources : inheritedResources
    let nextMediaBox  = mediaBox != InvalidNode ? mediaBox : inheritedMediaBox
    let nextRotate    = rotateId != InvalidNode ? parser.integer(rotateId) : inheritedRotate
    if parser.name(parser.dict(id, "Type")) == "Page"
    {
        pages.add(PageSource{id, nextResources, nextMediaBox, nextRotate})
        return
    }

    let kids = parser.dict(id, "Kids")
    if kids == InvalidNode or parser.nodes[kids].kind != .Array do
        return
    for child in parser.nodes[kids].values do
        try collectPages(parser, pages, child, nextResources, nextMediaBox, nextRotate, depth + 1)
}

private func metadataString(parser: const *PdfParser, dictId: u32, key: string)->String
{
    let raw = parser.stringValue(parser.dict(dictId, key))
    if @countof(raw) >= 2 and raw[0] == 0xFE and raw[1] == 0xFF
    {
        return Text.decode(cast(const [..] u8) raw[2 until], .Utf16Be)
    }

    return Text.decode(cast(const [..] u8) raw, .Windows1252)
}

internal func indexDocument(parser: *PdfParser, metadata: *Metadata, pages: *Array'PageSource) fail
{
    try parser.scanObjects()

    // The trailer names the catalog and the metadata; scanning for them is the fallback for a
    // file whose trailer is missing or damaged, and it is also where a security handler with
    // no readable trailer is noticed.
    var catalog = parser.trailerRoot
    var info    = parser.trailerInfo
    if catalog == InvalidNode or info == InvalidNode
    {
        for objectNumber, nodeId in parser.objects
        {
            discard objectNumber
            let id = parser.resolve(nodeId)
            if id == InvalidNode or parser.nodes[id].kind != .Dictionary do
                continue
            if parser.name(parser.dict(id, "Filter")) == "Standard" and parser.dict(id, "R") != InvalidNode do
                parser.isEncrypted = true
            if catalog == InvalidNode and parser.name(parser.dict(id, "Type")) == "Catalog" do
                catalog = id
            if info == InvalidNode and (parser.dict(id, "Producer") != InvalidNode or parser.dict(id, "Creator") != InvalidNode or parser.dict(id, "Title") != InvalidNode) do
                info = id
        }
    }

    if parser.isEncrypted do
        fail UnsupportedFormatError{"encrypted PDF documents are not supported"}
    if catalog == InvalidNode do
        fail InvalidFormatError{"PDF catalog is missing"}

    if info != InvalidNode
    {
        metadata.title    = metadataString(parser, info, "Title")
        metadata.author   = metadataString(parser, info, "Author")
        metadata.subject  = metadataString(parser, info, "Subject")
        metadata.keywords = metadataString(parser, info, "Keywords")
        metadata.creator  = metadataString(parser, info, "Creator")
        metadata.producer = metadataString(parser, info, "Producer")
    }

    let pageTree = parser.dict(catalog, "Pages")
    if pageTree == InvalidNode do
        fail InvalidFormatError{"PDF page tree is missing"}
    try collectPages(parser, pages, pageTree, InvalidNode, InvalidNode, 0, 0)
    if !pages.count do
        fail InvalidFormatError{"PDF document has no pages"}
}

func decodeDocument(bytes: const [..] u8)->Document fail
{
    var parser          = PdfParser{bytes: bytes}
    var sources: Array'PageSource
    var result:  retval = Document.create()
    try indexDocument(&parser, &result.metadata, &sources)
    for source in sources
    {
        var page = try decodePage(&parser, source.objectId, source.resourcesId, source.mediaBoxId, source.rotate)
        result.addPage(#move page)
    }

    return result
}
