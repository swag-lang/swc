#global namespace Serialization
#global namespace Read

using Swag, Core.Errors

/*
A simple JSON reader.
In the case of a struct, the JSON file must represent the structure layout (order of fields matters).
*/
public struct JSon
{
    stream:    ByteStream // Stream associated with this value.
    line, col: u64 = 1 // Line associated with this value.
    propName:  String // Prop name associated with this value.
}

public impl JSon
{
    // Returns version.
    #[Warning("Wrn0006", WarningLevel.Disable)]
    mtd getVersion()->u32
    {
        return 0
    }

    // Returns whether textual.
    #[Warning("Wrn0006", WarningLevel.Disable)]
    mtd isTextual()->bool
    {
        return true
    }

    // Returns error.
    mtd getError(val: string)->SyntaxError
    {
        var err: retval
        err.message = val
        err.line    = .line
        err.col     = .col
        err.seek    = .stream.seek
        return err
    }

    // Performs the zap blanks operation.
    mtd zapBlanks()
    {
        var c = .stream.peekU8()
        while c and Latin1.isSpace(c)
        {
            .stream.moveSeek()
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
        .stream = ByteStream.openRead(input)
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
        var c = .stream.readU8()
        if c != '"' do
            fail .getError("malformed property name, missing opening [[\"]]")

        .propName.clear()
        c = .stream.readU8()
        while c and c != '"'
        {
            .propName += c
            c         = .stream.readU8()
        }

        if .propName != val.name do
            fail .getError("invalid property name")

        if c != '"' do
            fail .getError("malformed property name, missing closing [[\"]]")

        .zapBlanks()
        c = .stream.readU8()
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
            .stream.moveSeek()
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
            let val = StrConv.parseBool(.stream.remainReadToString())
            .stream.moveSeek(val.eat)
            return val.value

        case f32:
            let val = StrConv.parseF32(.stream.remainReadToString())
            .stream.moveSeek(val.eat)
            return val.value

        case f64:
            let val = StrConv.parseF64(.stream.remainReadToString())
            .stream.moveSeek(val.eat)
            return val.value

        case s8:
            let val = StrConv.parseS8(.stream.remainReadToString())
            .stream.moveSeek(val.eat)
            return val.value

        case s16:
            let val = StrConv.parseS16(.stream.remainReadToString())
            .stream.moveSeek(val.eat)
            return val.value

        case s32:
            let val = StrConv.parseS32(.stream.remainReadToString())
            .stream.moveSeek(val.eat)
            return val.value

        case s64:
            let val = StrConv.parseS64(.stream.remainReadToString())
            .stream.moveSeek(val.eat)
            return val.value

        case u8:
            let val = StrConv.parseU8(.stream.remainReadToString())
            .stream.moveSeek(val.eat)
            return val.value

        case u16:
            let val = StrConv.parseU16(.stream.remainReadToString())
            .stream.moveSeek(val.eat)
            return val.value

        case u32:
            let val = StrConv.parseU32(.stream.remainReadToString())
            .stream.moveSeek(val.eat)
            return val.value

        case u64:
            let val = StrConv.parseU64(.stream.remainReadToString())
            .stream.moveSeek(val.eat)
            return val.value

        case Core.String:
            var result: retval

            .zapBlanks()
            var c = .stream.readU8()
            if c != '"'
            {
                if c == 'n' and
                   .stream.readU8() == 'u' and
                   .stream.readU8() == 'l' and
                   .stream.readU8() == 'l'
                {
                    return result
                }

                fail .getError("malformed string, missing opening [[\"]]")
            }

            c = .stream.peekU8()
            while c and c != '"'
            {
                c      = .stream.readU8()
                result += c
                c      = .stream.peekU8()
            }

            c = .stream.readU8()
            if c != '"' do
                fail .getError("malformed string, missing closing [[\"]]")

            return result

        default:
            #error("invalid type")
        }
    }
}
