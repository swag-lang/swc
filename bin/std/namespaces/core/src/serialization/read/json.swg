#global namespace Serialization
#global namespace Read

using Swag, Core.Errors

internal struct JsonObject
{
    properties:  HashTable!{String, u64}
    endPosition: u64
}

// Reads declaration-driven JSON objects independently of property order.
//
// Missing fields retain their initialized value and unknown properties are ignored.
// Duplicate properties, malformed numbers, trailing commas, and trailing root data fail.
// Strings support every JSON escape, including UTF-16 surrogate pairs in `\uXXXX` escapes.
// The input must be valid UTF-8; invalid byte sequences fail with a SyntaxError.
public struct Json
{
    internal
    {
        stream:         ByteStream             // Input cursor.
        objects:        Array!{JsonObject}     // Active object indexes, outermost first.
        containerKinds: [64] u8                // Zero for arrays and one for objects.
        firstValues:    [64] bool              // Whether an active array has read no value yet.
        containerDepth: u64                    // Number of active array and object scopes.
    }
}

public impl Json
{
    // Returns zero because JSON has no stream-level schema version.
    mtd version()->u32 => 0

    // Returns true because JSON is textual.
    mtd isTextual()->bool => true

    internal mtd getError(message: string)->SyntaxError
    {
        var result: #returntype
        result.message = message
        result.seek    = .stream.position()
        result.line    = 1
        result.col     = 1

        let data = .stream.data()
        for i in result.seek
        {
            if data[i] == '\n'
            {
                result.line += 1
                result.col  = 1
            }
            else
            {
                result.col += 1
            }
        }

        return result
    }

    internal mtd expectByte(expected: u8, message: string) fail
    {
        if .stream.readU8() != expected
        {
            fail .getError(message)
        }
    }

    internal mtd zapBlanks()
    {
        var c = .stream.peekU8()

        // RFC 8259 permits only space, horizontal tab, line feed and carriage return
        // outside strings. Latin1.isSpace also accepts control bytes JSON forbids.
        while c == ' ' or c == '\t' or c == '\n' or c == '\r'
        {
            .stream.advance()
            c = .stream.peekU8()
        }
    }

    internal mtd readHexQuad()->u32 fail
    {
        var value = 0_u32
        for 4
        {
            let c = .stream.readU8()
            if not Latin1.isHexDigit(c)
            {
                fail .getError("JSON Unicode escape needs four hexadecimal digits")
            }

            value <<= 4
            if Latin1.isDigit(c)
            {
                value += c - '0'_u8
            }
            else if c <= 'F'_u8
            {
                value += 10 + c - 'A'_u8
            }
            else
            {
                value += 10 + c - 'a'_u8
            }
        }

        return value
    }

    internal mtd readUnicodeEscape()->u32 fail
    {
        let firstCodeUnit = try .readHexQuad()
        if firstCodeUnit >= 0xDC00 and firstCodeUnit <= 0xDFFF
        {
            fail .getError("JSON Unicode escape contains an unpaired low surrogate")
        }

        if firstCodeUnit < 0xD800 or firstCodeUnit > 0xDBFF
        {
            return firstCodeUnit
        }

        // A high surrogate must be followed by a second Unicode escape.
        if .stream.readU8() != '\\' or .stream.readU8() != 'u'
        {
            fail .getError("JSON Unicode escape is missing the low surrogate")
        }

        let lowSurrogate = try .readHexQuad()
        if lowSurrogate < 0xDC00 or lowSurrogate > 0xDFFF
        {
            fail .getError("JSON Unicode escape contains an invalid low surrogate")
        }

        return 0x10000 + ((firstCodeUnit - 0xD800) << 10) + lowSurrogate - 0xDC00
    }

    internal mtd readString(result: *String?) fail
    {
        try .expectByte('"', "JSON string is missing its opening quote")
        if result
        {
            result.clear()
        }
        while true
        {
            let bytes  = .stream.remainingBytes()
            let length = jsonPlainByteCount(bytes)
            if length
            {
                if result
                {
                    result.append(Swag.makeString(bytes.buffer, length))
                }
                .stream.advance(length)
            }

            let c = .stream.readU8()
            if not c
            {
                fail .getError("JSON string is missing its closing quote")
            }

            if c == '"'
            {
                return
            }

            if c < 0x20
            {
                fail .getError("JSON string contains an unescaped control character")
            }

            let escaped = try .readStringEscape()
            if result
            {
                result.append(escaped)
            }
        }
    }

    private mtd readStringEscape()->rune fail
    {
        let c = .stream.readU8()
        switch c
        {
        case '"', '\\', '/': return cast(rune, c)
        case 'b': return '\b'
        case 'f': return '\f'
        case 'n': return '\n'
        case 'r': return '\r'
        case 't': return '\t'
        case 'u': return cast(rune, (try .readUnicodeEscape()))
        default:  fail .getError("JSON string contains an unknown escape sequence")
        }
    }

