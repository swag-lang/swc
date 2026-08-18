#global namespace Pdf

using Core, Core.Errors

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

    // Resolves a forward indirect integer before the main object scan has reached it. Stream
    // lengths are commonly stored in the object immediately after the stream, and scanning for
    // `endstream` cannot distinguish a delimiter newline from a final data byte with value 10.
    mtd findForwardIntegerObject(objectNumber: u32)->s64
    {
        var probe = PdfParser{bytes: .bytes, pos: .pos}
        while probe.pos < @countof(probe.bytes)
        {
            let start = probe.pos
            var number, generation: u64
            if probe.parseUnsigned(&number) and probe.parseUnsigned(&generation) and number == objectNumber and probe.consumeWord("obj")
            {
                let valueId = catch probe.parseValue() as parseError
                if parseError == null and probe.nodes[valueId].kind == .Integer do
                    return probe.nodes[valueId].integer
            }

            probe.pos = start + 1
        }

        return -1
    }

    mtd declaredStreamLength(nodeId: u32)->s64
    {
        let raw = .dictRaw(nodeId, "Length")
        let id  = .resolve(raw)
        if id != InvalidNode and .nodes[id].kind == .Integer do
            return .nodes[id].integer
        if raw != InvalidNode and .nodes[raw].kind == .Reference do
            return .findForwardIntegerObject(.nodes[raw].reference)
        return -1
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
        let declaredLength = .declaredStreamLength(nodeId)
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
        // The header is located within a bounded prefix rather than required at byte zero: a
        // file recovered from a mail body or a sloppy concatenation carries a preamble, and
        // every offset in the file is relative to the header, not to the container around it.
        const HeaderSearchLimit = 1024'u64
        var headerPos = Swag.U64.Max
        if @countof(.bytes) >= 8
        {
            let last = Math.min(@countof(.bytes) - 5, HeaderSearchLimit)
            for i in 0 to last
            {
                if !Memory.compare(@dataof(.bytes) + i, @dataof("%PDF-"), 5)
                {
                    headerPos = i
                    break
                }
            }
        }

        if headerPos == Swag.U64.Max do
            fail InvalidFormatError{"input has no PDF header"}
        if headerPos do
            .bytes = @mkslice(@dataof(.bytes) + headerPos, @countof(.bytes) - headerPos)
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
        .scanTrailers()
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

        // Recursive imports can grow the node array, so reacquire the destination after
        // each child returns.
        for value in sourceNode.values
        {
            let importedValue = .importNode(source, value, imported)
            .nodes[result].values.add(importedValue)
        }

        for key, value in sourceNode.entries
        {
            let importedValue = .importNode(source, value, imported)
            .nodes[result].entries[key[]] = importedValue
        }

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

    // Records the document roots named by every trailer and cross-reference stream.
    //
    // The object scan above is deliberately position-independent, so the trailer is read
    // for the entries only it carries: which object is the catalog, which one holds the
    // metadata, and whether the file declares encryption. A file whose trailer is damaged
    // still decodes through the catalog search in `decodeDocument`.
    mtd scanTrailers()
    {
        for objectNumber, nodeId in .objects
        {
            discard objectNumber
            let id = .resolve(nodeId)
            if id != InvalidNode and .name(.dict(id, "Type")) == "XRef" do
                .recordTrailer(id)
        }

        var search = 0'u64
        for
        {
            let found = .findFrom(search, "trailer")
            if found == Swag.U64.Max do
                break
            search = found + @countof("trailer")
            .pos   = search
            .skip()
            if !.startsWith("<<") do
                continue
            let dictId = catch .parseDictionary() as parseError
            if parseError == null do
                .recordTrailer(dictId)
        }
    }

    mtd recordTrailer(dictId: u32)
    {
        // The newest trailer of an incrementally updated file wins, and a trailer that
        // only carries /Prev never overwrites an entry it does not name.
        let root = .dict(dictId, "Root")
        if root != InvalidNode and .name(.dict(root, "Type")) == "Catalog" do
            .trailerRoot = root
        let info = .dict(dictId, "Info")
        if info != InvalidNode and .nodes[info].kind == .Dictionary do
            .trailerInfo = info
        if .dictRaw(dictId, "Encrypt") != InvalidNode do
            .isEncrypted = true
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

    mtd const boolean(nodeId: u32, fallback = false)->bool
    {
        let id = .resolve(nodeId)
        if id == InvalidNode or .nodes[id].kind != .Boolean do
            return fallback
        return .nodes[id].boolean
    }

    mtd const stringValue(nodeId: u32)->string
    {
        let id = .resolve(nodeId)
        return id != InvalidNode and .nodes[id].kind == .String ? .nodes[id].text.toString() : ""
    }

    // Returns the names of the filters applied to a stream, outermost first.
    mtd const streamFilters(nodeId: u32)->Array'String
    {
        var result: retval
        let filterId = .dict(nodeId, "Filter")
        if filterId == InvalidNode do
            return result
        if .nodes[filterId].kind == .Name
        {
            result.add(.nodes[filterId].text)
            return result
        }

        if .nodes[filterId].kind != .Array do
            return result
        for value in .nodes[filterId].values
        {
            let name = .name(value)
            if @countof(name) do
                result.add(name)
        }

        return result
    }

    // Returns the parameter dictionary that applies to the filter at `index`.
    mtd const filterParameters(nodeId: u32, index: u64)->u32
    {
        let parametersId = .dict(nodeId, "DecodeParms")
        if parametersId == InvalidNode do
            return InvalidNode
        if .nodes[parametersId].kind != .Array do
            return parametersId
        if index >= .nodes[parametersId].values.count do
            return InvalidNode
        return .resolve(.nodes[parametersId].values[index])
    }

    // Returns the name of the trailing image codec of a stream, or an empty string.
    //
    // These codecs carry their own container, so they are handed to the image decoder
    // whole instead of being expanded into samples by decodeStream.
    mtd const imageCodec(nodeId: u32)->String
    {
        var result: retval
        let filters = .streamFilters(nodeId)
        if !filters.count do
            return result
        switch filters.back().toString()
        {
        case "DCTDecode", "DCT", "JPXDecode", "JBIG2Decode", "CCITTFaxDecode", "CCF": result = filters.back()
        }

        return result
    }

    // Expands a stream through its filter chain.
    //
    // With `stopAtImageCodec`, a trailing image codec is left untouched and its input
    // bytes are returned, which is what imageCodec names.
    mtd decodeStream(nodeId: u32, stopAtImageCodec = false)->Array'u8 fail
    {
        let id = .resolve(nodeId)
        if id == InvalidNode or .nodes[id].kind != .Dictionary do
            fail InvalidFormatError{"PDF stream dictionary is missing"}
        var result: Array'u8 = .nodes[id].stream
        let filters          = .streamFilters(id)
        var count            = filters.count
        if stopAtImageCodec and count and @countof(.imageCodec(id)) do
            count -= 1

        for index in count
        {
            let parameters = .filterParameters(id, index)
            switch filters[index].toString()
            {
            case "FlateDecode", "Fl":
                var zlib: Compress.ZLib
                result = try zlib.decompress(result.toSlice())
                if parameters != InvalidNode do
                    result = try .applyPredictor(result.toSlice(), parameters)

            case "LZWDecode", "LZW":
                let earlyChange = .integer(.dict(parameters, "EarlyChange"), 1) != 0
                result = try decodeLzw(result.toSlice(), earlyChange)
                if parameters != InvalidNode do
                    result = try .applyPredictor(result.toSlice(), parameters)

            case "ASCIIHexDecode", "AHx":
                result = try decodeAsciiHex(result.toSlice())

            case "ASCII85Decode", "A85":
                result = try decodeAscii85(result.toSlice())

            case "RunLengthDecode", "RL":
                result = try decodeRunLength(result.toSlice())

            case "Crypt":
                break

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
        if bits != 1 and bits != 2 and bits != 4 and bits != 8 and bits != 16 do
            fail UnsupportedFormatError{"PDF predictor bit depth is not supported"}
        let sampleBits    = cast(u64) colors * cast(u64) bits
        let bytesPerPixel = Math.max(1'u64, (sampleBits + 7) / 8)
        let rowBytes      = (sampleBits * cast(u64) columns + 7) / 8

        if predictor == 2
        {
            // The TIFF predictor accumulates per component, so a sample must be a whole
            // number of bytes for the sum to stay inside one component.
            if bits != 8 and bits != 16 do
                fail UnsupportedFormatError{"PDF TIFF predictor bit depth is not supported"}
            if @countof(data) % rowBytes do
                fail InvalidFormatError{"PDF TIFF predictor rows are truncated"}
            var result: retval = data
            let stride         = cast(u64) colors * cast(u64) (bits / 8)
            for row in @countof(data) / rowBytes
            {
                let base = row * rowBytes
                for x in stride until rowBytes do
                    result[base + x] += #wrap result[base + x - stride]
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
