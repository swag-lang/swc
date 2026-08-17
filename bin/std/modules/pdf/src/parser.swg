using Core, Core.Errors

private func isWhite(c: u8)->bool => c == 0 or c == 9 or c == 10 or c == 12 or c == 13 or c == 32
func isDelimiter(c: u8)->bool => isWhite(c) or c == '(' or c == ')' or c == '<' or c == '>' or c == '[' or c == ']' or c == '{' or c == '}' or c == '/' or c == '%'
func isDigit(c: u8)->bool     => c >= '0' and c <= '9'
private func isHex(c: u8)->bool => isDigit(c) or (c >= 'A' and c <= 'F') or (c >= 'a' and c <= 'f')

private func hexValue(c: u8)->u8
{
    if isDigit(c) do
        return c - '0'
    if c >= 'A' and c <= 'F' do
        return c - 'A' + 10
    return c - 'a' + 10
}

internal func decodeAscii85(data: const [..] u8)->Array'u8 fail
{
    var result: retval
    var group:  [5] u8
    var groupCount = 0'u32
    var pos        = 0'u64
    while pos < @countof(data)
    {
        let c = data[pos]
        pos += 1
        if isWhite(c) do
            continue
        if c == '<' and pos < @countof(data) and data[pos] == '~'
        {
            pos += 1
            continue
        }

        if c == '~'
        {
            if pos >= @countof(data) or data[pos] != '>' do
                fail InvalidFormatError{"ASCII85Decode stream has an invalid terminator"}
            break
        }

        if c == 'z'
        {
            if groupCount do
                fail InvalidFormatError{"ASCII85Decode stream has a misplaced zero group"}
            result.add([0'u8, 0, 0, 0])
            continue
        }

        if c < '!' or c > 'u' do
            fail InvalidFormatError{"ASCII85Decode stream contains an invalid byte"}
        group[groupCount] = c - '!'
        groupCount        += 1
        if groupCount != 5 do
            continue

        var value = 0'u64
        for digit in group do
            value = value * 85 + digit
        if value > Swag.U32.Max do
            fail InvalidFormatError{"ASCII85Decode group exceeds 32 bits"}
        result.add([cast(u8) ((value >> 24) & 0xFF), cast(u8) ((value >> 16) & 0xFF), cast(u8) ((value >> 8) & 0xFF), cast(u8) (value & 0xFF)])
        groupCount = 0
    }

    if groupCount == 1 do
        fail InvalidFormatError{"ASCII85Decode stream has an incomplete group"}
    if groupCount
    {
        let outputCount = groupCount - 1
        for i in groupCount until 5 do
            group[i] = 84
        var value = 0'u64
        for digit in group do
            value = value * 85 + digit
        if value > Swag.U32.Max do
            fail InvalidFormatError{"ASCII85Decode group exceeds 32 bits"}
        let decoded: [4] u8 = [cast(u8) ((value >> 24) & 0xFF), cast(u8) ((value >> 16) & 0xFF), cast(u8) ((value >> 8) & 0xFF), cast(u8) (value & 0xFF)]
        for i in outputCount do
            result.add(decoded[i])
    }

    return result
}

internal func decodeRunLength(data: const [..] u8)->Array'u8 fail
{
    var result: retval
    var pos = 0'u64
    while pos < @countof(data)
    {
        let length = data[pos]
        pos += 1
        if length == 128 do
            break
        if length <= 127
        {
            let count = cast(u64) length + 1
            if pos + count > @countof(data) do
                fail InvalidFormatError{"RunLengthDecode literal run is truncated"}
            result.add(data[pos until pos + count])
            pos += count
            continue
        }

        if pos >= @countof(data) do
            fail InvalidFormatError{"RunLengthDecode repeated run is truncated"}
        let value = data[pos]
        pos += 1
        for cast(u64) (257 - cast(u32) length) do
            result.add(value)
    }

    return result
}

impl PdfParser
{
    mtd skip()
    {
        while .pos < @countof(.bytes)
        {
            if isWhite(.bytes[.pos])
            {
                .pos += 1
                continue
            }

            if .bytes[.pos] != '%' do
                break
            while .pos < @countof(.bytes) and .bytes[.pos] != '\n' and .bytes[.pos] != '\r' do
                .pos += 1
        }
    }

    mtd startsWith(text: string)->bool
    {
        if .pos + @countof(text) > @countof(.bytes) do
            return false
        return !Memory.compare(@dataof(.bytes) + .pos, @dataof(text), @countof(text))
    }

    mtd consumeWord(text: string)->bool
    {
        .skip()
        if !.startsWith(text) do
            return false
        let end = .pos + @countof(text)
        if end < @countof(.bytes) and !isDelimiter(.bytes[end]) do
            return false
        .pos = end
        return true
    }

    mtd addNode(node: #move Node)->u32
    {
        let result = cast(u32) .nodes.count
        .nodes.add(#move node)
        return result
    }

    mtd parseUnsigned(value: *u64)->bool
    {
        .skip()
        if .pos >= @countof(.bytes) or !isDigit(.bytes[.pos]) do
            return false
        var result = 0'u64
        while .pos < @countof(.bytes) and isDigit(.bytes[.pos])
        {
            let digit = cast(u64) (.bytes[.pos] - '0')
            if result > (Swag.U64.Max - digit) / 10 do
                return false
            result = result * 10 + digit
            .pos   += 1
        }

        value[] = result
        return true
    }

    mtd parseNumber()->u32 fail
    {
        .skip()
        let start = .pos
        if .pos < @countof(.bytes) and (.bytes[.pos] == '+' or .bytes[.pos] == '-') do
            .pos += 1
        var hasDigit = false
        var hasDot   = false
        while .pos < @countof(.bytes)
        {
            let c = .bytes[.pos]
            if isDigit(c)
            {
                hasDigit = true
                .pos     += 1
                continue
            }

            if c == '.' and !hasDot
            {
                hasDot = true
                .pos   += 1
                continue
            }

            break
        }

        if !hasDigit do
            fail InvalidFormatError{"PDF number has no digits"}

        let spelling = cast(string) @mkslice(@dataof(.bytes) + start, .pos - start)
        if !hasDot
        {
            let first      = try StrConv.toS64(spelling)
            let afterFirst = .pos
            var generation = 0'u64
            if first >= 0 and .parseUnsigned(&generation) and .consumeWord("R")
            {
                if cast(u64) first > Swag.U32.Max do
                    fail UnsupportedFormatError{"PDF object number exceeds 32 bits"}
                var reference: Node
                reference.kind      = .Reference
                reference.reference = cast(u32) first
                return .addNode(#move reference)
            }

            .pos = afterFirst
            var integer: Node
            integer.kind    = .Integer
            integer.integer = first
            integer.real    = try StrConv.toF64(spelling)
            return .addNode(#move integer)
        }

        var real: Node
        real.kind = .Real
        real.real = try StrConv.toF64(spelling)
        return .addNode(#move real)
    }

    mtd parseName()->u32 fail
    {
        Debug.assert(.bytes[.pos] == '/')
        .pos += 1
        var node: Node
        node.kind = .Name
        while .pos < @countof(.bytes) and !isDelimiter(.bytes[.pos])
        {
            if .bytes[.pos] == '#' and .pos + 2 < @countof(.bytes) and isHex(.bytes[.pos + 1]) and isHex(.bytes[.pos + 2])
            {
                node.text += hexValue(.bytes[.pos + 1]) * 16 + hexValue(.bytes[.pos + 2])
                .pos      += 3
            }
            else
            {
                node.text += .bytes[.pos]
                .pos      += 1
            }
        }

        return .addNode(#move node)
    }

    mtd parseLiteralString()->u32 fail
    {
        Debug.assert(.bytes[.pos] == '(')
        .pos += 1
        var depth = 1'u32
        var node: Node
        node.kind = .String
        while .pos < @countof(.bytes) and depth
        {
            var c = .bytes[.pos]
            .pos += 1
            if c == '\\'
            {
                if .pos >= @countof(.bytes) do
                    break
                c    = .bytes[.pos]
                .pos += 1
                switch c
                {
                case 'n':
                    node.text += '\n'

                case 'r':
                    node.text += '\r'

                case 't':
                    node.text += '\t'

                case 'b':
                    node.text += 8'u8

                case 'f':
                    node.text += 12'u8

                case '\n':
                    continue

                case '\r':
                    if .pos < @countof(.bytes) and .bytes[.pos] == '\n' do
                        .pos += 1
                    continue

                default:
                    if c >= '0' and c <= '7'
                    {
                        var value = cast(u32) (c - '0')
                        for 2 where .pos < @countof(.bytes) and .bytes[.pos] >= '0' and .bytes[.pos] <= '7'
                        {
                            value = value * 8 + .bytes[.pos] - '0'
                            .pos  += 1
                        }

                        node.text += cast #bit (u8) value
                    }
                    else do
                        node.text += c
                }

                continue
            }

            if c == '('
            {
                depth     += 1
                node.text += c
                continue
            }

            if c == ')'
            {
                depth -= 1
                if depth do
                    node.text += c
                continue
            }

            node.text += c
        }

        if depth do
            fail InvalidFormatError{"PDF literal string is not closed"}
        return .addNode(#move node)
    }

    mtd parseHexString()->u32 fail
    {
        Debug.assert(.bytes[.pos] == '<' and !.startsWith("<<"))
        .pos += 1
        var node: Node
        node.kind = .String
        var high = Swag.U8.Max
        while .pos < @countof(.bytes) and .bytes[.pos] != '>'
        {
            let c = .bytes[.pos]
            .pos += 1
            if isWhite(c) do
                continue
            if !isHex(c) do
                fail InvalidFormatError{"PDF hexadecimal string contains a non-hexadecimal byte"}
            let value = hexValue(c)
            if high == Swag.U8.Max do
                high = value
            else
            {
                node.text += high * 16 + value
                high      = Swag.U8.Max
            }
        }

        if .pos >= @countof(.bytes) do
            fail InvalidFormatError{"PDF hexadecimal string is not closed"}
        .pos += 1
        if high != Swag.U8.Max do
            node.text += high * 16
        return .addNode(#move node)
    }

    mtd parseArray()->u32 fail
    {
        Debug.assert(.bytes[.pos] == '[')
        .pos += 1
        var node: Node
        node.kind = .Array
        for
        {
            .skip()
            if .pos >= @countof(.bytes) do
                fail InvalidFormatError{"PDF array is not closed"}
            if .bytes[.pos] == ']'
            {
                .pos += 1
                break
            }

            node.values.add(try .parseValue())
        }

        return .addNode(#move node)
    }

    mtd parseDictionary()->u32 fail
    {
        Debug.assert(.startsWith("<<"))
        .pos += 2
        var node: Node
        node.kind = .Dictionary
        for
        {
            .skip()
            if .startsWith(">>")
            {
                .pos += 2
                break
            }

            if .pos >= @countof(.bytes) or .bytes[.pos] != '/' do
                fail InvalidFormatError{"PDF dictionary needs a name key"}
            let keyNode = try .parseName()
            let key     = .nodes[keyNode].text
            node.entries[key] = try .parseValue()
        }

        return .addNode(#move node)
    }

    mtd parseValue()->u32 fail
    {
        .skip()
        if .pos >= @countof(.bytes) do
            fail InvalidFormatError{"PDF value is missing"}
        let c = .bytes[.pos]
        if c == '/' do
            return try .parseName()
        if c == '(' do
            return try .parseLiteralString()
        if c == '[' do
            return try .parseArray()
        if c == '<'
        {
            if .startsWith("<<") do
                return try .parseDictionary()
            return try .parseHexString()
        }

        if isDigit(c) or c == '+' or c == '-' or c == '.' do
            return try .parseNumber()

        var node: Node
        if .consumeWord("true")
        {
            node.kind    = .Boolean
            node.boolean = true
        }
        elif .consumeWord("false") do
            node.kind = .Boolean
        elif !.consumeWord("null") do
            fail InvalidFormatError{"PDF value uses an unknown token"}
        return .addNode(#move node)
    }

    mtd findFrom(start: u64, text: string)->u64
    {
        if !@countof(text) or start >= @countof(.bytes) do
            return Swag.U64.Max
        let last = @countof(.bytes) - @countof(text)
        if start > last do
            return Swag.U64.Max
        for i in start to last
        {
            if !Memory.compare(@dataof(.bytes) + i, @dataof(text), @countof(text)) do
                return i
        }

        return Swag.U64.Max
    }

    mtd attachStream(nodeId: u32) fail
    {
        let saved = .pos
        if !.consumeWord("stream")
        {
            .pos = saved
            return
        }

        if .pos < @countof(.bytes) and .bytes[.pos] == '\r' do
            .pos += 1
        if .pos < @countof(.bytes) and .bytes[.pos] == '\n' do
            .pos += 1
        let start          = .pos
        let declaredLength = .integer(.dict(nodeId, "Length"), -1)
        if declaredLength >= 0
        {
            let length = cast(u64) declaredLength
            if length > @countof(.bytes) - start do
                fail InvalidFormatError{"PDF stream exceeds its declared length"}
            .nodes[nodeId].stream = @mkslice(@dataof(.bytes) + start, length)
            .pos = start + length
            if !.consumeWord("endstream") do
                fail InvalidFormatError{"PDF stream length does not end at endstream"}
            return
        }

        let end = .findFrom(start, "endstream")
        if end == Swag.U64.Max do
            fail InvalidFormatError{"PDF stream has no endstream marker"}
        var length = end - start
        while length and (.bytes[start + length - 1] == '\n' or .bytes[start + length - 1] == '\r') do
            length -= 1
        .nodes[nodeId].stream = @mkslice(@dataof(.bytes) + start, length)
        .pos = end + @countof("endstream")
    }

    mtd scanObjects() fail
    {
        if @countof(.bytes) < 8 or !.startsWith("%PDF-") do
            fail InvalidFormatError{"input has no PDF header"}
        while .pos < @countof(.bytes)
        {
            let start        = .pos
            var objectNumber = 0'u64
            var generation   = 0'u64
            if !.parseUnsigned(&objectNumber) or !.parseUnsigned(&generation) or !.consumeWord("obj")
            {
                .pos = start + 1
                continue
            }

            if objectNumber > Swag.U32.Max do
                fail UnsupportedFormatError{"PDF object number exceeds 32 bits"}
            let nodeId = try .parseValue()
            if .nodes[nodeId].kind == .Dictionary do
                try .attachStream(nodeId)
            .objects[cast(u32) objectNumber] = nodeId
            discard .consumeWord("endobj")
        }

        try .expandObjectStreams()
    }

    mtd importNode(source: const *PdfParser, sourceId: u32, imported: *HashTable'(u32, u32))->u32
    {
        let existing = imported.tryFind(sourceId)
        if existing do
            return existing.value

        let sourceNode = &source.nodes[sourceId]
        var node: Node
        node.kind      = sourceNode.kind
        node.integer   = sourceNode.integer
        node.real      = sourceNode.real
        node.boolean   = sourceNode.boolean
        node.text      = sourceNode.text
        node.reference = sourceNode.reference
        node.stream    = sourceNode.stream
        let result = .addNode(#move node)
        imported[sourceId] = result

        for value in sourceNode.values do
            .nodes[result].values.add(.importNode(source, value, imported))
        for key, value in sourceNode.entries do
            .nodes[result].entries[key[]] = .importNode(source, value, imported)
        return result
    }

    mtd expandObjectStreams() fail
    {
        var streams: Array'u32
        for objectNumber, nodeId in .objects
        {
            discard objectNumber
            let id = .resolve(nodeId)
            if id != InvalidNode and .name(.dict(id, "Type")) == "ObjStm" do
                streams.add(id)
        }

        for streamId in streams
        {
            let count = .integer(.dict(streamId, "N"))
            let first = .integer(.dict(streamId, "First"))
            if count < 0 or first < 0 do
                fail InvalidFormatError{"PDF object stream has invalid bounds"}
            let decoded = try .decodeStream(streamId)
            if cast(u64) first > decoded.count do
                fail InvalidFormatError{"PDF object stream header exceeds its data"}

            var embedded = PdfParser{bytes: decoded.toSlice()}
            var numbers: Array'u32
            var offsets: Array'u64
            for cast(u64) count
            {
                var number = 0'u64
                var offset = 0'u64
                if !embedded.parseUnsigned(&number) or !embedded.parseUnsigned(&offset) or number > Swag.U32.Max do
                    fail InvalidFormatError{"PDF object stream header is malformed"}
                numbers.add(cast(u32) number)
                offsets.add(offset)
            }

            for number, index in numbers
            {
                let position = cast(u64) first + offsets[index]
                if position >= decoded.count do
                    fail InvalidFormatError{"PDF object stream entry exceeds its data"}
                embedded.pos = position
                let sourceId = try embedded.parseValue()
                var imported: HashTable'(u32, u32)
                .objects[number] = .importNode(&embedded, sourceId, &imported)
            }
        }
    }

    mtd const resolve(nodeId: u32)->u32
    {
        var result = nodeId
        for 32
        {
            if result >= .nodes.count or .nodes[result].kind != .Reference do
                return result
            let entry = .objects.tryFind(.nodes[result].reference)
            if !entry do
                return InvalidNode
            result = entry.value
        }

        return InvalidNode
    }

    mtd const dictRaw(nodeId: u32, key: string)->u32
    {
        let id = .resolve(nodeId)
        if id == InvalidNode or .nodes[id].kind != .Dictionary do
            return InvalidNode
        let entry = .nodes[id].entries.tryFind(key)
        return entry ? entry.value : InvalidNode
    }

    mtd const dict(nodeId: u32, key: string)->u32 => .resolve(.dictRaw(nodeId, key))

    mtd const name(nodeId: u32)->string
    {
        let id = .resolve(nodeId)
        return id != InvalidNode and .nodes[id].kind == .Name ? .nodes[id].text.toString() : ""
    }

    mtd const integer(nodeId: u32, fallback = 0's64)->s64
    {
        let id = .resolve(nodeId)
        if id == InvalidNode do
            return fallback
        if .nodes[id].kind == .Integer do
            return .nodes[id].integer
        return fallback
    }

    mtd const number(nodeId: u32, fallback = 0.0)->f64
    {
        let id = .resolve(nodeId)
        if id == InvalidNode do
            return fallback
        if .nodes[id].kind == .Integer do
            return .nodes[id].real
        if .nodes[id].kind == .Real do
            return .nodes[id].real
        return fallback
    }

    mtd const stringValue(nodeId: u32)->string
    {
        let id = .resolve(nodeId)
        return id != InvalidNode and .nodes[id].kind == .String ? .nodes[id].text.toString() : ""
    }

    mtd decodeStream(nodeId: u32)->Array'u8 fail
    {
        let id = .resolve(nodeId)
        if id == InvalidNode or .nodes[id].kind != .Dictionary do
            fail InvalidFormatError{"PDF stream dictionary is missing"}
        var result: Array'u8 = .nodes[id].stream
        let filterId         = .dict(id, "Filter")
        if filterId == InvalidNode do
            return result

        var filters: Array'String
        if .nodes[filterId].kind == .Name do
            filters.add(.nodes[filterId].text)
        elif .nodes[filterId].kind == .Array
        {
            for value in .nodes[filterId].values
            {
                let name = .name(value)
                if @countof(name) do
                    filters.add(name)
            }
        }

        for filter in filters
        {
            switch filter.toString()
            {
            case "FlateDecode", "Fl":
                var zlib: Compress.ZLib
                result = try zlib.decompress(result.toSlice())
                let parameters = .dict(id, "DecodeParms")
                if parameters != InvalidNode do
                    result = try .applyPredictor(result.toSlice(), parameters)

            case "ASCIIHexDecode", "AHx":
                var decoded: Array'u8
                var high = Swag.U8.Max
                for c in result
                {
                    if isWhite(c) do
                        continue
                    if c == '>' do
                        break
                    if !isHex(c) do
                        fail InvalidFormatError{"ASCIIHexDecode stream contains a non-hexadecimal byte"}
                    let value = hexValue(c)
                    if high == Swag.U8.Max do
                        high = value
                    else
                    {
                        decoded.add(high * 16 + value)
                        high = Swag.U8.Max
                    }
                }

                if high != Swag.U8.Max do
                    decoded.add(high * 16)
                result = #move decoded

            case "ASCII85Decode", "A85":
                result = try decodeAscii85(result.toSlice())

            case "RunLengthDecode", "RL":
                result = try decodeRunLength(result.toSlice())

            default:
                fail UnsupportedFormatError{"PDF stream filter is not supported"}
            }
        }

        return result
    }

    mtd applyPredictor(data: const [..] u8, parametersId: u32)->Array'u8 fail
    {
        let predictor = .integer(.dict(parametersId, "Predictor"), 1)
        if predictor <= 1
        {
            var result: retval = data
            return result
        }

        let colors  = .integer(.dict(parametersId, "Colors"), 1)
        let bits    = .integer(.dict(parametersId, "BitsPerComponent"), 8)
        let columns = .integer(.dict(parametersId, "Columns"), 1)
        if colors <= 0 or bits <= 0 or columns <= 0 do
            fail InvalidFormatError{"PDF predictor has invalid dimensions"}
        if bits != 8 do
            fail UnsupportedFormatError{"PDF predictor bit depth is not supported"}
        let bytesPerPixel = cast(u64) colors
        let rowBytes      = cast(u64) colors * cast(u64) columns

        if predictor == 2
        {
            if @countof(data) % rowBytes do
                fail InvalidFormatError{"PDF TIFF predictor rows are truncated"}
            var result: retval = data
            for row in @countof(data) / rowBytes
            {
                let base = row * rowBytes
                for x in bytesPerPixel until rowBytes do
                    result[base + x] += #wrap result[base + x - bytesPerPixel]
            }

            return result
        }

        if predictor < 10 or predictor > 15 do
            fail UnsupportedFormatError{"PDF stream predictor is not supported"}

        let encodedRow = rowBytes + 1
        if @countof(data) % encodedRow do
            fail InvalidFormatError{"PDF PNG predictor rows are truncated"}
        var result: retval
        result.resize(@countof(data) / encodedRow * rowBytes)
        for row in @countof(data) / encodedRow
        {
            let source = row * encodedRow
            let target = row * rowBytes
            let filter = data[source]
            if filter > 4 do
                fail InvalidFormatError{"PDF PNG predictor has an invalid filter"}
            for x in rowBytes
            {
                let raw  = data[source + 1 + x]
                let left = x >= bytesPerPixel ? result[target + x - bytesPerPixel] : 0'u8
                let up   = row ? result[target - rowBytes + x] : 0'u8
                let ul   = row and x >= bytesPerPixel ? result[target - rowBytes + x - bytesPerPixel] : 0'u8
                switch filter
                {
                case 0:
                    result[target + x] = raw

                case 1:
                    result[target + x] = cast #bit (u8) (raw + #wrap left)

                case 2:
                    result[target + x] = cast #bit (u8) (raw + #wrap up)

                case 3:
                    result[target + x] = cast #bit (u8) (raw + #wrap cast(u8) ((cast(u32) left + up) / 2))

                case 4:
                    let p       = cast(s32) left + cast(s32) up - cast(s32) ul
                    let pa      = Math.abs(p - cast(s32) left)
                    let pb      = Math.abs(p - cast(s32) up)
                    let pc      = Math.abs(p - cast(s32) ul)
                    let predict = pa <= pb and pa <= pc ? left : (pb <= pc ? up : ul)
                    result[target + x] = cast #bit (u8) (raw + #wrap predict)
                }
            }
        }

        return result
    }
}
