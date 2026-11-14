#global namespace Serialization
#global namespace Read

using Swag, Core.Errors

// Reads XML whose element order matches the serialized Swag type.
//
// Every struct field is an element named after the field, and the document root is one more
// element around them, whatever its name, after an optional `<?xml ...?>` declaration. A
// sequence holds native values separated by blanks.
// Unknown, missing, and reordered elements fail. The input slice is borrowed until decoding
// completes.
public struct Xml
{
    internal
    {
        stream:    ByteStream         // Input cursor.
        stackTags: Array'(string)     // Borrowed open element names.
    }
}

public impl Xml
{
    // Returns zero because XML has no stream-level schema version.
    mtd version()->u32 => 0

    // Returns true, because XML is a textual format.
    mtd isTextual()->bool => true

    internal mtd readTag()->string fail
    {
        .zapBlanks()

        var c = .stream.readU8()
        if c != '<' do
            fail .getError("malformed tag, missing opening [[<]]")

        let start = .stream.position()
        c = .stream.readU8()
        while c and c != '>' do
            c = .stream.readU8()
        if c != '>' do
            fail .getError("malformed tag, missing closing [[>]]")

        let end = .stream.position() - 1
        return Latin1.trim(cast(string, .stream.readBuffer![start until end]))
    }

    internal mtd readStartTag()->string fail
    {
        let tag = try .readTag()
        .stackTags.add(tag)
        return tag
    }

    internal mtd readEndTag() fail
    {
        let tag   = try .readTag()
        let start = .stackTags.popBack()
        if not Utf8.startsWith(tag, "/") or tag[1 to ] != start do
            fail .getError(Format.toString("invalid end tag [[%]] for [[%]]", tag, start))
    }

    // Reads a predefined entity or XML character reference after an '&'.
    internal mtd readEntity()->rune fail
    {
        const Names = ["lt;", "gt;", "amp;", "quot;", "apos;"]
        const Chars = "<>&\"'"
        let rest = .stream.remainingString()
        for index in Names.count
        {
            if Utf8.startsWith(rest, Names[index])
            {
                .stream.advance(Names[index].count)
                return cast(rune, Chars[index])
            }
        }

        if .stream.peekU8() != '#' do
            fail .getError("unknown XML entity")
        .stream.advance()

        var radix = 10'u32
        if .stream.peekU8() == 'x'
        {
            radix = 16
            .stream.advance()
        }

        var value  = 0'u32
        var digits = 0'u32
        while true
        {
            let c = .stream.peekU8()
            if c == ';' do
                break

            var digit: u32
            if '0' <= c and c <= '9'
            {
                digit = cast(u32, c - '0')
            }
            elif radix == 16 and 'a' <= c and c <= 'f'
            {
                digit = cast(u32, c - 'a' + 10)
            }
            elif radix == 16 and 'A' <= c and c <= 'F'
            {
                digit = cast(u32, c - 'A' + 10)
            }
            else
            {
                fail .getError("malformed XML character reference")
            }

            if digit >= radix or value > (0x10FFFF - digit) / radix do
                fail .getError("XML character reference is outside the Unicode range")
            value = value * radix + digit
            digits += 1
            .stream.advance()
        }

        if not digits do
            fail .getError("empty XML character reference")
        .stream.advance() // semicolon

        // XML 1.0 Char: #x9 | #xA | #xD | [#x20-#xD7FF] |
        // [#xE000-#xFFFD] | [#x10000-#x10FFFF].
        if not (value == 0x9 or value == 0xA or value == 0xD or
                (0x20 <= value and value <= 0xD7FF) or
                (0xE000 <= value and value <= 0xFFFD) or
                (0x10000 <= value and value <= 0x10FFFF))
        {
            fail .getError("XML character reference names a character forbidden by XML 1.0")
        }

        return cast(rune, value)
    }

    internal mtd getError(val: string)->SyntaxError
    {
        var err: #returntype
        err.message = Errors.mkString(val)
        err.seek    = .stream.seek
        err.line    = 1
        err.col     = 1

        let data = .stream.data()
        for i in err.seek
        {
            if data[i] == '\n'
            {
                err.line += 1
                err.col  = 1
            }
            else
            {
                err.col += 1
            }
        }

        return err
    }

    internal mtd zapBlanks()
    {
        var c = .stream.peekU8()
        while c and Latin1.isSpace(c)
        {
            .stream.advance()
            c = .stream.peekU8()
        }
    }

