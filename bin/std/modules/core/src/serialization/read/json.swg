#global namespace Serialization
#global namespace Read

using Swag, Core.Errors

// Reads declaration-driven JSON objects independently of property order.
//
// Missing fields retain their initialized value and unknown properties are ignored.
// Duplicate properties, malformed numbers, trailing commas, and trailing root data fail.
// Strings support every JSON escape, including UTF-16 surrogate pairs in `\uXXXX` escapes.
public struct Json
{
    internal
    {
        stream:         ByteStream     // Input cursor.
        propName:       String         // Reusable decoded property name.
        containerKinds: [64] u8        // Zero for arrays and one for objects.
        contentStarts:  [64] u64       // First byte inside each active object.
        endPositions:   [64] u64       // First byte after each active object.
        firstValues:    [64] bool      // Whether an active array has read no value yet.
        containerDepth: u64            // Number of active array and object scopes.
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
        var result: retval
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
            else do
                result.col += 1
        }

        return result
    }

    internal mtd expectByte(expected: u8, message: string) fail
    {
        if .stream.readU8() != expected do
            fail .getError(message)
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

    internal mtd readHexQuad()->u32 fail
    {
        var value = 0'u32
        for 4
        {
            let c = .stream.readU8()
            if !Latin1.isHexDigit(c) do
                fail .getError("JSON Unicode escape needs four hexadecimal digits")

            value <<= 4
            if Latin1.isDigit(c) do
                value += c - '0'u8
            elif c <= 'F'u8 do
                value += 10 + c - 'A'u8
            else do
                value += 10 + c - 'a'u8
        }

        return value
    }

    internal mtd readUnicodeEscape()->u32 fail
    {
        let first = .readHexQuad()
        if first >= 0xDC00 and first <= 0xDFFF do
            fail .getError("JSON Unicode escape contains an unpaired low surrogate")
        if first < 0xD800 or first > 0xDBFF do
            return first

        if .stream.readU8() != '\\' or .stream.readU8() != 'u' do
            fail .getError("JSON Unicode escape is missing the low surrogate")
        let second = .readHexQuad()
        if second < 0xDC00 or second > 0xDFFF do
            fail .getError("JSON Unicode escape contains an invalid low surrogate")
        return 0x10000 + ((first - 0xD800) << 10) + second - 0xDC00
    }

    internal mtd readString(result: *String) fail
    {
        .expectByte('"', "JSON string is missing its opening quote")
        result.clear()
        while true
        {
            let c = .stream.readU8()
            if !c do
                fail .getError("JSON string is missing its closing quote")
            if c == '"' do
                return
            if c < 0x20 do
                fail .getError("JSON string contains an unescaped control character")
            if c != '\\'
            {
                result.append(c)
                continue
            }

            switch .stream.readU8()
            {
            case '"':  result.append('"'u8)
            case '\\': result.append('\\'u8)
            case '/':  result.append('/'u8)
            case 'b':  result.append('\b'u8)
            case 'f':  result.append('\f'u8)
            case 'n':  result.append('\n'u8)
            case 'r':  result.append('\r'u8)
            case 't':  result.append('\t'u8)
            case 'u':  result.append(cast(rune) .readUnicodeEscape())
            default:   fail .getError("JSON string contains an unknown escape sequence")
            }
        }
    }

    internal mtd readLiteral(literal: string) fail
    {
        for c in literal
        {
            if .stream.readU8() != c do
                fail .getError("JSON literal is malformed")
        }
    }

    internal mtd skipNumber() fail
    {
        if .stream.peekU8() == '-' do
            .stream.advance()

        let first = .stream.peekU8()
        if first == '0'
        {
            .stream.advance()
            if Latin1.isDigit(.stream.peekU8()) do
                fail .getError("JSON number has a leading zero")
        }
        elif first >= '1' and first <= '9'
        {
            while Latin1.isDigit(.stream.peekU8()) do
                .stream.advance()
        }
        else do
            fail .getError("JSON number is missing its integer part")

        if .stream.peekU8() == '.'
        {
            .stream.advance()
            if !Latin1.isDigit(.stream.peekU8()) do
                fail .getError("JSON number is missing digits after its decimal point")
            while Latin1.isDigit(.stream.peekU8()) do
                .stream.advance()
        }

        let exponent = .stream.peekU8()
        if exponent == 'e' or exponent == 'E'
        {
            .stream.advance()
            let sign = .stream.peekU8()
            if sign == '+' or sign == '-' do
                .stream.advance()
            if !Latin1.isDigit(.stream.peekU8()) do
                fail .getError("JSON number is missing exponent digits")
            while Latin1.isDigit(.stream.peekU8()) do
                .stream.advance()
        }
    }

    internal mtd skipValue(depth = 0'u32) fail
    {
        if depth >= 64 do
            fail .getError("JSON nesting is too deep")
        .zapBlanks()
        switch .stream.peekU8()
        {
        case '"':
            var ignored: String
            .readString(&ignored)

        case '{':
            .stream.advance()
            .skipObjectContent(depth + 1)

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
                .skipValue(depth + 1)
                .zapBlanks()
                let separator = .stream.readU8()
                if separator == ']' do
                    return
                if separator != ',' do
                    fail .getError("JSON array needs a comma between values")
                .zapBlanks()
                if .stream.peekU8() == ']' do
                    fail .getError("JSON array has a trailing comma")
            }

        case 't':
            .readLiteral("true")

        case 'f':
            .readLiteral("false")

        case 'n':
            .readLiteral("null")

        default:
            .skipNumber()
        }
    }

    internal mtd skipObjectContent(depth = 0'u32) fail
    {
        .zapBlanks()
        if .stream.peekU8() == '}'
        {
            .stream.advance()
            return
        }

        var names:   HashSet'String
        var ignored: String
        while true
        {
            .readString(&ignored)
            if names.contains(ignored) do
                fail .getError("JSON object contains a duplicate property")
            names.add(ignored)
            .zapBlanks()
            .expectByte(':', "JSON property is missing a colon after its name")
            .skipValue(depth)
            .zapBlanks()
            let separator = .stream.readU8()
            if separator == '}' do
                return
            if separator != ',' do
                fail .getError("JSON object needs a comma between properties")
            .zapBlanks()
            if .stream.peekU8() == '}' do
                fail .getError("JSON object has a trailing comma")
        }
    }

    internal mtd beginObject() fail
    {
        if .containerDepth == (.containerKinds).count do
            fail .getError("JSON nesting is too deep")
        .zapBlanks()
        .expectByte('{', "JSON object is missing its opening brace")

        let index = .containerDepth
        .containerKinds[index] = 1
        .contentStarts[index]  = .stream.position()
        .skipObjectContent(1)
        .endPositions[index] = .stream.position()
        .stream.setPosition(.contentStarts[index])
        .containerDepth += 1
    }

    internal mtd propertyMatches(val: TypeValue)->bool
    {
        return .propName == wireFieldKey(val)
    }

    // Starts reading a borrowed JSON buffer.
    mtd startRead(input: const [..] u8) fail
    {
        .stream = ByteStream.openRead(input)
        if !Utf8.isValid(input) do
            fail .getError("JSON document is not valid UTF-8")
        .propName.clear()
        .containerDepth = 0
    }

    // Begins an array.
    mtd beginSequence(_typeElem: #null typeinfo, _data: #null *u8, _countElem: *u64)->bool fail
    {
        .zapBlanks()
        .expectByte('[', "JSON array is missing its opening bracket")
        if .containerDepth == (.containerKinds).count do
            fail .getError("JSON nesting is too deep")
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
        .expectByte(']', "JSON array is missing its closing bracket")
        .containerDepth -= 1
    }

    // Returns whether another array element remains.
    mtd toNextSequenceElement(_countElem: *u64)->bool
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
        if .stream.position() != .stream.length() do
            fail .getError("JSON document has trailing data")
    }

    // Begins an object section.
    mtd beginSection(_kind: SectionKind) fail => .beginObject()

    // Ends an object section.
    mtd endSection() fail
    {
        .stream.setPosition(.endPositions[.containerDepth - 1])
        .containerDepth -= 1
    }

    // Begins a reflected struct object.
    mtd beginStruct(_structType: #null typeinfo, _structData: #null const *u8)->bool fail
    {
        .beginObject()
        return false
    }

    // Ends a reflected struct object.
    mtd endStruct() fail => .endSection()

    // Finds a property by name in the current object.
    mtd beginElement(val: TypeValue)->bool fail
    {
        if !.containerDepth do
            fail .getError("JSON property is outside an object")
        let index = .containerDepth - 1
        if .containerKinds[index] != 1 do
            fail .getError("JSON named property is inside an array")

        .stream.setPosition(.contentStarts[index])
        .zapBlanks()
        if .stream.peekU8() == '}' do
            return false

        var foundPosition = Swag.U64.Max
        while true
        {
            .readString(&.propName)
            .zapBlanks()
            .expectByte(':', "JSON property is missing a colon after its name")
            .zapBlanks()
            let valuePosition = .stream.position()
            if .propertyMatches(val)
            {
                if foundPosition != Swag.U64.Max do
                    fail .getError("JSON object contains a duplicate property")
                foundPosition = valuePosition
            }

            .skipValue()
            .zapBlanks()
            let separator = .stream.readU8()
            if separator == '}' do
                break
            if separator != ',' do
                fail .getError("JSON object needs a comma between properties")
            .zapBlanks()
        }

        if foundPosition == Swag.U64.Max
        {
            .stream.setPosition(.endPositions[index])
            return false
        }

        .stream.setPosition(foundPosition)
        return true
    }

    // Completes a property.
    mtd endElement(_val: TypeValue) fail {}

    // Begins a value, consuming the separator required by an enclosing array.
    mtd beginValue() fail
    {
        if !.containerDepth do
            return
        let index = .containerDepth - 1
        if .containerKinds[index] != 0 do
            return

        .zapBlanks()
        if .firstValues[index]
        {
            .firstValues[index] = false
            return
        }

        .expectByte(',', "JSON array needs a comma between values")
        .zapBlanks()
        if .stream.peekU8() == ']' do
            fail .getError("JSON array has a trailing comma")
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
                .readLiteral("true")
                return true
            }

            if .stream.peekU8() == 'f'
            {
                .readLiteral("false")
                return false
            }

            fail .getError("JSON Boolean value must be true or false")

        case Core.String:
            if .stream.peekU8() == 'n'
            {
                .readLiteral("null")
                var result: retval
                return result
            }

            var result: retval
            .readString(&result)
            return result

        default:
            let start = .stream.position()
            .skipNumber()
            let length = .stream.position() - start
            let token  = Swag.makeString(.stream.data() + start, length)
            #static switch NT
            {
            case f32:
                let val = StrConv.parseF32(token)
                if val.eat != length do
                    fail .getError("JSON number cannot be represented as f32")
                return val.value

            case f64:
                let val = StrConv.parseF64(token)
                if val.eat != length do
                    fail .getError("JSON number cannot be represented as f64")
                return val.value

            case s8:
                let val = StrConv.parseS8(token)
                if val.eat != length or val.ovf do
                    fail .getError("JSON number cannot be represented as s8")
                return val.value

            case s16:
                let val = StrConv.parseS16(token)
                if val.eat != length or val.ovf do
                    fail .getError("JSON number cannot be represented as s16")
                return val.value

            case s32:
                let val = StrConv.parseS32(token)
                if val.eat != length or val.ovf do
                    fail .getError("JSON number cannot be represented as s32")
                return val.value

            case s64:
                let val = StrConv.parseS64(token)
                if val.eat != length or val.ovf do
                    fail .getError("JSON number cannot be represented as s64")
                return val.value

            case u8:
                let val = StrConv.parseU8(token)
                if val.eat != length or val.ovf do
                    fail .getError("JSON number cannot be represented as u8")
                return val.value

            case u16:
                let val = StrConv.parseU16(token)
                if val.eat != length or val.ovf do
                    fail .getError("JSON number cannot be represented as u16")
                return val.value

            case u32:
                let val = StrConv.parseU32(token)
                if val.eat != length or val.ovf do
                    fail .getError("JSON number cannot be represented as u32")
                return val.value

            case u64:
                let val = StrConv.parseU64(token)
                if val.eat != length or val.ovf do
                    fail .getError("JSON number cannot be represented as u64")
                return val.value
            }
        }
    }
}
