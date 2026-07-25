#global namespace Serialization
#global namespace Read

using Swag, Core.Errors

/*
A simple JSON reader.
In the case of a struct, the JSON file must represent the structure layout (order of fields matters).
*/
public struct JSon
{
    stream:    ByteStream
    line, col: u64 = 1
    propName:  String
}

public impl JSon
{
    #[Warning("Wrn0006", WarningLevel.Disable)]
    mtd getVersion()->u32
    {
        return 0
    }

    #[Warning("Wrn0006", WarningLevel.Disable)]
    mtd isTextual()->bool
    {
        return true
    }

    mtd getError(val: string)->SyntaxError
    {
        var err: retval
        err.message = val
        err.line    = .line
        err.col     = .col
        err.seek    = .stream.seek
        return err
    }

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

    mtd startRead(input: const [..] u8)
    {
        .stream = ByteStream.openRead(input)
    }

    mtd beginSequence(_typeElem: #null typeinfo, _data: #null *u8, _countElem: *u64)->bool fail
    {
        .zapBlanks()
        let c = .stream.readU8()
        if c != '[' do
            fail .getError("malformed array, missing opening [[[?]]")
        return false
    }

    mtd endSequence() fail
    {
        .zapBlanks()
        let c = .stream.readU8()
        if c != ']' do
            fail .getError("malformed array; missing closing [[?]]]")
    }

    mtd toNextSequenceElement(_countElem: *u64)->bool
    {
        .zapBlanks()
        let c = .stream.peekU8()
        return c != ']'
    }

    #[Warning("Wrn0006", WarningLevel.Disable)]
    mtd beginRoot() fail {}

    #[Warning("Wrn0006", WarningLevel.Disable)]
    mtd endRoot() fail {}

    mtd beginSection(_kind: SectionKind) fail
    {
        .zapBlanks()
        let c = .stream.readU8()
        if c != '{' do
            fail .getError("malformed struct, missing opening [[{]]")
    }

    mtd endSection() fail
    {
        .zapBlanks()
        let c = .stream.readU8()
        if c != '}' do
            fail .getError("malformed struct, missing closing [[}]]")
    }

    mtd beginStruct(_structType: #null typeinfo, _structData: #null const *u8)->bool fail
    {
        .beginSection(.Ordered)
        return false
    }

    mtd endStruct() fail
    {
        .endSection()
    }

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

    #[Warning("Wrn0006", WarningLevel.Disable)]
    mtd endElement(_val: TypeValue) fail {}

    #[Warning("Wrn0006", WarningLevel.Disable)]
    mtd beginValue() fail {}

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

    mtd(NT) readNative()->NT fail
    {
        .zapBlanks()
        #if NT == bool
        {
            let val = StrConv.parseBool(.stream.remainReadToString())
            .stream.moveSeek(val.eat)
            return val.value
        }
        #elif NT == f32
        {
            let val = StrConv.parseF32(.stream.remainReadToString())
            .stream.moveSeek(val.eat)
            return val.value
        }
        #elif NT == f64
        {
            let val = StrConv.parseF64(.stream.remainReadToString())
            .stream.moveSeek(val.eat)
            return val.value
        }
        #elif NT == s8
        {
            let val = StrConv.parseS8(.stream.remainReadToString())
            .stream.moveSeek(val.eat)
            return val.value
        }
        #elif NT == s16
        {
            let val = StrConv.parseS16(.stream.remainReadToString())
            .stream.moveSeek(val.eat)
            return val.value
        }
        #elif NT == s32
        {
            let val = StrConv.parseS32(.stream.remainReadToString())
            .stream.moveSeek(val.eat)
            return val.value
        }
        #elif NT == s64
        {
            let val = StrConv.parseS64(.stream.remainReadToString())
            .stream.moveSeek(val.eat)
            return val.value
        }
        #elif NT == u8
        {
            let val = StrConv.parseU8(.stream.remainReadToString())
            .stream.moveSeek(val.eat)
            return val.value
        }
        #elif NT == u16
        {
            let val = StrConv.parseU16(.stream.remainReadToString())
            .stream.moveSeek(val.eat)
            return val.value
        }
        #elif NT == u32
        {
            let val = StrConv.parseU32(.stream.remainReadToString())
            .stream.moveSeek(val.eat)
            return val.value
        }
        #elif NT == u64
        {
            let val = StrConv.parseU64(.stream.remainReadToString())
            .stream.moveSeek(val.eat)
            return val.value
        }
        #elif NT == Core.String
        {
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
        }
        #else
        {
            #error("invalid type")
        }
    }
}