    // Starts decoding from borrowed XML bytes and resets reusable state.
    mtd startRead(input: const [..] u8) fail
    {
        .stream = ByteStream.openRead(input)
        .stackTags.clear()
        if not Utf8.isValid(input) do
            fail .getError("XML document is not valid UTF-8")

        var offset = 0'u64
        while offset < input.count
        {
            let {c, eat} = Utf8.decodeRune(input[offset to])
            if (c < 0x20 and c != '\t' and c != '\n' and c != '\r') or
               c == 0xFFFE or c == 0xFFFF
            {
                .stream.setPosition(offset)
                fail .getError("XML document contains a character forbidden by XML 1.0")
            }
            offset += eat
        }

        let bytes = .stream.remainingBytes()
        if bytes.count >= 3 and bytes[0] == 0xEF and bytes[1] == 0xBB and bytes[2] == 0xBF do
            .stream.advance(3)
    }

    // Returns whether another sequence element follows, that is, whether the next non-blank byte does not start a tag.
    mtd toNextSequenceElement(_: *u64)->bool
    {
        .zapBlanks()
        return .stream.peekU8() != '<'
    }

    // Reads the tag that opens a section.
    mtd beginSection(_: SectionKind) fail
    {
        discard try .readStartTag()
    }

    // Reads and validates the matching tag that closes a section.
    mtd endSection() fail
    {
        try .readEndTag()
    }

    // Skips an optional XML declaration, then reads the tag that opens the document.
    mtd beginRoot() fail
    {
        .zapBlanks()
        let rest = .stream.remainingString()
        if Utf8.startsWith(rest, "<?")
        {
            let end = Utf8.indexOf(rest, "?>")
            if end == Swag.U64.Max do
                fail .getError("malformed XML declaration, missing closing [[?>]]")
            .stream.advance(end + 2)
        }

        discard try .readStartTag()
    }

    // Reads the matching root close tag and rejects non-whitespace data after it.
    mtd endRoot() fail
    {
        try .readEndTag()
        .zapBlanks()
        if .stream.position() != .stream.length() do
            fail .getError("XML document has trailing data")
    }

    // Reads the start tag of the element `val` and fails when it names another element.
    mtd beginElement(val: TypeValue)->bool fail
    {
        let tag = try .readStartTag()
        if tag != val.name do
            fail .getError("invalid property name")
        return true
    }

    // Reads the end tag of the current element.
    mtd endElement(_: TypeValue) fail
    {
        try .readEndTag()
    }

    {
        // Returns false, so the decoder reads the fields of the struct.
        mtd beginStruct(_: typeinfo, _: const *u8)->bool fail => false

        // Does nothing: the struct ends with its last element.
        mtd endStruct() fail {}

        // Returns false, so the decoder reads the elements one by one.
        mtd beginSequence(_: typeinfo, _: *u8, _: *u64)->bool fail => false

        // Does nothing: the sequence ends before the next tag.
        mtd endSequence() fail {}

        // Does nothing: an XML value needs no opening mark.
        mtd beginValue() fail {}

        // Does nothing: an XML value needs no closing mark.
        mtd endValue() fail {}
    }

    // Reads a native value at the current XML position.
    mtd(NT) readNative()->NT fail
    {
        .zapBlanks()
        #static switch NT
        {
        case bool:
            let val = try StrConv.parseBool(.stream.remainingString())
            .stream.advance(val.eat)
            return val.value

        case Core.String:
            var result: #returntype
            var c = .stream.peekU8()
            while c and c != '<'
            {
                .stream.advance()
                if c == '\r'
                {
                    // XML normalizes CR and CRLF line endings to LF before parsing text.
                    result += '\n'
                    if .stream.peekU8() == '\n' do
                        .stream.advance()
                }
                elif c == '&' do
                    result.append(try .readEntity())
                else do
                    result += c
                c = .stream.peekU8()
            }

            return result

        default:
            var parsed: {value: NT, eat: u32, ovf: bool}
            #static switch NT
            {
            case f32: parsed = try StrConv.parseF32(.stream.remainingString())
            case f64: parsed = try StrConv.parseF64(.stream.remainingString())
            case s8:  parsed = try StrConv.parseS8(.stream.remainingString())
            case s16: parsed = try StrConv.parseS16(.stream.remainingString())
            case s32: parsed = try StrConv.parseS32(.stream.remainingString())
            case s64: parsed = try StrConv.parseS64(.stream.remainingString())
            case u8:  parsed = try StrConv.parseU8(.stream.remainingString())
            case u16: parsed = try StrConv.parseU16(.stream.remainingString())
            case u32: parsed = try StrConv.parseU32(.stream.remainingString())
            case u64: parsed = try StrConv.parseU64(.stream.remainingString())
            default:  #error("invalid type")
            }

            if parsed.ovf do
                fail .getError("XML number is outside the range of its type")

            .stream.advance(parsed.eat)
            return parsed.value
        }
    }
}
