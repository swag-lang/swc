using Core, Core.Errors, Core.Math, Pixel

private struct GraphicsState
{
    ctm:         Transform2 = Transform2.Identity
    fillColor:   Color      = Color.fromArgb(Argb.Black)
    strokeColor: Color      = Color.fromArgb(Argb.Black)
    strokeWidth: f32        = 1
    fontName:    String
    fontSize:    f32        = 12
    textMatrix:  Transform2 = Transform2.Identity
    lineMatrix:  Transform2 = Transform2.Identity
}

private func component(value: f64)->u8 => cast(u8) Math.clamp(Math.round(value * 255.0), 0, 255)

private func grayColor(value: f64)->Color
{
    let c = component(value)
    return Color.fromRgb(c, c, c)
}

private func rgbColor(r, g, b: f64)->Color => Color.fromRgb(component(r), component(g), component(b))

private func cmykColor(c, m, y, k: f64)->Color
{
    let r = 1.0 - Math.min(1.0, c + k)
    let g = 1.0 - Math.min(1.0, m + k)
    let b = 1.0 - Math.min(1.0, y + k)
    return rgbColor(r, g, b)
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

private func currentPath(path: *LinePathList, current: *#null *LinePath, start: Vector2)->*LinePath
{
    let result = path.newPath()
    result.start(start.x, start.y)
    current[] = result
    return result
}

private func appendPathItem(page: *Page, path: *LinePathList, state: const *GraphicsState, fill, stroke, close: bool)
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
    item.fillColor   = state.fillColor
    item.strokeColor = state.strokeColor
    item.strokeWidth = state.strokeWidth
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

private func decodeText(font: #null const *FontResource, bytes: string)->String
{
    if !font or !font.unicode.count do
        return Text.decode(cast(const [..] u8) bytes, .Windows1252)

    var result: retval
    var pos       = 0'u64
    let codeBytes = Math.max(font.codeBytes, 1)
    while pos + codeBytes <= @countof(bytes)
    {
        var code = 0'u32
        for i in codeBytes do
            code = code << 8 | bytes[pos + i]
        pos += codeBytes
        let entry = font.unicode.tryFind(code)
        if entry do
            result += entry.value
        elif code <= 0xFF do
            result += Text.decode(@mkslice(cast(const [*] u8) &code, 1), .Windows1252)
    }

    return result
}

private func appendText(parser: const *PdfParser, page: *Page, resourcesId: u32, state: *GraphicsState, bytes: string)
{
    let index = fontIndex(parser, page, resourcesId, state.fontName.toString())
    let font  = index < page.fonts.count ? &page.fonts[index] : null
    let text  = decodeText(font, bytes)
    if text.isEmpty() do
        return
    let runeCount = Utf8.countRunes(text.toString())

    var combined = state.textMatrix
    combined.multiply(state.ctm)
    let baseline = combined.translation()
    var item     = Item.createText()
    item.text      = #move text
    item.fontSize  = state.fontSize
    item.fillColor = state.fillColor
    item.fontIndex = index
    let m11       = combined.m11
    let m12       = -combined.m12
    let m21       = -combined.m21
    let m22       = combined.m22
    let baselineX = baseline.x
    let baselineY = page.height - baseline.y
    item.transform = Transform2{m11, m12, m21, m22, baselineX - state.fontSize * m21, baselineY - state.fontSize * m22}
    page.appendItem(#move item)

    state.textMatrix.tx += cast(f32) runeCount * state.fontSize * 0.5
}

private func decodeImage(parser: *PdfParser, nodeId: u32)->Image fail
{
    let width  = parser.integer(parser.dict(nodeId, "Width"))
    let height = parser.integer(parser.dict(nodeId, "Height"))
    let bits   = parser.integer(parser.dict(nodeId, "BitsPerComponent"), 8)
    if width <= 0 or height <= 0 or width > Swag.S32.Max or height > Swag.S32.Max do
        fail InvalidFormatError{"PDF image has invalid dimensions"}
    if bits != 8 do
        fail UnsupportedFormatError{"PDF image bit depth is not supported"}

    let filter = parser.name(parser.dict(nodeId, "Filter"))
    if filter == "DCTDecode" or filter == "DCT"
    {
        let id = parser.resolve(nodeId)
        return try Image.decode(".jpg", parser.nodes[id].stream.toSlice())
    }

    let bytes      = try parser.decodeStream(nodeId)
    let colorSpace = parser.name(parser.dict(nodeId, "ColorSpace"))
    let pixelCount = cast(u64) width * cast(u64) height
    if colorSpace == "DeviceGray" or colorSpace == "G"
    {
        if bytes.count < pixelCount do
            fail InvalidFormatError{"PDF grayscale image stream is truncated"}
        var rgb: Array'u8
        rgb.resize(pixelCount * 3)
        for y in cast(u64) height
        {
            for x in cast(u64) width
            {
                let source = y * cast(u64) width + x
                let target = (cast(u64) height - y - 1) * cast(u64) width + x
                rgb[target * 3 + 0] = bytes[source]
                rgb[target * 3 + 1] = bytes[source]
                rgb[target * 3 + 2] = bytes[source]
            }
        }

        return Image.create(cast(s32) width, cast(s32) height, .RGB8, rgb.toSlice())
    }

    if colorSpace == "DeviceRGB" or colorSpace == "RGB" or !@countof(colorSpace)
    {
        if bytes.count < pixelCount * 3 do
            fail InvalidFormatError{"PDF RGB image stream is truncated"}
        var rgb: Array'u8
        rgb.resize(pixelCount * 3)
        for y in cast(u64) height
        {
            let targetY = cast(u64) height - y - 1
            for x in cast(u64) width
            {
                let source = (y * cast(u64) width + x) * 3
                let target = (targetY * cast(u64) width + x) * 3
                rgb[target + 0] = bytes[source + 0]
                rgb[target + 1] = bytes[source + 1]
                rgb[target + 2] = bytes[source + 2]
            }
        }

        return Image.create(cast(s32) width, cast(s32) height, .RGB8, rgb.toSlice())
    }

    if colorSpace == "DeviceCMYK" or colorSpace == "CMYK"
    {
        if bytes.count < pixelCount * 4 do
            fail InvalidFormatError{"PDF CMYK image stream is truncated"}
        var rgb: Array'u8
        rgb.resize(pixelCount * 3)
        for y in cast(u64) height
        {
            for x in cast(u64) width
            {
                let source = (y * cast(u64) width + x) * 4
                let target = ((cast(u64) height - y - 1) * cast(u64) width + x) * 3
                let color  = cmykColor(bytes[source + 0] / 255.0, bytes[source + 1] / 255.0, bytes[source + 2] / 255.0, bytes[source + 3] / 255.0)
                rgb[target + 0] = color.r
                rgb[target + 1] = color.g
                rgb[target + 2] = color.b
            }
        }

        return Image.create(cast(s32) width, cast(s32) height, .RGB8, rgb.toSlice())
    }

    fail UnsupportedFormatError{"PDF image color space is not supported"}
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

    var item = Item.createImage()
    item.image = try decodeImage(parser, id)
    let top    = transformPoint(state, page, 0, 1)
    let right  = transformPoint(state, page, 1, 1)
    let bottom = transformPoint(state, page, 0, 0)
    item.transform = Transform2{right.x - top.x, right.y - top.y, bottom.x - top.x, bottom.y - top.y, top.x, top.y}
    page.appendItem(#move item)
}

private func parseContent(parser: *PdfParser, page: *Page, resourcesId: u32, bytes: const [..] u8, initialState: #null const *GraphicsState = null, depth = 0'u32) fail
{
    var content = PdfParser{bytes: bytes}
    var operands: Array'u32
    var state   = initialState ? initialState![] : GraphicsState{}
    var stack:    Array'GraphicsState
    var path:     LinePathList
    var current:  #null *LinePath

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
            if operands.count do
                state.strokeWidth = operandNumber(&content, operands, operands.count - 1)

        case "g":
            if operands.count do
                state.fillColor = grayColor(content.number(operands.back()))

        case "G":
            if operands.count do
                state.strokeColor = grayColor(content.number(operands.back()))

        case "rg":
            if operands.count >= 3 do
                state.fillColor = rgbColor(content.number(operands[operands.count - 3]), content.number(operands[operands.count - 2]), content.number(operands[operands.count - 1]))

        case "RG":
            if operands.count >= 3 do
                state.strokeColor = rgbColor(content.number(operands[operands.count - 3]), content.number(operands[operands.count - 2]), content.number(operands[operands.count - 1]))

        case "k":
            if operands.count >= 4 do
                state.fillColor = cmykColor(content.number(operands[operands.count - 4]), content.number(operands[operands.count - 3]), content.number(operands[operands.count - 2]), content.number(operands[operands.count - 1]))

        case "K":
            if operands.count >= 4 do
                state.strokeColor = cmykColor(content.number(operands[operands.count - 4]), content.number(operands[operands.count - 3]), content.number(operands[operands.count - 2]), content.number(operands[operands.count - 1]))

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

        case "S":
            appendPathItem(page, &path, &state, false, true, false)
            current = null

        case "s":
            appendPathItem(page, &path, &state, false, true, true)
            current = null

        case "f", "F", "f*":
            appendPathItem(page, &path, &state, true, false, false)
            current = null

        case "B", "B*":
            appendPathItem(page, &path, &state, true, true, false)
            current = null

        case "b", "b*":
            appendPathItem(page, &path, &state, true, true, true)
            current = null

        case "n":
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

        case "Tm":
            if operands.count >= 6
            {
                let n = operands.count - 6
                state.textMatrix = Transform2{operandNumber(&content, operands, n), operandNumber(&content, operands, n + 1), operandNumber(&content, operands, n + 2), operandNumber(&content, operands, n + 3), operandNumber(&content, operands, n + 4), operandNumber(&content, operands, n + 5)}
                state.lineMatrix = state.textMatrix
            }

        case "Td", "TD":
            if operands.count >= 2
            {
                state.lineMatrix.tx += operandNumber(&content, operands, operands.count - 2)
                state.lineMatrix.ty += operandNumber(&content, operands, operands.count - 1)
                state.textMatrix    = state.lineMatrix
            }

        case "Tj", "'", "\"":
            if operands.count do
                appendText(parser, page, resourcesId, &state, content.stringValue(operands.back()))

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
                            state.textMatrix.tx -= cast(f32) content.number(id) * state.fontSize / 1000.0
                    }
                }
            }

        case "Do":
            if operands.count do
                try appendXObject(parser, page, resourcesId, &state, content.name(operands.back()), depth)

        case "BI":
            fail UnsupportedFormatError{"PDF inline images are not supported"}

        default:
            break
        }

        operands.clear()
    }
}

private func parseToUnicode(font: *FontResource, bytes: const [..] u8)
{
    var scanner   = PdfParser{bytes: bytes}
    var pending: Array'u32
    var rangeMode = false
    while scanner.pos < @countof(bytes)
    {
        scanner.skip()
        if scanner.pos >= @countof(bytes) do
            break
        let c = bytes[scanner.pos]
        if c == '<' and !scanner.startsWith("<<")
        {
            pending.add(catch scanner.parseHexString())
            continue
        }

        if isDelimiter(c)
        {
            scanner.pos += 1
            continue
        }

        let start = scanner.pos
        while scanner.pos < @countof(bytes) and !isDelimiter(bytes[scanner.pos]) do
            scanner.pos += 1
        let word = cast(string) @mkslice(@dataof(bytes) + start, scanner.pos - start)
        if word == "beginbfchar"
        {
            pending.clear()
            rangeMode = false
            continue
        }

        if word == "beginbfrange"
        {
            pending.clear()
            rangeMode = true
            continue
        }

        if word == "endbfchar"
        {
            for i in pending.count / 2
            {
                let src  = scanner.nodes[pending[i * 2]].text.toString()
                let dst  = scanner.nodes[pending[i * 2 + 1]].text.toString()
                var code = 0'u32
                for value in cast(const [..] u8) src do
                    code = code << 8 | value
                font.codeBytes = cast(u32) @countof(src)
                if @countof(dst) >= 2
                {
                    let runeValue = cast(rune) ((cast(u32) dst[0] << 8) | dst[1])
                    var builder: StrConv.StringBuilder
                    builder.appendRune(runeValue)
                    font.unicode[code] = builder.toString()
                }
            }

            pending.clear()
        }

        if word == "endbfrange" and rangeMode
        {
            for i in pending.count / 3
            {
                let firstBytes = scanner.nodes[pending[i * 3]].text.toString()
                let lastBytes  = scanner.nodes[pending[i * 3 + 1]].text.toString()
                let destBytes  = scanner.nodes[pending[i * 3 + 2]].text.toString()
                var first      = 0'u32
                var last       = 0'u32
                var dest       = 0'u32
                for value in cast(const [..] u8) firstBytes do
                    first = first << 8 | value
                for value in cast(const [..] u8) lastBytes do
                    last = last << 8 | value
                for value in cast(const [..] u8) destBytes do
                    dest = dest << 8 | value
                if first > last or last - first > 4096 do
                    continue
                font.codeBytes = cast(u32) @countof(firstBytes)
                for code in first to last
                {
                    var builder: StrConv.StringBuilder
                    builder.appendRune(cast(rune) (dest + code - first))
                    font.unicode[code] = builder.toString()
                }
            }

            pending.clear()
            rangeMode = false
        }
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
        var font: FontResource
        font.objectId = fontId
        font.name     = name[]
        font.baseName = parser.name(parser.dict(fontId, "BaseFont"))
        let descriptor = parser.dict(fontId, "FontDescriptor")
        let file2      = parser.dict(descriptor, "FontFile2")
        if file2 != InvalidNode do
            font.bytes = try parser.decodeStream(file2)
        let toUnicode = parser.dict(fontId, "ToUnicode")
        if toUnicode != InvalidNode
        {
            let cmap = try parser.decodeStream(toUnicode)
            parseToUnicode(&font, cmap.toSlice())
        }

        page.fonts.add(#move font)
    }
}

private func decodePage(parser: *PdfParser, pageId, inheritedResources, inheritedMediaBox: u32, rotate: s64)->Page fail
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

private func visitPages(parser: *PdfParser, document: *Document, nodeId, inheritedResources, inheritedMediaBox: u32, inheritedRotate: s64) fail
{
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
        var page = try decodePage(parser, id, nextResources, nextMediaBox, nextRotate)
        document.addPage(#move page)
        return
    }

    let kids = parser.dict(id, "Kids")
    if kids == InvalidNode or parser.nodes[kids].kind != .Array do
        return
    for child in parser.nodes[kids].values do
        try visitPages(parser, document, child, nextResources, nextMediaBox, nextRotate)
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

func decodeDocument(bytes: const [..] u8)->Document fail
{
    var parser = PdfParser{bytes: bytes}
    try parser.scanObjects()

    var catalog   = InvalidNode
    var info      = InvalidNode
    var encrypted = false
    for objectNumber, nodeId in parser.objects
    {
        discard objectNumber
        let id = parser.resolve(nodeId)
        if id == InvalidNode or parser.nodes[id].kind != .Dictionary do
            continue
        if parser.name(parser.dict(id, "Type")) == "Catalog" do
            catalog = id
        if parser.name(parser.dict(id, "Filter")) == "Standard" and parser.dict(id, "R") != InvalidNode do
            encrypted = true
        if parser.dict(id, "Title") != InvalidNode or parser.dict(id, "Author") != InvalidNode or parser.dict(id, "Subject") != InvalidNode or parser.dict(id, "Keywords") != InvalidNode or parser.dict(id, "Creator") != InvalidNode or parser.dict(id, "Producer") != InvalidNode do
            info = id
    }

    if encrypted do
        fail UnsupportedFormatError{"encrypted PDF documents are not supported"}
    if catalog == InvalidNode do
        fail InvalidFormatError{"PDF catalog is missing"}

    var result: retval = Document.create()
    if info != InvalidNode
    {
        result.metadata.title    = metadataString(&parser, info, "Title")
        result.metadata.author   = metadataString(&parser, info, "Author")
        result.metadata.subject  = metadataString(&parser, info, "Subject")
        result.metadata.keywords = metadataString(&parser, info, "Keywords")
        result.metadata.creator  = metadataString(&parser, info, "Creator")
        result.metadata.producer = metadataString(&parser, info, "Producer")
    }

    let pages = parser.dict(catalog, "Pages")
    if pages == InvalidNode do
        fail InvalidFormatError{"PDF page tree is missing"}
    try visitPages(&parser, &result, pages, InvalidNode, InvalidNode, 0)
    if !result.pages.count do
        fail InvalidFormatError{"PDF document has no pages"}
    return result
}
