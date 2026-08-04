#global namespace Serialization
#global namespace Read

using Swag, Core.Errors

// Reads XML whose element order matches the serialized Swag type.
//
// Unknown, missing, and reordered elements fail. The input slice is borrowed
// until decoding completes.
public struct Xml
{
    internal
    {
        stream:    ByteStream         // Input cursor.
        line, col: u64 = 1            // One-based source position.
        stackTags: Array'(string)     // Borrowed open element names.
    }
}

public impl Xml
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
        return Latin1.trim(cast(string) .stream.readBuffer![start until end])
    }

    internal mtd readStartTag()->string fail
    {
        let tag = .readTag()
        .stackTags.add(tag)
        return tag
    }

    internal mtd readEndTag() fail
    {
        let tag   = .readTag()
        let start = .stackTags.popBack()
        if tag[1 to ] != start do
            fail .getError(Format.toString("invalid end tag [[%]] for [[%]]", tag, start))
    }

    internal mtd getError(val: string)->SyntaxError
    {
        var err: retval
        err.message = Errors.mkString(val)
        err.line    = .line
        err.col     = .col
        err.seek    = .stream.seek
        return err
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
            else
            {
                .col += 1
            }

            c = .stream.peekU8()
        }
    }

    // Starts decoding from borrowed XML bytes and resets reusable state.
    mtd startRead(input: const [..] u8)
    {
        .stream = ByteStream.openRead(input)
        .line   = 1
        .col    = 1
        .stackTags.clear()
    }

    // Converts this value to next sequence element.
    mtd toNextSequenceElement(_countElem: *u64)->bool
    {
        let c = .stream.peekU8()
        return c != '<'
    }

    // Begins section.
    mtd beginSection(_kind: SectionKind) fail
    {
        discard .readTag()
    }

    // Performs the end section operation.
    mtd endSection() fail
    {
        discard .readTag()
    }

    // Begins root.
    mtd beginRoot() fail
    {
        discard .readStartTag()
    }

    // Performs the end root operation.
    mtd endRoot() fail
    {
        .readEndTag()
    }

    // Begins element.
    mtd beginElement(val: TypeValue)->bool fail
    {
        let tag = .readStartTag()
        if tag != val.name do
            fail .getError("invalid property name")
        return true
    }

    // Performs the end element operation.
    mtd endElement(_val: TypeValue) fail
    {
        .readEndTag()
    }

    #[Warning("Wrn0006", WarningLevel.Disable)]
    {
        // Begins struct.
        mtd beginStruct(structType: typeinfo, structData: const *u8)->bool fail
        {
            return false
        }

        // Performs the end struct operation.
        mtd endStruct() fail {}

        // Begins sequence.
        mtd beginSequence(_typeElem: typeinfo, _data: *u8, _countElem: *u64)->bool fail
        {
            return false
        }

        // Performs the end sequence operation.
        mtd endSequence() fail {}

        // Begins value.
        mtd beginValue() fail {}

        // Performs the end value operation.
        mtd endValue() fail {}
    }

    /////////////////////////////////
    // VALUES
    /////////////////////////////////

    // Reads a native value at the current XML position.
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
            var result: retval
            var c = .stream.peekU8()
            while c and c != '<'
            {
                c      = .stream.readU8()
                result += c
                c      = .stream.peekU8()
            }

            return result

        default:
            #error("invalid type")
        }
    }
}