    internal mtd readLiteral(literal: string) fail
    {
        for c in literal
        {
            if .stream.readU8() != c
            {
                fail .getError("JSON literal is malformed")
            }
        }
    }

    internal mtd skipNumber() fail
    {
        if .stream.peekU8() == '-'
        {
            .stream.advance()
        }

        let first = .stream.peekU8()
        if first == '0'
        {
            .stream.advance()
            if Latin1.isDigit(.stream.peekU8())
            {
                fail .getError("JSON number has a leading zero")
            }
        }
        else if first >= '1' and first <= '9'
        {
            while Latin1.isDigit(.stream.peekU8())
            {
                .stream.advance()
            }
        }
        else
        {
            fail .getError("JSON number is missing its integer part")
        }

        if .stream.peekU8() == '.'
        {
            .stream.advance()
            if not Latin1.isDigit(.stream.peekU8())
            {
                fail .getError("JSON number is missing digits after its decimal point")
            }

            while Latin1.isDigit(.stream.peekU8())
            {
                .stream.advance()
            }
        }

        let exponent = .stream.peekU8()
        if exponent == 'e' or exponent == 'E'
        {
            .stream.advance()
            let sign = .stream.peekU8()
            if sign == '+' or sign == '-'
            {
                .stream.advance()
            }

            if not Latin1.isDigit(.stream.peekU8())
            {
                fail .getError("JSON number is missing exponent digits")
            }

            while Latin1.isDigit(.stream.peekU8())
            {
                .stream.advance()
            }
        }
    }

    internal mtd skipValue(depth: u32) fail
    {
        if depth >= 64
        {
            fail .getError("JSON nesting is too deep")
        }

        .zapBlanks()
        switch .stream.peekU8()
        {
        case '"':
            try .readString(null)

        case '{':
            .stream.advance()
            var properties: HashTable!{String, u64}
            try .scanObject(&properties, depth + 1)

        case '[':
            .stream.advance()
            .zapBlanks()
            if .stream.peekU8() == ']'
            {
                .stream.advance()
                return
            }

            while true
            {
                try .skipValue(depth + 1)
                .zapBlanks()
                let separator = .stream.readU8()
                if separator == ']'
                {
                    return
                }

                if separator != ','
                {
                    fail .getError("JSON array needs a comma between values")
                }

                .zapBlanks()
                if .stream.peekU8() == ']'
                {
                    fail .getError("JSON array has a trailing comma")
                }
            }

        case 't':
            try .readLiteral("true")

        case 'f':
            try .readLiteral("false")

        case 'n':
            try .readLiteral("null")

        default:
            try .skipNumber()
        }
    }

    private mtd scanObject(properties: *HashTable!{String, u64}, depth: u32) fail
    {
        .zapBlanks()
        if .stream.peekU8() == '}'
        {
            .stream.advance()
            return
        }

        var name: String
        while true
        {
            try .readString(&name)
            let property = properties.findOrAdd(name)
            if property.value
            {
                fail .getError("JSON object contains a duplicate property")
            }

            .zapBlanks()
            try .expectByte(':', "JSON property is missing a colon after its name")
            .zapBlanks()
            property.value = .stream.position()
            try .skipValue(depth)

            .zapBlanks()
            let separator = .stream.readU8()
            if separator == '}'
            {
                return
            }

            if separator != ','
            {
                fail .getError("JSON object needs a comma between properties")
            }

            .zapBlanks()
            if .stream.peekU8() == '}'
            {
                fail .getError("JSON object has a trailing comma")
            }
        }
    }

