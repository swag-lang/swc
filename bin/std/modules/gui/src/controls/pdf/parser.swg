#global namespace Pdf

using Core, Core.Errors

impl PdfParser
{
    mtd skip()
    {
        while .pos < .bytes.count
        {
            if isWhite(.bytes[.pos])
            {
                .pos += 1
                continue
            }

            if .bytes[.pos] != '%' do
                break
            while .pos < .bytes.count and .bytes[.pos] != '\n' and .bytes[.pos] != '\r' do
                .pos += 1
        }
    }

    mtd startsWith(text: string)->bool
    {
        if .pos + text.count > .bytes.count do
            return false
        return !Memory.compare(.bytes.buffer + .pos, text.buffer, text.count)
    }

    mtd consumeWord(text: string)->bool
    {
        .skip()
        if !.startsWith(text) do
            return false
        let end = .pos + text.count
        if end < .bytes.count and !isDelimiter(.bytes[end]) do
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
        if .pos >= .bytes.count or !isDigit(.bytes[.pos]) do
            return false
        var result = 0'u64
        while .pos < .bytes.count and isDigit(.bytes[.pos])
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
        if .pos < .bytes.count and (.bytes[.pos] == '+' or .bytes[.pos] == '-') do
            .pos += 1
        var hasDigit = false
        var hasDot   = false
        while .pos < .bytes.count
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

        let spelling = cast(string) Swag.makeSlice(.bytes.buffer + start, .pos - start)
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
                reference.kind                = .Reference
                reference.reference           = cast(u32) first
                reference.referenceGeneration = generation <= Swag.U16.Max ? cast(u16) generation : 0
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
        while .pos < .bytes.count and !isDelimiter(.bytes[.pos])
        {
            if .bytes[.pos] == '#' and .pos + 2 < .bytes.count and isHex(.bytes[.pos + 1]) and isHex(.bytes[.pos + 2])
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
        while .pos < .bytes.count and depth
        {
            var c = .bytes[.pos]
            .pos += 1
            if c == '\\'
            {
                if .pos >= .bytes.count do
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
                    if .pos < .bytes.count and .bytes[.pos] == '\n' do
                        .pos += 1
                    continue

                default:
                    if c >= '0' and c <= '7'
                    {
                        var value = cast(u32) (c - '0')
                        for 2 where .pos < .bytes.count and .bytes[.pos] >= '0' and .bytes[.pos] <= '7'
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
        while .pos < .bytes.count and .bytes[.pos] != '>'
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

        if .pos >= .bytes.count do
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
            if .pos >= .bytes.count do
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

            if .pos >= .bytes.count or .bytes[.pos] != '/' do
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
        if .pos >= .bytes.count do
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
        if !text.count or start >= .bytes.count do
            return Swag.U64.Max
        let last = .bytes.count - text.count
        if start > last do
            return Swag.U64.Max
        for i in start to last
        {
            if !Memory.compare(.bytes.buffer + i, text.buffer, text.count) do
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
        while probe.pos < probe.bytes.count
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

        if .pos < .bytes.count and .bytes[.pos] == '\r' do
            .pos += 1
        if .pos < .bytes.count and .bytes[.pos] == '\n' do
            .pos += 1
        let start          = .pos
        let declaredLength = .declaredStreamLength(nodeId)
        if declaredLength >= 0
        {
            let length = cast(u64) declaredLength
            if length > .bytes.count - start do
                fail InvalidFormatError{"PDF stream exceeds its declared length"}
            .nodes[nodeId].stream = Swag.makeSlice(.bytes.buffer + start, length)
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
        .nodes[nodeId].stream = Swag.makeSlice(.bytes.buffer + start, length)
        .pos = end + ("endstream").count
    }

    // Positions the file on its header and drops anything written before it.
    //
    // The header is located within a bounded prefix rather than required at byte zero: a file
    // recovered from a mail body or a sloppy concatenation carries a preamble, and every offset
    // in the file is relative to the header, not to the container around it.
    mtd locateHeader() fail
    {
        const HeaderSearchLimit = 1024'u64
        var headerPos = Swag.U64.Max
        if .bytes.count >= 8
        {
            let last = Math.min(.bytes.count - 5, HeaderSearchLimit)
            for i in 0 to last
            {
                if !Memory.compare(.bytes.buffer + i, ("%PDF-").buffer, 5)
                {
                    headerPos = i
                    break
                }
            }
        }

        if headerPos == Swag.U64.Max do
            fail InvalidFormatError{"input has no PDF header"}
        if headerPos do
            .bytes = Swag.makeSlice(.bytes.buffer + headerPos, .bytes.count - headerPos)
    }

    // Parses every object in the file, keeping the last definition of each number.
    //
    // This is the repair path, not the primary one: it costs the whole file and cannot tell
    // `5 0 obj` from `5 1 obj`. It runs once, when the cross-reference chain is missing,
    // damaged, or points somewhere an object is not.
    mtd scanObjects() fail
    {
        // An object the index already produced is the one the file's own trailer chose. Every
        // other number keeps the last definition the scan meets, which is the only ordering a
        // file with no usable index offers.
        var indexed: HashTable'(u32, bool)
        for number, nodeId in .objects
        {
            discard nodeId
            indexed[number] = true
        }

        .hasScanned = true
        .pos        = 0
        while .pos < .bytes.count
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

            if !indexed.tryFind(cast(u32) objectNumber) do
                .objects[cast(u32) objectNumber] = nodeId
            discard .consumeWord("endobj")
        }

        try .expandObjectStreams()
        .scanTrailers()
    }

    // Runs the repair scan once, and only once.
    mtd ensureScanned()
    {
        if .hasScanned do
            return
        catch .scanObjects() as scanError
        discard scanError
        .hasScanned = true
    }

    // Follows `startxref` and the `/Prev` chain, newest section first.
    //
    // Reading the index is what an incremental update means: a revision that reinstates an
    // earlier object has to win over the one it replaced, and file order cannot say which of
    // two definitions is the newer. Returns whether anything usable was found; a file whose
    // index is damaged falls back to the scan.
    mtd readXrefChain()->bool
    {
        var next = .findStartXref()
        if next == Swag.U64.Max do
            return false

        var visited: Array'u64
        for 64
        {
            if next >= .bytes.count do
                break

            var seen = false
            for offset in visited where offset == next
            {
                seen = true
                break
            }

            if seen do
                break
            visited.add(next)

            let section = .readXrefSection(next)
            if !section.ok or !section.hasPrev do
                break
            next = section.prev
        }

        return .xref.count != 0
    }

    // Returns the offset the last `startxref` of the file names.
    mtd findStartXref()->u64
    {
        const TailSearchLimit = 2048'u64
        let size = .bytes.count
        if size < 9 do
            return Swag.U64.Max

        var probe = size > TailSearchLimit ? size - TailSearchLimit : 0
        var found = Swag.U64.Max
        for
        {
            let at = .findFrom(probe, "startxref")
            if at == Swag.U64.Max do
                break
            found = at
            probe = at + 1
        }

        if found == Swag.U64.Max do
            return Swag.U64.Max
        .pos = found + ("startxref").count
        var offset = 0'u64
        if !.parseUnsigned(&offset) do
            return Swag.U64.Max
        return offset
    }

    // Reads one section of the chain, in whichever of the two forms it is written.
    mtd readXrefSection(offset: u64)->{ ok, hasPrev: bool, prev: u64 }
    {
        var result: retval
        if offset >= .bytes.count do
            return result
        .pos = offset
        if .consumeWord("xref") do
            return .readClassicXref()
        return .readXrefStreamSection(offset)
    }

    // Reads a classic cross-reference table and the trailer that follows it.
    mtd readClassicXref()->{ ok, hasPrev: bool, prev: u64 }
    {
        var result: retval
        for
        {
            .skip()
            if .startsWith("trailer") do
                break

            var first = 0'u64
            var count = 0'u64
            if !.parseUnsigned(&first) or !.parseUnsigned(&count) do
                return result
            if first > Swag.U32.Max or count > Swag.U32.Max do
                return result

            for i in count
            {
                var position   = 0'u64
                var generation = 0'u64
                if !.parseUnsigned(&position) or !.parseUnsigned(&generation) do
                    return result
                .skip()
                if .pos >= .bytes.count do
                    return result
                let kind = .bytes[.pos]
                .pos += 1

                let number = first + i
                if number > Swag.U32.Max do
                    continue

                var entry: XrefEntry
                entry.generation = generation <= Swag.U16.Max ? cast(u16) generation : 0
                if kind == 'n'
                {
                    entry.kind   = .Offset
                    entry.offset = position
                }

                .recordXrefEntry(cast(u32) number, entry)
            }
        }

        if !.consumeWord("trailer") do
            return result
        .skip()
        if !.startsWith("<<") do
            return result
        let dictId = catch .parseDictionary() as parseError
        if parseError != null do
            return result

        result.ok = true
        .recordTrailer(dictId)

        // A hybrid file keeps its compressed objects in a stream a classic table cannot
        // describe, and names that stream here for readers that understand one.
        let hybrid = .dictRaw(dictId, "XRefStm")
        if hybrid != InvalidNode and .nodes[hybrid].kind == .Integer and .nodes[hybrid].integer >= 0
        {
            let savedPos = .pos
            discard .readXrefSection(cast(u64) .nodes[hybrid].integer)
            .pos = savedPos
        }

        return .withPrevious(result, dictId)
    }

    // Reads a cross-reference stream, the form every file with compressed objects uses.
    mtd readXrefStreamSection(offset: u64)->{ ok, hasPrev: bool, prev: u64 }
    {
        var result: retval
        .pos = offset
        var number, generation: u64
        if !.parseUnsigned(&number) or !.parseUnsigned(&generation) or !.consumeWord("obj") do
            return result

        let nodeId = catch .parseValue() as parseError
        if parseError != null or .nodes[nodeId].kind != .Dictionary do
            return result
        catch .attachStream(nodeId) as streamError
        if streamError != null do
            return result
        if .name(.dict(nodeId, "Type")) != "XRef" do
            return result

        // The three field widths are what the entries are written in; a zero width means the
        // field is not stored and takes its default.
        let widthsId = .resolve(.dictRaw(nodeId, "W"))
        if widthsId == InvalidNode or .nodes[widthsId].kind != .Array or .nodes[widthsId].values.count < 3 do
            return result
        var widths: [3] u64
        for i in 3
        {
            let width = .integer(.nodes[widthsId].values[i], -1)
            if width < 0 or width > 8 do
                return result
            widths[i] = cast(u64) width
        }

        let entryBytes = widths[0] + widths[1] + widths[2]
        if !entryBytes do
            return result

        let data = catch .decodeStream(nodeId) as decodeError
        if decodeError != null do
            return result

        // The index defaults to every object the file declares.
        var ranges: Array'u64
        let indexId = .resolve(.dictRaw(nodeId, "Index"))
        if indexId != InvalidNode and .nodes[indexId].kind == .Array
        {
            for value in .nodes[indexId].values do
                ranges.add(cast(u64) Math.max(0's64, .integer(value)))
        }
        else
        {
            ranges.add(0)
            ranges.add(cast(u64) Math.max(0's64, .integer(.dict(nodeId, "Size"))))
        }

        var cursor = 0'u64
        var range  = 0'u64
        while range + 1 < ranges.count
        {
            let firstNumber = ranges[range]
            let entryCount  = ranges[range + 1]
            range += 2
            for i in entryCount
            {
                if cursor + entryBytes > data.count do
                    break

                var fields: [3] u64
                for k in 3
                {
                    var value = 0'u64
                    for widths[k]
                    {
                        value  = (value << 8) | cast(u64) data[cursor]
                        cursor += 1
                    }

                    fields[k] = value
                }

                // A stored type of zero is a free entry, and an absent type field means the
                // ordinary uncompressed form.
                let kind   = widths[0] ? fields[0] : 1
                let number = firstNumber + i
                if number > Swag.U32.Max do
                    continue

                var entry: XrefEntry
                if kind == 1
                {
                    entry.kind       = .Offset
                    entry.offset     = fields[1]
                    entry.generation = fields[2] <= Swag.U16.Max ? cast(u16) fields[2] : 0
                }
                elif kind == 2
                {
                    if fields[1] > Swag.U32.Max or fields[2] > Swag.U32.Max do
                        continue
                    entry.kind          = .InStream
                    entry.container     = cast(u32) fields[1]
                    entry.indexInStream = cast(u32) fields[2]
                }

                .recordXrefEntry(cast(u32) number, entry)
            }
        }

        result.ok = true
        .recordTrailer(nodeId)
        return .withPrevious(result, nodeId)
    }

    // Fills in where the previous section of the chain starts, when the trailer names one.
    mtd withPrevious(section: { ok, hasPrev: bool, prev: u64 }, dictId: u32)->{ ok, hasPrev: bool, prev: u64 }
    {
        var result: retval = section
        let previous       = .dictRaw(dictId, "Prev")
        if previous != InvalidNode and .nodes[previous].kind == .Integer and .nodes[previous].integer >= 0
        {
            result.hasPrev = true
            result.prev    = cast(u64) .nodes[previous].integer
        }

        return result
    }

    // Files an entry unless a newer section of the chain already named that object.
    mtd recordXrefEntry(number: u32, entry: XrefEntry)
    {
        if .xref.tryFind(number) do
            return
        .xref[number] = entry
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
        // Resolving reaches back into the object table, which may parse an object and insert
        // it, so the walk works from a snapshot rather than from the table itself.
        var scanned: Array'u32
        for objectNumber, nodeId in .objects
        {
            discard objectNumber
            scanned.add(nodeId)
        }

        var streams: Array'u32
        for nodeId in scanned
        {
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
            let decoded = #move try .decodeStream(streamId)
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
        var scanned: Array'u32
        for objectNumber, nodeId in .objects
        {
            discard objectNumber
            scanned.add(nodeId)
        }

        for nodeId in scanned
        {
            let id = .resolve(nodeId)
            if id != InvalidNode and .name(.dict(id, "Type")) == "XRef" do
                .recordTrailer(id, false)
        }

        var search = 0'u64
        for
        {
            let found = .findFrom(search, "trailer")
            if found == Swag.U64.Max do
                break
            search = found + ("trailer").count
            .pos   = search
            .skip()
            if !.startsWith("<<") do
                continue
            let dictId = catch .parseDictionary() as parseError
            if parseError == null do
                .recordTrailer(dictId, false)
        }
    }

    // Remembers what a trailer names, without following any of it.
    //
    // The chain is walked newest first, so the first trailer that names a root is the one the
    // file's latest revision chose, and a trailer carrying only /Prev never overwrites an entry
    // it does not name. Nothing is resolved here: the object a trailer names usually lives in a
    // section the walk has not reached yet, and resolving it now would fall back to the scan the
    // index exists to avoid. The scan meets its trailers in file order instead, so there the
    // last one wins.
    mtd recordTrailer(dictId: u32, preferExisting = true)
    {
        let root = .dictRaw(dictId, "Root")
        if root != InvalidNode and (!preferExisting or .trailerRoot == InvalidNode) do
            .trailerRoot = root

        let info = .dictRaw(dictId, "Info")
        if info != InvalidNode and (!preferExisting or .trailerInfo == InvalidNode) do
            .trailerInfo = info

        if .dictRaw(dictId, "Encrypt") != InvalidNode do
            .isEncrypted = true
    }

    // Returns the node an indirect reference names, following a chain of them.
    mtd resolve(nodeId: u32)->u32
    {
        var result = nodeId
        for 32
        {
            if result >= .nodes.count or .nodes[result].kind != .Reference do
                return result
            let target = .objectNode(.nodes[result].reference, .nodes[result].referenceGeneration)
            if target == InvalidNode do
                return InvalidNode
            result = target
        }

        return InvalidNode
    }

    // Returns the node of one indirect object, parsing it the first time it is asked for.
    //
    // This is what makes opening a document cost its trailer chain rather than its length: an
    // object nothing reaches is never read, and a page that is never displayed is never parsed.
    mtd objectNode(number: u32, generation: u16)->u32
    {
        let known = .objects.tryFind(number)
        if known do
            return known.value

        let indexed = .xref.tryFind(number)
        if indexed
        {
            // A reference whose generation disagrees with the index is still followed. Writers
            // disagree about generations far more often than they disagree about offsets, and
            // refusing the object would lose content the file plainly means to carry.
            discard generation
            let node = .parseIndexedObject(number, indexed.value)
            if node != InvalidNode
            {
                .objects[number] = node
                return node
            }
        }

        // Either the file has no usable index, or it points somewhere the object is not.
        .ensureScanned()
        let scanned = .objects.tryFind(number)
        return scanned ? scanned.value : InvalidNode
    }

    mtd parseIndexedObject(number: u32, entry: XrefEntry)->u32
    {
        if entry.kind == .Offset do
            return .parseObjectAt(number, entry.offset)
        if entry.kind == .InStream do
            return .parseObjectInStream(entry.container, entry.indexInStream)
        return InvalidNode
    }

    // Parses `N G obj` at one byte offset, leaving the parser where it found it.
    //
    // A stream length stated as a forward reference makes this reenter, so the position is
    // saved and the nesting is bounded rather than trusted.
    mtd parseObjectAt(number: u32, offset: u64)->u32
    {
        if offset >= .bytes.count or .objectDepth >= 32 do
            return InvalidNode

        let savedPos = .pos
        .objectDepth += 1
        defer
        {
            .objectDepth -= 1
            .pos         = savedPos
        }

        .pos = offset
        var found, generation: u64
        if !.parseUnsigned(&found) or !.parseUnsigned(&generation) or !.consumeWord("obj") do
            return InvalidNode
        if found != cast(u64) number do
            return InvalidNode

        let nodeId = catch .parseValue() as parseError
        if parseError != null do
            return InvalidNode
        if .nodes[nodeId].kind == .Dictionary
        {
            catch .attachStream(nodeId) as streamError
            discard streamError
        }

        return nodeId
    }

    // Parses one object out of a compressed object stream.
    mtd parseObjectInStream(container: u32, index: u32)->u32
    {
        if .objectDepth >= 32 do
            return InvalidNode
        let stream = .objectStream(container)
        if !stream or index >= stream!.offsets.count do
            return InvalidNode

        let position = stream!.first + stream!.offsets[index]
        if position >= stream!.data.count do
            return InvalidNode

        let savedBytes = .bytes
        let savedPos   = .pos
        .objectDepth += 1
        defer
        {
            .objectDepth -= 1
            .bytes       = savedBytes
            .pos         = savedPos
        }

        .bytes = stream!.data.toSlice()
        .pos   = position
        let nodeId = catch .parseValue() as parseError
        return parseError == null ? nodeId : InvalidNode
    }

    // Returns one expanded object stream, decompressing it the first time it is needed.
    mtd objectStream(container: u32)->#null *ObjectStream
    {
        let existing = .objectStreamIndex.tryFind(container)
        if existing do
            return .objectStreams[existing.value]

        let streamId = .objectNode(container, 0)
        if streamId == InvalidNode or .name(.dict(streamId, "Type")) != "ObjStm" do
            return null
        let count = .integer(.dict(streamId, "N"))
        let first = .integer(.dict(streamId, "First"))
        if count < 0 or first < 0 do
            return null

        let decoded = catch .decodeStream(streamId) as decodeError
        if decodeError != null or cast(u64) first > decoded.count do
            return null

        let result = .objectStreams.addNew()
        .objectStreamIndex[container] = cast(u32) (.objectStreams.count - 1)
        result.data  = decoded
        result.first = cast(u64) first

        var header = PdfParser{bytes: result.data.toSlice()}
        for cast(u64) count
        {
            var objectNumber = 0'u64
            var objectOffset = 0'u64
            if !header.parseUnsigned(&objectNumber) or !header.parseUnsigned(&objectOffset) or objectNumber > Swag.U32.Max do
                break
            result.numbers.add(cast(u32) objectNumber)
            result.offsets.add(objectOffset)
        }

        return result
    }

    mtd dictRaw(nodeId: u32, key: string)->u32
    {
        let id = .resolve(nodeId)
        if id == InvalidNode or .nodes[id].kind != .Dictionary do
            return InvalidNode
        let entry = .nodes[id].entries.tryFind(key)
        return entry ? entry.value : InvalidNode
    }

    mtd dict(nodeId: u32, key: string)->u32 => .resolve(.dictRaw(nodeId, key))

    mtd name(nodeId: u32)->string
    {
        let id = .resolve(nodeId)
        return id != InvalidNode and .nodes[id].kind == .Name ? .nodes[id].text.toString() : ""
    }

    mtd integer(nodeId: u32, fallback = 0's64)->s64
    {
        let id = .resolve(nodeId)
        if id == InvalidNode do
            return fallback
        if .nodes[id].kind == .Integer do
            return .nodes[id].integer
        return fallback
    }

    mtd number(nodeId: u32, fallback = 0.0)->f64
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

    mtd boolean(nodeId: u32, fallback = false)->bool
    {
        let id = .resolve(nodeId)
        if id == InvalidNode or .nodes[id].kind != .Boolean do
            return fallback
        return .nodes[id].boolean
    }

    mtd stringValue(nodeId: u32)->string
    {
        let id = .resolve(nodeId)
        return id != InvalidNode and .nodes[id].kind == .String ? .nodes[id].text.toString() : ""
    }

    // Returns the names of the filters applied to a stream, outermost first.
    mtd streamFilters(nodeId: u32)->Array'String
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
            if name.count do
                result.add(name)
        }

        return result
    }

    // Returns the parameter dictionary that applies to the filter at `index`.
    mtd filterParameters(nodeId: u32, index: u64)->u32
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
    mtd imageCodec(nodeId: u32)->String
    {
        var result: retval
        let filters = #move .streamFilters(nodeId)
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
        let filters          = #move .streamFilters(id)
        var count            = filters.count
        if stopAtImageCodec and count and .imageCodec(id).count do
            count -= 1

        for index in count
        {
            let parameters = .filterParameters(id, index)
            switch filters[index].toString()
            {
            case "FlateDecode", "Fl":
                var zlib: Compress.ZLib
                var decoded = #move try zlib.decompress(result.toSlice())
                result.free()
                result = #move decoded
                if parameters != InvalidNode
                {
                    var predicted = #move try .applyPredictor(result.toSlice(), parameters)
                    result.free()
                    result = #move predicted
                }

            case "LZWDecode", "LZW":
                let earlyChange = .integer(.dict(parameters, "EarlyChange"), 1) != 0
                var decoded     = #move try decodeLzw(result.toSlice(), earlyChange)
                result.free()
                result = #move decoded
                if parameters != InvalidNode
                {
                    var predicted = #move try .applyPredictor(result.toSlice(), parameters)
                    result.free()
                    result = #move predicted
                }

            case "ASCIIHexDecode", "AHx":
                var decoded = #move try decodeAsciiHex(result.toSlice())
                result.free()
                result = #move decoded

            case "ASCII85Decode", "A85":
                var decoded = #move try decodeAscii85(result.toSlice())
                result.free()
                result = #move decoded

            case "RunLengthDecode", "RL":
                var decoded = #move try decodeRunLength(result.toSlice())
                result.free()
                result = #move decoded

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
            if data.count % rowBytes do
                fail InvalidFormatError{"PDF TIFF predictor rows are truncated"}
            var result: retval = data
            let stride         = cast(u64) colors * cast(u64) (bits / 8)
            for row in data.count / rowBytes
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
        if data.count % encodedRow do
            fail InvalidFormatError{"PDF PNG predictor rows are truncated"}
        var result: retval
        result.resize(data.count / encodedRow * rowBytes)
        for row in data.count / encodedRow
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
