#global namespace Pdf

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

    // Constant alpha, blend mode, and soft mask, from `/ca`, `/CA`, `/BM` and `/SMask`.
    //
    // These are what a document sets a watermark, an overlay, and a feathered shadow with. A mark
    // painted without them arrives at full strength over what it was meant to let through.
    fillAlpha:   f32          = 1
    strokeAlpha: f32          = 1
    blend:       BlendingMode = .Alpha
    softMask:    SoftMaskRef

    // Region every mark is confined to, in the page's own top-left coordinates.
    //
    // A clip is bounded by its enclosing rectangle, which is exact for the axis-aligned
    // rectangles clip paths and form bounding boxes are almost always written as, and
    // conservative otherwise: it can leave a mark that a shaped clip would have removed,
    // and never removes one the page meant to show.
    clip:    Math.Rectangle
    hasClip: bool

    // Shape the clip has beyond its rectangle, as the page records it, once a `W` has marked a
    // path that is not an axis-aligned rectangle.
    clipPath: u32 = InvalidClipPath
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

// One operand waiting for the operator that consumes it.
//
// Numbers are almost every operand a content stream carries, and a number is its value. Giving
// each one a parser node instead costs a hash table, two arrays and a string it never uses, and
// leaves the content parser's node table holding the whole stream at once.
private struct ContentOperand
{
    number: f32
    node:   u32 = InvalidNode
}

// Reads one number straight out of a content stream, without building a node for it.
private func parseContentNumber(content: *PdfParser)->f32
{
    let bytes = content.bytes
    var pos   = content.pos
    var sign  = 1.0'f32
    if pos < bytes.count and (bytes[pos] == '+' or bytes[pos] == '-')
    {
        if bytes[pos] == '-' do
            sign = -1
        pos += 1
    }

    var value = 0.0'f32
    while pos < bytes.count and isDigit(bytes[pos])
    {
        value = value * 10 + cast(f32) (bytes[pos] - '0')
        pos   += 1
    }

    if pos < bytes.count and bytes[pos] == '.'
    {
        pos += 1
        var scale = 0.1'f32
        while pos < bytes.count and isDigit(bytes[pos])
        {
            value += scale * cast(f32) (bytes[pos] - '0')
            scale *= 0.1
            pos   += 1
        }
    }

    content.pos = pos
    return sign * value
}

private func operandNumber(parser: *PdfParser, operands: const [..] ContentOperand, index: u64)->f32
{
    if index >= operands.count do
        return 0
    let operand = operands[index]
    if operand.node == InvalidNode do
        return operand.number
    let value = parser.number(operand.node)
    return value < 0 ? -cast(f32) (-value) : cast(f32) value
}

// Returns the node of one operand, for the few operators that need more than a number.
private func operandNode(operands: const [..] ContentOperand, index: u64)->u32
{
    if index >= operands.count do
        return InvalidNode
    return operands[index].node
}

// Returns one operand as a whole number, or reports that it is not one.
private func operandInteger(parser: *PdfParser, operands: const [..] ContentOperand, index: u64)->{ value: s64, found: bool }
{
    var result: retval
    if index >= operands.count do
        return result

    let operand = operands[index]
    if operand.node == InvalidNode
    {
        if operand.number != Math.trunc(operand.number) or !Math.isFinite(operand.number) do
            return result
        result.value = cast(s64) operand.number
        result.found = true
        return result
    }

    let id = parser.resolve(operand.node)
    if id == InvalidNode or parser.nodes[id].kind != .Integer do
        return result
    result.value = parser.nodes[id].integer
    result.found = true
    return result
}

private func nodeNumber(parser: *PdfParser, nodeId: u32)->f32
{
    let value = parser.number(nodeId)
    return value < 0 ? -cast(f32) (-value) : cast(f32) value
}

// Collects the trailing numeric operands of a color operator.
private func colorComponents(parser: *PdfParser, operands: const [..] ContentOperand, target: [..] f32)->u32
{
    var count = 0'u64
    while count < operands.count and count < target.count
    {
        let operand = operands[operands.count - count - 1]
        if operand.node != InvalidNode
        {
            let id = parser.resolve(operand.node)
            if id == InvalidNode or (parser.nodes[id].kind != .Integer and parser.nodes[id].kind != .Real) do
                break
        }

        count += 1
    }

    for i in count do
        target[i] = operandNumber(parser, operands, operands.count - count + i)
    return cast(u32) count
}