    internal mtd beginObject() fail
    {
        if .containerDepth == (.containerKinds).count
        {
            fail .getError("JSON nesting is too deep")
        }

        .zapBlanks()
        try .expectByte('{', "JSON object is missing its opening brace")
        let contentStart = .stream.position()

        // Validate even unknown properties while indexing values in this object once.
        var object: JsonObject
        try .scanObject(&object.properties, 1)
        object.endPosition = .stream.position()
        .objects.add(#move object)
        .stream.setPosition(contentStart)
        .containerKinds[.containerDepth] = 1
        .containerDepth += 1
    }

    // Starts reading a borrowed JSON buffer.
    mtd startRead(input: const [..] u8) fail
    {
        .stream = ByteStream.openRead(input)
        .objects.clear()
        .containerDepth = 0
        if not Utf8.isValid(input)
        {
            fail .getError("JSON document is not valid UTF-8")
        }
    }

    // Begins an array.
    mtd beginSequence(_: typeinfo?, _: *u8?, _: *u64)->bool fail
    {
        .zapBlanks()
        try .expectByte('[', "JSON array is missing its opening bracket")
        if .containerDepth == (.containerKinds).count
        {
            fail .getError("JSON nesting is too deep")
        }

        let index = .containerDepth
        .containerKinds[index] = 0
        .firstValues[index]    = true
        .containerDepth        += 1
        return false
    }

    // Ends an array and rejects extra or trailing values.
    mtd endSequence() fail
    {
        .zapBlanks()
        try .expectByte(']', "JSON array is missing its closing bracket")
        .containerDepth -= 1
    }

    // Returns whether another array element remains.
    mtd toNextSequenceElement(_: *u64)->bool
    {
        .zapBlanks()
        return .stream.peekU8() != ']'
    }

    // Begins the JSON document.
    mtd beginRoot() fail {}

    // Ends the JSON document and rejects non-whitespace trailing data.
    mtd endRoot() fail
    {
        .zapBlanks()
        if .stream.position() != .stream.length()
        {
            fail .getError("JSON document has trailing data")
        }
    }

    // Begins an object section.
    mtd beginSection(_: SectionKind) fail => try .beginObject()

    // Ends an object section.
    mtd endSection() fail
    {
        .stream.setPosition(.objects.backPtr().endPosition)
        .objects.removeBack()
        .containerDepth -= 1
    }

    // Begins a reflected struct object.
    mtd beginStruct(_: typeinfo?, _: const *u8?)->bool fail
    {
        try .beginObject()
        return false
    }

    // Ends a reflected struct object.
    mtd endStruct() fail => try .endSection()

    // Finds a property by name in the current object.
    mtd beginElement(val: TypeValue)->bool fail
    {
        if not .containerDepth
        {
            fail .getError("JSON property is outside an object")
        }

        if .containerKinds[.containerDepth - 1] != 1
        {
            fail .getError("JSON named property is inside an array")
        }

        let object   = .objects.backPtr()
        let property = object.properties.tryFind(String.from(wireFieldKey(val)))
        if not property
        {
            .stream.setPosition(object.endPosition)
            return false
        }

        .stream.setPosition(property.value)
        return true
    }

    // Completes a property.
    mtd endElement(_: TypeValue) fail {}

    // Begins a value, consuming the separator required by an enclosing array.
    mtd beginValue() fail
    {
        if not .containerDepth
        {
            return
        }

        let index = .containerDepth - 1
        if .containerKinds[index] != 0
        {
            return
        }

        .zapBlanks()
        if .firstValues[index]
        {
            .firstValues[index] = false
            return
        }

        try .expectByte(',', "JSON array needs a comma between values")
        .zapBlanks()
        if .stream.peekU8() == ']'
        {
            fail .getError("JSON array has a trailing comma")
        }
    }

    // Completes a value.
    mtd endValue() fail {}

    // Reads a native value at the current JSON position.
    mtd(NT) readNative()->NT fail
    {
        .zapBlanks()
        #static switch NT
        {
        case bool:
            if .stream.peekU8() == 't'
            {
                try .readLiteral("true")
                return true
            }

            if .stream.peekU8() == 'f'
            {
                try .readLiteral("false")
                return false
            }

            fail .getError("JSON Boolean value must be true or false")

        case Core.String:
            if .stream.peekU8() == 'n'
            {
                try .readLiteral("null")
                var result: #returntype
                return result
            }

            var result: #returntype
            try .readString(&result)
            return result

        default:
            let start = .stream.position()
            try .skipNumber()
            let length = .stream.position() - start
            let token  = Swag.makeString(.stream.data() + start, length)
            #static switch NT
            {
            case f32:
                let val = try StrConv.parseF32Invariant(token)
                if val.eat != length or val.ovf
                {
                    fail .getError("JSON number cannot be represented as f32")
                }

                return val.value

            case f64:
                let val = try StrConv.parseF64Invariant(token)
                if val.eat != length or val.ovf
                {
                    fail .getError("JSON number cannot be represented as f64")
                }

                return val.value

            case s8:
                let val = try StrConv.parseS8(token)
                if val.eat != length or val.ovf
                {
                    fail .getError("JSON number cannot be represented as s8")
                }

                return val.value

            case s16:
                let val = try StrConv.parseS16(token)
                if val.eat != length or val.ovf
                {
                    fail .getError("JSON number cannot be represented as s16")
                }

                return val.value

            case s32:
                let val = try StrConv.parseS32(token)
                if val.eat != length or val.ovf
                {
                    fail .getError("JSON number cannot be represented as s32")
                }

                return val.value

            case s64:
                let val = try StrConv.parseS64(token)
                if val.eat != length or val.ovf
                {
                    fail .getError("JSON number cannot be represented as s64")
                }

                return val.value

            case u8:
                let val = try StrConv.parseU8(token)
                if val.eat != length or val.ovf
                {
                    fail .getError("JSON number cannot be represented as u8")
                }

                return val.value

            case u16:
                let val = try StrConv.parseU16(token)
                if val.eat != length or val.ovf
                {
                    fail .getError("JSON number cannot be represented as u16")
                }

                return val.value

            case u32:
                let val = try StrConv.parseU32(token)
                if val.eat != length or val.ovf
                {
                    fail .getError("JSON number cannot be represented as u32")
                }

                return val.value

            case u64:
                let val = try StrConv.parseU64(token)
                if val.eat != length or val.ovf
                {
                    fail .getError("JSON number cannot be represented as u64")
                }

                return val.value
            }
        }
    }
}
