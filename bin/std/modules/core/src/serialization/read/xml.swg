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
        line, col: u64 = 1            // One-based source position.
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
        return Latin1.trim(cast(string) .stream.readBuffer![start until end])
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
        if not Utf8.startsWith(tag, "/") or tag[1 to] != start do
            fail .getError(Format.toString("invalid end tag [[%]] for [[%]]", tag, start))
    }

    // Reads the predefined entity after an '&' and returns the character it stands for.
    internal mtd readEntity()->u8 fail
    {
        const Names = ["lt;", "gt;", "amp;", "quot;", "apos;"]
        const Chars = "<>&\"'"
        let rest    = .stream.remainingString()
        for index in Names.count
        {
            if Utf8.startsWith(rest, Names[index])
            {
                .stream.advance(Names[index].count)
                return Chars[index]
            }
        }

        fail .getError("unknown entity, expected [[&lt;]], [[&gt;]], [[&amp;]], [[&quot;]], or [[&apos;]]")
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
    mtd startRead(input: const [..] u8) fail
    {
        .stream = ByteStream.openRead(input)
        .line   = 1
        .col    = 1
        .stackTags.clear()
    }

    // Returns whether another sequence element follows, that is, whether the next non-blank byte does not start a tag.
    mtd toNextSequenceElement(_countElem: *u64)->bool
    {
        .zapBlanks()
        return .stream.peekU8() != '<'
    }

    // Reads the tag that opens a section.
    mtd beginSection(_kind: SectionKind) fail
    {
        discard try .readTag()
    }

    // Reads the tag that closes a section.
    mtd endSection() fail
    {
        discard try .readTag()
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

    // Reads the tag that closes the document, which must match the opening one.
    mtd endRoot() fail
    {
        try .readEndTag()
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
    mtd endElement(_val: TypeValue) fail
    {
        try .readEndTag()
    }

    {
        // Returns false, so the decoder reads the fields of the struct.
        mtd beginStruct(structType: typeinfo, structData: const *u8)->bool fail => false

        // Does nothing: the struct ends with its last element.
        mtd endStruct() fail {}

        // Returns false, so the decoder reads the elements one by one.
        mtd beginSequence(_typeElem: typeinfo, _data: *u8, _countElem: *u64)->bool fail => false

        // Does nothing: the sequence ends before the next tag.
        mtd endSequence() fail {}

        // Does nothing: an XML value needs no opening mark.
        mtd beginValue() fail {}

        // Does nothing: an XML value needs no closing mark.
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
            let val = try StrConv.parseBool(.stream.remainingString())
            .stream.advance(val.eat)
            return val.value

        case f32:
            let val = try StrConv.parseF32(.stream.remainingString())
            .stream.advance(val.eat)
            return val.value

        case f64:
            let val = try StrConv.parseF64(.stream.remainingString())
            .stream.advance(val.eat)
            return val.value

        case s8:
            let val = try StrConv.parseS8(.stream.remainingString())
            .stream.advance(val.eat)
            return val.value

        case s16:
            let val = try StrConv.parseS16(.stream.remainingString())
            .stream.advance(val.eat)
            return val.value

        case s32:
            let val = try StrConv.parseS32(.stream.remainingString())
            .stream.advance(val.eat)
            return val.value

        case s64:
            let val = try StrConv.parseS64(.stream.remainingString())
            .stream.advance(val.eat)
            return val.value

        case u8:
            let val = try StrConv.parseU8(.stream.remainingString())
            .stream.advance(val.eat)
            return val.value

        case u16:
            let val = try StrConv.parseU16(.stream.remainingString())
            .stream.advance(val.eat)
            return val.value

        case u32:
            let val = try StrConv.parseU32(.stream.remainingString())
            .stream.advance(val.eat)
            return val.value

        case u64:
            let val = try StrConv.parseU64(.stream.remainingString())
            .stream.advance(val.eat)
            return val.value

        case Core.String:
            var result: retval
            var c = .stream.peekU8()
            while c and c != '<'
            {
                .stream.advance()
                if c == '&' do
                    result += try .readEntity()
                else do
                    result += c
                c = .stream.peekU8()
            }

            return result

        default:
            #error("invalid type")
        }
    }
}
