#global namespace Serialization
#global namespace Read

using Swag, Core.Errors

// Reads JSON objects whose property order matches the serialized Swag type.
//
// Strings support the complete JSON escape set, including UTF-16 surrogate
// pairs in `\uXXXX` escapes. Unknown, missing, and reordered properties fail.
public struct Json
{
    internal
    {
        stream:    ByteStream     // Input cursor.
        line, col: u64 = 1        // One-based source position.
        propName:  String         // Reusable decoded property name.
    }
}

public impl Json
{
    // Returns version.
    #[Warning("Wrn0006", WarningLevel.Disable)]
    mtd version()->u32
    {
        return 0
    }

    // Returns whether textual.
    #[Warning("Wrn0006", WarningLevel.Disable)]
    mtd isTextual()->bool
    {
        return true
    }

    internal mtd getError(val: string)->SyntaxError
    {
        var err: retval
        err.message = val
        err.line    = .line
        err.col     = .col
        err.seek    = .stream.seek
        return err
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
        if .stream.readU8() != '"' do
            fail .getError("JSON string is missing its opening quote")

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

            let escaped = .stream.readU8()
            switch escaped
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

        unreachable
    }

    internal mtd zapBlanks()
    {
        var c = .stream.peekU8()
        while c and Latin1.isSpace(c)
        {
            .stream.advance()
            if c == '\n'
            {
                .line += 1
                .col  = 1
            }
            else do
                .col += 1
            c        = .stream.peekU8()
        }
    }

    // Defines start read.
    mtd startRead(input: const [..] u8)
    {
        .stream    = ByteStream.openRead(input)
        .line      = 1
        .col       = 1
        .propName.clear()
    }

    // Begins sequence.
    mtd beginSequence(_typeElem: #null typeinfo, _data: #null *u8, _countElem: *u64)->bool fail
    {
        .zapBlanks()
        let c = .stream.readU8()
        if c != '[' do
            fail .getError("malformed array, missing opening [[[?]]")
        return false
    }

    // Performs the end sequence operation.
    mtd endSequence() fail
    {
        .zapBlanks()
        let c = .stream.readU8()
        if c != ']' do
            fail .getError("malformed array; missing closing [[?]]]")
    }

    // Converts this value to next sequence element.
    mtd toNextSequenceElement(_countElem: *u64)->bool
    {
        .zapBlanks()
        let c = .stream.peekU8()
        return c != ']'
    }

    // Begins root.
    #[Warning("Wrn0006", WarningLevel.Disable)]
    mtd beginRoot() fail {}

    // Performs the end root operation.
    #[Warning("Wrn0006", WarningLevel.Disable)]
    mtd endRoot() fail {}

    // Begins section.
    mtd beginSection(_kind: SectionKind) fail
    {
        .zapBlanks()
        let c = .stream.readU8()
        if c != '{' do
            fail .getError("malformed struct, missing opening [[{]]")
    }

    // Performs the end section operation.
    mtd endSection() fail
    {
        .zapBlanks()
        let c = .stream.readU8()
        if c != '}' do
            fail .getError("malformed struct, missing closing [[}]]")
    }

    // Begins struct.
    mtd beginStruct(_structType: #null typeinfo, _structData: #null const *u8)->bool fail
    {
        .beginSection(.Ordered)
        return false
    }

    // Performs the end struct operation.
    mtd endStruct() fail
    {
        .endSection()
    }

    // Begins element.
    mtd beginElement(val: TypeValue)->bool fail
    {
        .zapBlanks()
        .readString(&.propName)

        if .propName != val.name do
            fail .getError("JSON property name does not match the serialized field")

        .zapBlanks()
        let c = .stream.readU8()
        if c != ':' do
            fail .getError("malformed property, missing [[:]] after name")

        return true
    }

    // Performs the end element operation.
    #[Warning("Wrn0006", WarningLevel.Disable)]
    mtd endElement(_val: TypeValue) fail {}

    // Begins value.
    #[Warning("Wrn0006", WarningLevel.Disable)]
    mtd beginValue() fail {}

    // Performs the end value operation.
    mtd endValue() fail
    {
        .zapBlanks()
        let c = .stream.peekU8()
        if c == ',' do
            .stream.advance()
    }

    /////////////////////////////////
    // VALUES
    /////////////////////////////////

    // Reads a native value at the current JSON position.
    mtd(NT) readNative()->NT fail
    {
        .zapBlanks()
        #static switch NT
        {
        case bool:
            let val = StrConv.parseBool(.stream.remainingString())
            .stream.advance(val.eat)
            return val.value

        case f32:
            let val = StrConv.parseF32(.stream.remainingString())
            .stream.advance(val.eat)
            return val.value

        case f64:
            let val = StrConv.parseF64(.stream.remainingString())
            .stream.advance(val.eat)
            return val.value

        case s8:
            let val = StrConv.parseS8(.stream.remainingString())
            .stream.advance(val.eat)
            return val.value

        case s16:
            let val = StrConv.parseS16(.stream.remainingString())
            .stream.advance(val.eat)
            return val.value

        case s32:
            let val = StrConv.parseS32(.stream.remainingString())
            .stream.advance(val.eat)
            return val.value

        case s64:
            let val = StrConv.parseS64(.stream.remainingString())
            .stream.advance(val.eat)
            return val.value

        case u8:
            let val = StrConv.parseU8(.stream.remainingString())
            .stream.advance(val.eat)
            return val.value

        case u16:
            let val = StrConv.parseU16(.stream.remainingString())
            .stream.advance(val.eat)
            return val.value

        case u32:
            let val = StrConv.parseU32(.stream.remainingString())
            .stream.advance(val.eat)
            return val.value

        case u64:
            let val = StrConv.parseU64(.stream.remainingString())
            .stream.advance(val.eat)
            return val.value

        case Core.String:
            .zapBlanks()
            if .stream.peekU8() == 'n'
            {
                if .stream.readU8() != 'n' or .stream.readU8() != 'u' or .stream.readU8() != 'l' or .stream.readU8() != 'l' do
                    fail .getError("JSON null literal is incomplete")
                var result: retval
                return result
            }
            var result: retval
            .readString(&result)
            return result

        default:
            #error("invalid type")
        }
    }
}