private func currentPath(path: *LinePathList, current: *#null *LinePath, start: Vector2)->*LinePath
{
    let result = path.newPath()
    result.start(start.x, start.y)
    current[] = result
    return result
}

// How finely two clip shapes are flattened before they intersect.
//
// The intersection is polygonal, and it is stated in page points, so at this density its
// facets stay far below what any zoom of a page can show.
private const ClipIntersectionScale = 20.0'f32

// Largest distance between two coordinates that still reads as the same edge of a rectangle.
private const RectangleEpsilon = 0.001'f32

// Reports whether a path is one closed axis-aligned rectangle, the shape almost every clip is.
private func isAxisAlignedRectangle(path: const *LinePathList)->bool
{
    if path.count() != 1 do
        return false

    // Four corners: the start and three lines, or four lines when the last returns to the start.
    let contour = path.toSlice()[0]
    var corners: [5] Vector2
    corners[0] = contour.startPoint
    var count = 1'u64
    for elem in contour.elements
    {
        if elem.type != .Line or count >= corners.count do
            return false
        corners[count] = elem.position
        count          += 1
    }

    if count == 5
    {
        if !corners[4].isEqualEpsilon(corners[0], RectangleEpsilon) do
            return false
        count = 4
    }

    if count != 4 do
        return false

    // Every edge runs along one axis and none is a point, which is what makes four of them a
    // rectangle once they close.
    for i in 4'u64
    {
        let a          = corners[i]
        let b          = corners[(i + 1) % 4]
        let horizontal = Math.isEqualEpsilon(a.y, b.y, RectangleEpsilon)
        let vertical   = Math.isEqualEpsilon(a.x, b.x, RectangleEpsilon)
        if horizontal == vertical do
            return false
    }

    return true
}

// Returns the fill rule a clip operator named, as the boolean solver states it.
private func clipFillType(evenOdd: bool)->Clipper.PolyFillType => evenOdd ? Clipper.PolyFillType.EvenOdd : Clipper.PolyFillType.NonZero

// Narrows the graphics state to the path a `W` or `W*` operator marked as the next clip.
//
// An axis-aligned rectangle, which nearly every clip is, narrows the rectangle alone and
// exactly. Any other shape narrows the rectangle to its bounds and is kept as a shape of its
// own, so the marks painted through it are cut where the author cut them; a shape established
// inside another intersects with it.
private func applyPendingClip(page: *Page, state: *GraphicsState, path: *LinePathList, evenOdd: bool, pending: *bool)
{
    if !pending[] do
        return
    pending[] = false
    if !path.count() do
        return

    state.intersectClip(path.controlBounds())
    if isAxisAlignedRectangle(path) do
        return

    var shape: LinePathList = path[]
    if state.clipPath == InvalidClipPath
    {
        state.clipPath = page.addClipPath(#move shape, evenOdd)
        return
    }

    let outer               = page.clipPaths[state.clipPath]!
    var frame: LinePathList = outer.path
    frame.flatten(.High, ClipIntersectionScale)
    shape.flatten(.High, ClipIntersectionScale)
    shape.intersect(&frame, clipFillType(evenOdd), clipFillType(outer.evenOdd))
    state.clipPath = page.addClipPath(#move shape, false)
}

private func appendPathItem(parser: *PdfParser, page: *Page, path: *LinePathList, state: const *GraphicsState, fill, stroke, close: bool, depth: u32, evenOdd = false)
{
    if !path.count() do
        return

    // A paint operation whose color space could not be reduced paints nothing rather than a
    // color of this module's own choosing.
    let paintFill   = fill and !state.fillSpace.unsupported
    let paintStroke = stroke and !state.strokeSpace.unsupported
    if !paintFill and !paintStroke
    {
        path.clear()
        return
    }

    if close
    {
        let paths = path.toSlice()
        if paths.count do
            paths[paths.count - 1].close()
    }

    var item = Item.createPath()
    item.path        = #move path[]
    item.hasFill     = paintFill
    item.hasStroke   = paintStroke
    item.evenOddFill = evenOdd
    item.fillColor   = dimmed(state.fillColor, state.fillAlpha)
    item.strokeColor = dimmed(state.strokeColor, state.strokeAlpha)
    item.strokeWidth = state.strokeWidth
    item.strokeStyle = state.strokeStyle
    item.clip        = state.clip
    item.hasClip     = state.hasClip
    item.clipPath    = state.clipPath
    appendPaintedItem(parser, page, state, #move item, depth)
    Swag.init(path, 1)
}

private func fontIndex(parser: *PdfParser, page: const *Page, resourcesId: u32, name: string)->u32
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

private func appendText(parser: *PdfParser, page: *Page, resourcesId: u32, state: *GraphicsState, bytes: string, depth: u32)
{
    let index = fontIndex(parser, page, resourcesId, state.fontName.toString())
    let font  = index < page.fonts.count ? &page.fonts[index] : null

    var advance = 0.0'f32
    if font do
        advance = font.runAdvance(bytes, state.fontSize, state.charSpacing, state.wordSpacing)
    else do
        advance = cast(f32) bytes.count * state.fontSize * 0.5

    // Render modes 3 and 7 add no marks; the text still moves the position, which is how
    // an invisible layer over a scanned page stays aligned with what it transcribes.
    let invisible = state.renderMode == 3 or state.renderMode == 7
    let text      = #move (font ? font.decodeText(bytes) : Text.decode(cast(const [..] u8) bytes, .Windows1252))
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
            item.textCodes    = #move font.decodeCodes(bytes)
            item.textAdvances = #move font.codeAdvances(bytes, state.fontSize, state.charSpacing, state.wordSpacing)
        }

        item.fontSize  = state.fontSize
        item.fillColor = dimmed(state.fillColor, state.fillAlpha)
        item.fontIndex = index
        item.transform = Transform2{combined.m11, -combined.m12, m21, m22, baseline.x - state.fontSize * m21, baselineY - state.fontSize * m22}
        item.clip      = state.clip
        item.hasClip   = state.hasClip
        item.clipPath  = state.clipPath
        if font and font.hasStandard do
            item.standardFont = font.standard
        appendPaintedItem(parser, page, state, #move item, depth)
    }

    advanceText(state, advance * state.horizScale)
}

private func appendImageItem(parser: *PdfParser, page: *Page, state: const *GraphicsState, imageId, resourcesId: u32, depth: u32) fail
{
    var item = Item.createImage()
    item.image = #move try decodeImage(parser, imageId, resourcesId, state.fillColor)
    let top    = transformPoint(state, page, 0, 1)
    let right  = transformPoint(state, page, 1, 1)
    let bottom = transformPoint(state, page, 0, 0)
    item.transform = Transform2{right.x - top.x, right.y - top.y, bottom.x - top.x, bottom.y - top.y, top.x, top.y}
    item.clip      = state.clip
    item.hasClip   = state.hasClip
    item.clipPath  = state.clipPath
    if state.clipPath != InvalidClipPath
    {
        // The shape is restated in the image's own unit square, so drawing the shape filled with
        // the texture puts every sample exactly where drawing the rectangle would have.
        item.imageClip = page.clipPaths[state.clipPath]!.path
        item.imageClip.transform(item.transform.inverse())
    }

    // An image carries no colour of its own to dim, so the constant alpha travels as the tint the
    // painter modulates its texture by.
    item.fillColor = dimmed(Color.fromArgb(Argb.White), state.fillAlpha)
    appendPaintedItem(parser, page, state, #move item, depth)
}

// How deep one form XObject may nest inside another before the page is refused.
const MaxFormDepth = 32'u32

// Paints one form XObject's content into the page, under its own matrix and bounding box.
//
// `resourcesId` is what the form inherits when it declares no resources of its own; a form
// reached outside a content stream, such as the group behind a soft mask, inherits nothing.
private func appendForm(parser: *PdfParser, page: *Page, resourcesId: u32, state: const *GraphicsState, formId: u32, depth: u32) fail
{
    if depth >= MaxFormDepth do
        fail UnsupportedFormatError{"PDF form nesting exceeds the supported depth"}

    var formState = state[]
    let matrixId  = parser.dict(formId, "Matrix")
    if matrixId != InvalidNode and parser.nodes[matrixId].kind == .Array and parser.nodes[matrixId].values.count >= 6
    {
        let values = parser.nodes[matrixId].values
        var matrix = Transform2{nodeNumber(parser, values[0]), nodeNumber(parser, values[1]), nodeNumber(parser, values[2]), nodeNumber(parser, values[3]), nodeNumber(parser, values[4]), nodeNumber(parser, values[5])}
        matrix.multiply(formState.ctm)
        formState.ctm = matrix
    }

    // A form's bounding box is part of what it means, not a hint: the form paints nothing
    // outside it, and content built to be trimmed by it would otherwise reach the page as
    // stray marks.
    let boxId = parser.dict(formId, "BBox")
    if boxId != InvalidNode and parser.nodes[boxId].kind == .Array and parser.nodes[boxId].values.count >= 4
    {
        let box = parser.nodes[boxId].values
        let x0  = nodeNumber(parser, box[0])
        let y0  = nodeNumber(parser, box[1])
        let x1  = nodeNumber(parser, box[2])
        let y1  = nodeNumber(parser, box[3])
        formState.intersectClip(transformedBounds(&formState, page, x0, y0, x1, y1))
    }

    // A transparency group is composited as a unit before it reaches the page, so the constant
    // alpha and the soft mask around it apply to that result. Inside the group they start
    // cleared: a group's own content states its marks' transparency, and a `gs` there must not
    // be able to remove the mask the page put the whole group behind.
    let group      = parser.dict(formId, "Group")
    let isGroup    = parser.name(parser.dict(group, "S")) == "Transparency"
    var outerMask: SoftMaskRef
    var outerAlpha = 1.0'f32
    if isGroup
    {
        outerMask             = formState.softMask
        outerAlpha            = formState.fillAlpha
        formState.softMask    = SoftMaskRef{}
        formState.fillAlpha   = 1
        formState.strokeAlpha = 1
    }

    let ownResources = parser.dict(formId, "Resources")
    let resources    = ownResources != InvalidNode ? ownResources : resourcesId
    if resources != InvalidNode do
        try decodeFonts(parser, page, resources)
    let bytes = #move try parser.decodeStream(formId)
    let first = page.items.count
    try parseContent(parser, page, resources, bytes.toSlice(), &formState, depth + 1)
    if isGroup and (outerMask.isActive() or outerAlpha < 1) do
        applyGroupTransparency(parser, page, first, &outerMask, outerAlpha, depth)
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
        try appendForm(parser, page, resourcesId, state, id, depth)
        return
    }

    if subtype != "Image" do
        return
    try appendImageItem(parser, page, state, id, resourcesId, depth)
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
private func appendInlineImage(parser: *PdfParser, content: *PdfParser, page: *Page, resourcesId: u32, state: const *GraphicsState, depth: u32) fail
{
    var node: Node
    node.kind = .Dictionary
    var imported: HashTable'(u32, u32)
    for
    {
        content.skip()
        if content.pos >= content.bytes.count do
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
    if content.pos < content.bytes.count and isWhite(content.bytes[content.pos]) do
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
        let space   = #move try resolveImageSpace(parser, parser.dictRaw(imageId, "ColorSpace"), resourcesId, 0)
        let rowBits = cast(s64) space.components * bits * width
        if width > 0 and height > 0 and bits > 0 do
            length = (rowBits + 7) / 8 * height
    }

    var end = Swag.U64.Max
    if length >= 0 and start + cast(u64) length <= content.bytes.count do
        end = start + cast(u64) length
    else do
        end = findInlineImageEnd(content.bytes, start)
    if end == Swag.U64.Max do
        fail InvalidFormatError{"PDF inline image has no EI marker"}

    parser.nodes[imageId].stream = Swag.makeSlice(content.bytes.buffer + start, end - start)
    content.pos = end
    discard content.consumeWord("EI")
    try appendImageItem(parser, page, state, imageId, resourcesId, depth)
}

// Finds the `EI` that closes an inline image whose length cannot be computed.
private func findInlineImageEnd(bytes: const [..] u8, start: u64)->u64
{
    var pos = start
    while pos + 2 <= bytes.count
    {
        if bytes[pos] == 'E' and bytes[pos + 1] == 'I' and pos > start and isWhite(bytes[pos - 1])
        {
            if pos + 2 == bytes.count or isDelimiter(bytes[pos + 2]) do
                return pos - 1
        }

        pos += 1
    }

    return Swag.U64.Max
}

// Returns the painter mode a `/BM` name selects.
//
// Every mode the format defines is one the painter composites natively, separable and
// non-separable alike, so a name is either one of these or not a blend mode at all.
private func blendingMode(name: string)->{ mode: BlendingMode, found: bool }
{
    switch name
    {
    case "Normal", "Compatible": return {.Alpha, true}
    case "Multiply":             return {.Multiply, true}
    case "Screen":               return {.Screen, true}
    case "Overlay":              return {.Overlay, true}
    case "Darken":               return {.Darken, true}
    case "Lighten":              return {.Lighten, true}
    case "ColorDodge":           return {.ColorDodge, true}
    case "ColorBurn":            return {.ColorBurn, true}
    case "HardLight":            return {.HardLight, true}
    case "SoftLight":            return {.SoftLight, true}
    case "Difference":           return {.Difference, true}
    case "Exclusion":            return {.Exclusion, true}
    case "Hue":                  return {.Hue, true}
    case "Saturation":           return {.Saturation, true}
    case "Color":                return {.Color, true}
    case "Luminosity":           return {.Luminosity, true}
    }

    return {.Alpha, false}
}

// Reads the parts of an ExtGState that change how later operators paint.
//
// Every entry is applied only when the dictionary carries it: an ExtGState states the parameters
// it changes and leaves the rest of the graphics state alone.
private func applyExtGState(parser: *PdfParser, page: const *Page, resourcesId: u32, state: *GraphicsState, name: string)
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

    let fillAlpha = parser.dict(entry, "ca")
    if fillAlpha != InvalidNode do
        state.fillAlpha = Math.saturate(nodeNumber(parser, fillAlpha))

    let strokeAlpha = parser.dict(entry, "CA")
    if strokeAlpha != InvalidNode do
        state.strokeAlpha = Math.saturate(nodeNumber(parser, strokeAlpha))

    // `/BM` may name one mode or an array of them, in which case the first supported name is the
    // one that applies; a name this module cannot express leaves the mode alone rather than
    // normalizing an overlay into a replacement.
    let blend = parser.dict(entry, "BM")
    if blend != InvalidNode
    {
        if parser.nodes[blend].kind == .Array
        {
            for value in parser.nodes[blend].values
            {
                let picked = blendingMode(parser.name(parser.resolve(value)))
                if picked.found
                {
                    state.blend = picked.mode
                    break
                }
            }
        }
        else
        {
            let picked = blendingMode(parser.name(blend))
            if picked.found do
                state.blend = picked.mode
        }
    }

    // The mask is established in the transform in force at this point, not in the one a later
    // mark happens to be painted under.
    if parser.dict(entry, "SMask") != InvalidNode do
        state.softMask = readSoftMask(parser, entry, state.ctm)
}

// Decodes the transparency group behind a soft mask, once per group and transform.
//
// The group's marks are read into a page of the same dimensions as the one being decoded, so its
// coverage is expressed in the same coordinates as the marks it covers.
private func softMaskGroup(parser: *PdfParser, page: const *Page, mask: const *SoftMaskRef, depth: u32)->#null *SoftMaskGroup fail
{
    let key    = mask.cacheKey()
    let cached = parser.softMaskCache.tryFind(key)
    if cached do
        return &cached.value

    if depth >= MaxFormDepth do
        fail UnsupportedFormatError{"PDF soft mask nesting exceeds the supported depth"}

    var group: SoftMaskGroup
    group.backdrop = mask.backdrop
    group.kind     = mask.kind
    group.page     = #move Page.create(page.width, page.height)

    var groupState: GraphicsState
    groupState.ctm = mask.ctm
    try appendForm(parser, &group.page, InvalidNode, &groupState, mask.groupId, depth + 1)

    parser.softMaskCache.add(key, #move group)
    return &parser.softMaskCache.tryFind(key)!.value
}

// Returns a colour dimmed by a constant alpha.
//
// The alpha is rounded the way a sample is, so a half-transparent black is the same 128 a
// document that stated it as a byte would have produced.
private func dimmed(color: Color, alpha: f32)->Color => color.withAlpha(componentByte(cast(f32) color.a / 255.0 * alpha))

// Returns the mean coverage of an image whose alpha carries it.
private func meanCoverage(coverage: const *Image)->f32
{
    var total = 0'u64
    for y in cast(u64) coverage.height
    {
        var source = coverage.pixels.buffer! + y * cast(u64) coverage.rowStride
        for cast(u64) coverage.width
        {
            total  += source[3]
            source += 4
        }
    }

    let count = cast(u64) coverage.width * cast(u64) coverage.height
    if !count do
        return 1
    return cast(f32) total / (cast(f32) count * 255.0)
}

// Multiplies a soft mask's coverage into an image item's own alpha channel.
//
// An image is already a raster, so its coverage belongs in its samples: that is exact, needs no
// second texture, and keeps the item a single draw. The item's transform maps the unit square
// onto the page, which is what turns a sample position into the page point the coverage is
// stated at.
private func maskImagePixels(item: *Item, coverage: const *Image, region: Math.Rectangle)
{
    if !item.image.isValid() or !coverage.isValid() do
        return
    if item.image.pixelFormat != .RGBA8
    {
        var opaque = #move item.image.convertedTo(.RGBA8)
        item.image = #move opaque
    }

    let width  = cast(u64) item.image.width
    let height = cast(u64) item.image.height
    for row in height
    {
        // An image stores its rows bottom-up while its unit square runs top-down.
        let v      = (cast(f32) (height - row - 1) + 0.5) / cast(f32) height
        var pixels = item.image.pixels.buffer! + row * cast(u64) item.image.rowStride
        for column in width
        {
            let u     = (cast(f32) column + 0.5) / cast(f32) width
            let point = item.transform.transformPoint({u, v})
            let x     = cast(s32) ((point.x - region.x) / region.width * cast(f32) coverage.width)
            let y     = cast(s32) ((point.y - region.y) / region.height * cast(f32) coverage.height)
            let alpha = coverage.pixelColor(x, y).a
            pixels[3] = cast(u8) ((cast(u32) pixels[3] * alpha) / 255)
            pixels    += 4
        }
    }
}

// Multiplies a soft mask's coverage into one already-built item.
//
// A mask that cannot be built leaves the mark at full strength, which is what the page showed
// before masks were read at all: losing a shadow's softness beats losing the mark under it.
private func maskItem(parser: *PdfParser, page: *Page, mask: const *SoftMaskRef, item: *Item, depth: u32)
{
    let group = catch softMaskGroup(parser, page, mask, depth) as groupError
    if groupError != null do
        return

    item.refreshPaintBounds()
    let region = item.maskRegion()
    if !region.known do
        return

    var coverage = catch softMaskCoverage(group!, region.rect) as coverageError
    if coverageError != null or !coverage.isValid() do
        return

    switch item.kind
    {
    case .Image:

        // An image is already a raster, so its coverage belongs in its own samples: exact, and it
        // keeps the item a single draw with no second texture.
        maskImagePixels(item, &coverage, region.rect)

    case .Text:

        // A run is drawn from the glyph atlas, which is the one texture the painter samples for
        // it, so its coverage cannot vary across the run. The mean over the run's own box is what
        // remains expressible: exact for the uniform mask a whole faded layer uses, and an
        // approximation for a gradient crossing a single line of text.
        item.fillColor = dimmed(item.fillColor, meanCoverage(&coverage))

    case .Path:
        item.multiplyMask(#move coverage, region.rect)
    }
}

// Records one item under the transparency the graphics state establishes.
//
// Constant alpha reaches the mark through its own colour, a blend mode travels to the painter,
// and a soft mask becomes the coverage the mark is multiplied by.
private func appendPaintedItem(parser: *PdfParser, page: *Page, state: const *GraphicsState, item: #move Item, depth: u32)
{
    item.blend = state.blend
    if state.softMask.isActive() do
        maskItem(parser, page, &state.softMask, &item, depth)
    page.appendItem(#move item)
}

// Applies to a transparency group's result the transparency that was in force around it.
//
// A group is composited as a unit and only then combined with the page, so the constant alpha
// and the soft mask outside it belong to that result — not to the marks inside, which state
// their own and must not be able to clear the group's. `first` is where the group's items begin.
//
// The marks are masked one at a time rather than composited together first, which is the same
// result whenever they do not overlap, and every drop shadow, vignette and fade a document
// expresses this way is a single mark under its mask.
private func applyGroupTransparency(parser: *PdfParser, page: *Page, first: u64, mask: const *SoftMaskRef, alpha: f32, depth: u32)
{
    for index in first until page.items.count
    {
        let item = page.itemAt(index)
        if alpha < 1
        {
            item.fillColor   = dimmed(item.fillColor, alpha)
            item.strokeColor = dimmed(item.strokeColor, alpha)
        }

        if mask.isActive() do
            maskItem(parser, page, mask, item, depth)
    }
}

private func parseContent(parser: *PdfParser, page: *Page, resourcesId: u32, bytes: const [..] u8, initialState: #null const *GraphicsState = null, depth = 0'u32) fail
{
    var content = PdfParser{bytes: bytes}
    var operands: Array'ContentOperand
    var state   = initialState ? initialState![] : GraphicsState{}
    var stack:    Array'GraphicsState
    var path:     LinePathList
    var current:  #null *LinePath

    // A `W` operator names the path under construction as the next clip, and the painting
    // operator that ends the path is what puts it into effect.
    var pendingClip:        bool
    var pendingClipEvenOdd: bool
    var values:             [8] f32

    while content.pos < bytes.count
    {
        content.skip()
        if content.pos >= bytes.count do
            break
        let c = bytes[content.pos]
        if isDigit(c) or c == '+' or c == '-' or c == '.'
        {
            operands.add({number: parseContentNumber(&content), node: InvalidNode})
            continue
        }

        if c == '/' or c == '(' or c == '[' or c == '<'
        {
            operands.add({number: 0, node: try content.parseValue()})
            continue
        }

        let start = content.pos
        while content.pos < bytes.count and !isDelimiter(bytes[content.pos]) do
            content.pos += 1
        if content.pos == start
        {
            content.pos += 1
            continue
        }

        let op  = cast(string) Swag.makeSlice(bytes.buffer + start, content.pos - start)
        let ops = operands.toSlice()
        switch op
        {
        case "q":
            stack.add(state)

        case "Q":
            if stack.count
            {
                var restored = #move stack.popBack()
                Swag.drop(&state, 1)
                Swag.init(&state, 1)
                state = #move restored
            }

        case "cm":
            if ops.count >= 6
            {
                let n      = ops.count - 6
                let a      = operandNumber(&content, ops, n)
                let b      = operandNumber(&content, ops, n + 1)
                let c      = operandNumber(&content, ops, n + 2)
                let d      = operandNumber(&content, ops, n + 3)
                let e      = operandNumber(&content, ops, n + 4)
                let f      = operandNumber(&content, ops, n + 5)
                var matrix = Transform2{a, b, c, d, e, f}
                matrix.multiply(state.ctm)
                state.ctm = matrix
            }

        case "w":
            if ops.count
            {
                let width = operandNumber(&content, ops, ops.count - 1)
                if width < 0 or !Math.isFinite(width) do
                    fail InvalidFormatError{"PDF line width needs a non-negative finite number"}
                state.strokeWidth = width
            }

        case "J":
            if ops.count
            {
                let cap = operandInteger(&content, ops, ops.count - 1)
                if !cap.found do
                    fail InvalidFormatError{"PDF line cap needs an integer from 0 to 2"}
                switch cap.value
                {
                case 0:  state.strokeStyle.cap = .Butt
                case 1:  state.strokeStyle.cap = .Round
                case 2:  state.strokeStyle.cap = .Square
                default: fail InvalidFormatError{"PDF line cap accepts values from 0 to 2"}
                }
            }

        case "j":
            if ops.count
            {
                let join = operandInteger(&content, ops, ops.count - 1)
                if !join.found do
                    fail InvalidFormatError{"PDF line join needs an integer from 0 to 2"}
                switch join.value
                {
                case 0:  state.strokeStyle.join = .Miter
                case 1:  state.strokeStyle.join = .Round
                case 2:  state.strokeStyle.join = .Bevel
                default: fail InvalidFormatError{"PDF line join accepts values from 0 to 2"}
                }
            }

        case "M":
            if ops.count
            {
                let limit = operandNumber(&content, ops, ops.count - 1)
                if limit < 1 or !Math.isFinite(limit) do
                    fail InvalidFormatError{"PDF miter limit needs a finite number of at least 1"}
                state.strokeStyle.miterLimit = limit
            }

        case "d":
            if ops.count >= 2
            {
                let arrayId = content.resolve(operandNode(ops, ops.count - 2))
                let phase   = operandNumber(&content, ops, ops.count - 1)
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

                state.strokeStyle.dashPattern.free()
                state.strokeStyle.dashPattern = #move pattern
                state.strokeStyle.dashPhase   = phase
            }

        case "gs":
            if ops.count do
                applyExtGState(parser, page, resourcesId, &state, content.name(ops[ops.count - 1].node))

        case "g":
            if ops.count
            {
                state.fillSpace.palette.free()
                state.fillSpace = deviceSpace(.Gray, 1)
                state.fillColor = grayColor(operandNumber(&content, ops, ops.count - 1))
            }

        case "G":
            if ops.count
            {
                state.strokeSpace.palette.free()
                state.strokeSpace = deviceSpace(.Gray, 1)
                state.strokeColor = grayColor(operandNumber(&content, ops, ops.count - 1))
            }

        case "rg":
            if ops.count >= 3
            {
                state.fillSpace.palette.free()
                state.fillSpace = deviceSpace(.Rgb, 3)
                state.fillColor = rgbColor(operandNumber(&content, ops, ops.count - 3), operandNumber(&content, ops, ops.count - 2), operandNumber(&content, ops, ops.count - 1))
            }

        case "RG":
            if ops.count >= 3
            {
                state.strokeSpace.palette.free()
                state.strokeSpace = deviceSpace(.Rgb, 3)
                state.strokeColor = rgbColor(operandNumber(&content, ops, ops.count - 3), operandNumber(&content, ops, ops.count - 2), operandNumber(&content, ops, ops.count - 1))
            }

        case "k":
            if ops.count >= 4
            {
                state.fillSpace.palette.free()
                state.fillSpace = deviceSpace(.Cmyk, 4)
                state.fillColor = cmykColor(operandNumber(&content, ops, ops.count - 4), operandNumber(&content, ops, ops.count - 3), operandNumber(&content, ops, ops.count - 2), operandNumber(&content, ops, ops.count - 1))
            }

        case "K":
            if ops.count >= 4
            {
                state.strokeSpace.palette.free()
                state.strokeSpace = deviceSpace(.Cmyk, 4)
                state.strokeColor = cmykColor(operandNumber(&content, ops, ops.count - 4), operandNumber(&content, ops, ops.count - 3), operandNumber(&content, ops, ops.count - 2), operandNumber(&content, ops, ops.count - 1))
            }

        case "cs", "CS":
            if ops.count
            {
                // The operand is a name parsed by the content scanner, so it is resolved
                // against the page resources rather than through a document node.
                var picked = deviceSpace(.Gray, 1)
                let space  = catch resolveNamedColorSpace(parser, content.name(ops[ops.count - 1].node), resourcesId, 0) as spaceError
                if spaceError == null do
                    picked = space
                else do
                    picked.unsupported = true
                if op == "cs"
                {
                    state.fillColor = initialSpaceColor(&picked)
                    state.fillSpace.palette.free()
                    state.fillSpace = #move picked
                }
                else
                {
                    state.strokeColor = initialSpaceColor(&picked)
                    state.strokeSpace.palette.free()
                    state.strokeSpace = #move picked
                }
            }

        case "sc", "scn", "SC", "SCN":
            let count = colorComponents(&content, ops, values)
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
            if ops.count >= 2 do
                currentPath(&path, &current, transformPoint(&state, page, operandNumber(&content, ops, ops.count - 2), operandNumber(&content, ops, ops.count - 1)))

        case "l":
            if current and ops.count >= 2
            {
                let p = transformPoint(&state, page, operandNumber(&content, ops, ops.count - 2), operandNumber(&content, ops, ops.count - 1))
                current!.lineTo(p.x, p.y)
            }

        case "c":
            if current and ops.count >= 6
            {
                let n  = ops.count - 6
                let c1 = transformPoint(&state, page, operandNumber(&content, ops, n), operandNumber(&content, ops, n + 1))
                let c2 = transformPoint(&state, page, operandNumber(&content, ops, n + 2), operandNumber(&content, ops, n + 3))
                let p  = transformPoint(&state, page, operandNumber(&content, ops, n + 4), operandNumber(&content, ops, n + 5))
                current!.bezierTo(p.x, p.y, c1.x, c1.y, c2.x, c2.y)
            }

        case "v":

            // The first control point of `v` is the current point itself.
            if current and ops.count >= 4
            {
                let n  = ops.count - 4
                let c1 = current!.endPoint
                let c2 = transformPoint(&state, page, operandNumber(&content, ops, n), operandNumber(&content, ops, n + 1))
                let p  = transformPoint(&state, page, operandNumber(&content, ops, n + 2), operandNumber(&content, ops, n + 3))
                current!.bezierTo(p.x, p.y, c1.x, c1.y, c2.x, c2.y)
            }

        case "y":

            // The second control point of `y` is its own end point.
            if current and ops.count >= 4
            {
                let n  = ops.count - 4
                let c1 = transformPoint(&state, page, operandNumber(&content, ops, n), operandNumber(&content, ops, n + 1))
                let p  = transformPoint(&state, page, operandNumber(&content, ops, n + 2), operandNumber(&content, ops, n + 3))
                current!.bezierTo(p.x, p.y, c1.x, c1.y, p.x, p.y)
            }

        case "h":
            if current do
                current!.close()

        case "re":
            if ops.count >= 4
            {
                let n    = ops.count - 4
                let x    = operandNumber(&content, ops, n)
                let y    = operandNumber(&content, ops, n + 1)
                let w    = operandNumber(&content, ops, n + 2)
                let h    = operandNumber(&content, ops, n + 3)
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
            pendingClip        = true
            pendingClipEvenOdd = op == "W*"

        case "S":
            applyPendingClip(page, &state, &path, pendingClipEvenOdd, &pendingClip)
            appendPathItem(parser, page, &path, &state, false, true, false, depth)
            current = null

        case "s":
            applyPendingClip(page, &state, &path, pendingClipEvenOdd, &pendingClip)
            appendPathItem(parser, page, &path, &state, false, true, true, depth)
            current = null

        // A star names the alternating rule, under which two overlapping contours cancel
        // instead of merging; without it a ring drawn as two circles fills solid.
        case "f", "F", "f*":
            applyPendingClip(page, &state, &path, pendingClipEvenOdd, &pendingClip)
            appendPathItem(parser, page, &path, &state, true, false, false, depth, op == "f*")
            current = null

        case "B", "B*":
            applyPendingClip(page, &state, &path, pendingClipEvenOdd, &pendingClip)
            appendPathItem(parser, page, &path, &state, true, true, false, depth, op == "B*")
            current = null

        case "b", "b*":
            applyPendingClip(page, &state, &path, pendingClipEvenOdd, &pendingClip)
            appendPathItem(parser, page, &path, &state, true, true, true, depth, op == "b*")
            current = null

        case "n":
            applyPendingClip(page, &state, &path, pendingClipEvenOdd, &pendingClip)
            path.clear()
            current = null

        case "BT":
            state.textMatrix = Transform2.Identity
            state.lineMatrix = Transform2.Identity

        case "Tf":
            if ops.count >= 2
            {
                state.fontName = content.name(operandNode(ops, ops.count - 2))
                state.fontSize = operandNumber(&content, ops, ops.count - 1)
            }

        case "Tc":
            if ops.count do
                state.charSpacing = operandNumber(&content, ops, ops.count - 1)

        case "Tw":
            if ops.count do
                state.wordSpacing = operandNumber(&content, ops, ops.count - 1)

        case "Tz":
            if ops.count do
                state.horizScale = operandNumber(&content, ops, ops.count - 1) / 100.0

        case "TL":
            if ops.count do
                state.leading = operandNumber(&content, ops, ops.count - 1)

        case "Ts":
            if ops.count do
                state.rise = operandNumber(&content, ops, ops.count - 1)

        case "Tr":
            if ops.count do
                state.renderMode = operandInteger(&content, ops, ops.count - 1).value

        case "Tm":
            if ops.count >= 6
            {
                let n = ops.count - 6
                state.textMatrix = Transform2{operandNumber(&content, ops, n), operandNumber(&content, ops, n + 1), operandNumber(&content, ops, n + 2), operandNumber(&content, ops, n + 3), operandNumber(&content, ops, n + 4), operandNumber(&content, ops, n + 5)}
                state.lineMatrix = state.textMatrix
            }

        case "Td":
            if ops.count >= 2 do
                moveTextLine(&state, operandNumber(&content, ops, ops.count - 2), operandNumber(&content, ops, ops.count - 1))

        case "TD":
            if ops.count >= 2
            {
                let y = operandNumber(&content, ops, ops.count - 1)
                state.leading = -y
                moveTextLine(&state, operandNumber(&content, ops, ops.count - 2), y)
            }

        case "T*":
            moveTextLine(&state, 0, -state.leading)

        case "Tj":
            if ops.count do
                appendText(parser, page, resourcesId, &state, content.stringValue(ops[ops.count - 1].node), depth)

        case "'":
            if ops.count
            {
                moveTextLine(&state, 0, -state.leading)
                appendText(parser, page, resourcesId, &state, content.stringValue(ops[ops.count - 1].node), depth)
            }

        case "\"":
            if ops.count >= 3
            {
                state.wordSpacing = operandNumber(&content, ops, ops.count - 3)
                state.charSpacing = operandNumber(&content, ops, ops.count - 2)
                moveTextLine(&state, 0, -state.leading)
                appendText(parser, page, resourcesId, &state, content.stringValue(ops[ops.count - 1].node), depth)
            }

        case "TJ":
            if ops.count
            {
                let arrayId = content.resolve(ops[ops.count - 1].node)
                if arrayId != InvalidNode and content.nodes[arrayId].kind == .Array
                {
                    for value in content.nodes[arrayId].values
                    {
                        let id = content.resolve(value)
                        if id != InvalidNode and content.nodes[id].kind == .String do
                            appendText(parser, page, resourcesId, &state, content.nodes[id].text.toString(), depth)
                        elif id != InvalidNode do
                            advanceText(&state, -cast(f32) content.number(id) * state.fontSize * state.horizScale / 1000.0)
                    }
                }
            }

        case "Do":
            if ops.count do
                try appendXObject(parser, page, resourcesId, &state, content.name(ops[ops.count - 1].node), depth)

        case "BI":
            try appendInlineImage(parser, &content, page, resourcesId, &state, depth)

        default:
            break
        }

        operands.clear()

        // Nothing outlives the operator that consumed it: a name or a string is copied into the
        // state or the item that keeps it, so the nodes behind this operator's operands can go
        // back. Left to grow, the table would hold the whole content stream at once.
        content.nodes.clear()
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

        let cached = parser.fontCache.tryFind(fontId)
        if cached
        {
            // The resource name is the key this page filed the font under, and two pages may
            // file the same object under different names; everything else about the font is a
            // property of the object.
            var shared: FontResource = cached.value
            shared.name = name.toString()
            page.fonts.add(#move shared)
            continue
        }

        var font = #move try decodeFontResource(parser, fontId, name.toString())
        parser.fontCache[fontId] = font
        page.fonts.add(#move font)
    }
}

// Returns a page box array as a normalized rectangle in PDF coordinates.
private func boxRectangle(parser: *PdfParser, boxId: u32)->Math.Rectangle
{
    let values = parser.nodes[boxId].values
    let x0     = nodeNumber(parser, values[0])
    let y0     = nodeNumber(parser, values[1])
    let x1     = nodeNumber(parser, values[2])
    let y1     = nodeNumber(parser, values[3])
    return {Math.min(x0, x1), Math.min(y0, y1), Math.abs(x1 - x0), Math.abs(y1 - y0)}
}

internal func decodePage(parser: *PdfParser, pageId, inheritedResources, inheritedMediaBox, inheritedCropBox: u32, rotate: s64)->Page fail
{
    let mediaId = parser.dict(pageId, "MediaBox")
    let media   = mediaId != InvalidNode ? mediaId : inheritedMediaBox
    if media == InvalidNode or parser.nodes[media].kind != .Array or parser.nodes[media].values.count < 4 do
        fail InvalidFormatError{"PDF page has no valid MediaBox"}
    var box = boxRectangle(parser, media)

    // The MediaBox bounds the medium; the CropBox, when present, is the region a reader
    // displays. The page is their intersection, so the margins an author trimmed away stay
    // trimmed here the same way the file shows everywhere else. A malformed crop is ignored
    // rather than costing the page.
    let cropId = parser.dict(pageId, "CropBox")
    let crop   = cropId != InvalidNode ? cropId : inheritedCropBox
    if crop != InvalidNode and parser.nodes[crop].kind == .Array and parser.nodes[crop].values.count >= 4
    {
        var cropped = boxRectangle(parser, crop)
        cropped.intersect(box)
        if cropped.width > 0 and cropped.height > 0 and Math.isFinite(cropped.width) and Math.isFinite(cropped.height) do
            box = cropped
    }

    let x0          = box.x
    let y0          = box.y
    let mediaWidth  = box.width
    let mediaHeight = box.height
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
                let stream = #move try parser.decodeStream(value)
                contentBytes.add(stream.toSlice())
                contentBytes.add('\n')
            }
        }
        else
        {
            let stream = #move try parser.decodeStream(contents)
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

private func collectPages(parser: *PdfParser, pages: *Array'PageSource, nodeId, inheritedResources, inheritedMediaBox, inheritedCropBox: u32, inheritedRotate: s64, depth: u32) fail
{
    if depth >= 64 do
        fail UnsupportedFormatError{"PDF page tree nesting exceeds the supported depth"}
    let id = parser.resolve(nodeId)
    if id == InvalidNode do
        return
    let resources     = parser.dict(id, "Resources")
    let mediaBox      = parser.dict(id, "MediaBox")
    let cropBox       = parser.dict(id, "CropBox")
    let rotateId      = parser.dict(id, "Rotate")
    let nextResources = resources != InvalidNode ? resources : inheritedResources
    let nextMediaBox  = mediaBox != InvalidNode ? mediaBox : inheritedMediaBox
    let nextCropBox   = cropBox != InvalidNode ? cropBox : inheritedCropBox
    let nextRotate    = rotateId != InvalidNode ? parser.integer(rotateId) : inheritedRotate
    if parser.name(parser.dict(id, "Type")) == "Page"
    {
        pages.add(PageSource{id, nextResources, nextMediaBox, nextCropBox, nextRotate})
        return
    }

    let kids = parser.dict(id, "Kids")
    if kids == InvalidNode or parser.nodes[kids].kind != .Array do
        return
    for child in parser.nodes[kids].values do
        try collectPages(parser, pages, child, nextResources, nextMediaBox, nextCropBox, nextRotate, depth + 1)
}

private func metadataString(parser: *PdfParser, dictId: u32, key: string)->String
{
    let raw = parser.stringValue(parser.dict(dictId, key))
    if raw.count >= 2 and raw[0] == 0xFE and raw[1] == 0xFF
    {
        var result = #move Text.decode(cast(const [..] u8) raw[2 until], .Utf16Be)
        return #move result
    }

    var result = #move Text.decode(cast(const [..] u8) raw, .Windows1252)
    return #move result
}

// Returns the catalog a trailer named, once the whole chain has been read.
private func resolvedCatalog(parser: *PdfParser, rootRaw: u32)->u32
{
    let catalog = parser.resolve(rootRaw)
    if catalog == InvalidNode or parser.name(parser.dict(catalog, "Type")) != "Catalog" do
        return InvalidNode
    return catalog
}

// Returns the information dictionary a trailer named.
private func resolvedInfo(parser: *PdfParser, infoRaw: u32)->u32
{
    let info = parser.resolve(infoRaw)
    if info == InvalidNode or parser.nodes[info].kind != .Dictionary do
        return InvalidNode
    return info
}

internal func indexDocument(parser: *PdfParser, metadata: *Metadata, pages: *Array'PageSource) fail
{
    try parser.locateHeader()

    // The file's own cross-reference chain says where every object is, so opening costs the
    // chain and the page tree rather than the whole file. A chain that is missing or damaged
    // falls back to the scan, which is the only thing that can read such a file at all.
    if !parser.readXrefChain() do
        try parser.scanObjects()

    // The trailer names the catalog and the metadata; searching for them is the fallback for a
    // file whose trailer is missing or damaged, and it is also where a security handler with
    // no readable trailer is noticed.
    var catalog = resolvedCatalog(parser, parser.trailerRoot)
    var info    = resolvedInfo(parser, parser.trailerInfo)
    if catalog == InvalidNode or info == InvalidNode
    {
        // The search needs every object, which is exactly what the scan produces.
        parser.ensureScanned()
        if catalog == InvalidNode do
            catalog = resolvedCatalog(parser, parser.trailerRoot)
        if info == InvalidNode do
            info = resolvedInfo(parser, parser.trailerInfo)

        var scanned: Array'u32
        for objectNumber, nodeId in parser.objects
        {
            discard objectNumber
            scanned.add(nodeId)
        }

        for nodeId in scanned
        {
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
        metadata.title    = #move metadataString(parser, info, "Title")
        metadata.author   = #move metadataString(parser, info, "Author")
        metadata.subject  = #move metadataString(parser, info, "Subject")
        metadata.keywords = #move metadataString(parser, info, "Keywords")
        metadata.creator  = #move metadataString(parser, info, "Creator")
        metadata.producer = #move metadataString(parser, info, "Producer")
    }

    let pageTree = parser.dict(catalog, "Pages")
    if pageTree == InvalidNode do
        fail InvalidFormatError{"PDF page tree is missing"}
    try collectPages(parser, pages, pageTree, InvalidNode, InvalidNode, InvalidNode, 0, 0)
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
        var page = #move try decodePage(&parser, source.objectId, source.resourcesId, source.mediaBoxId, source.cropBoxId, source.rotate)
        result.addPage(#move page)
    }

    return result
}
