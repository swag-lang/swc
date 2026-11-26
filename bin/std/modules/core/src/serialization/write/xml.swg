#global namespace Serialization
#global namespace Write
#global public

using Swag, Core.Errors

// Returns whether the reader consumes `type` as one undelimited text value.
internal func xmlIsStringValue(type: typeinfo?)->bool
{
    if not type
    {
        return false
    }

    var resolved = Reflection.resolveAliases(type)
    if Reflection.isEnum(resolved)
    {
        resolved = Reflection.enumUnderlyingType(resolved)
    }

    return Reflection.isString(resolved) or resolved == Core.String
}

// Returns whether the XML reader can consume values of `type` in its ordered element format.
internal func xmlCanWrite(type: typeinfo?)->bool
{
    if not type
    {
        return false
    }

    var resolved = Reflection.resolveAliases(type)
    if Reflection.isEnum(resolved)
    {
        resolved = Reflection.enumUnderlyingType(resolved)
        return xmlCanWrite(resolved)
    }

    if Reflection.isNative(resolved)
    {
        return Reflection.isBool(resolved) or
               Reflection.isInteger(resolved) or
               Reflection.isFloat(resolved) or
               Reflection.isRune(resolved)
    }

    if resolved == Core.String
    {
        return true
    }

    if Reflection.isType(resolved)
    {
        return true
    }

    if Reflection.isInterface(resolved)
    {
        return false
    }

    let elementType = Reflection.dynamicArrayElementType(resolved)
    if elementType
    {
        // The reader has no end marker for dynamic arrays of structs and reads string text as one value.
        return not Reflection.isStruct(elementType) and
               not xmlIsStringValue(elementType) and
               not Reflection.dynamicArrayElementType(elementType) and
               xmlCanWrite(elementType)
    }

    if Reflection.isStaticArray(resolved)
    {
        let arrayType = assume cast(const *TypeInfoArray, resolved)
        return not xmlIsStringValue(arrayType.pointedType) and
               not Reflection.dynamicArrayElementType(arrayType.pointedType) and
               xmlCanWrite(arrayType.pointedType)
    }

    if not Reflection.isStruct(resolved) or Reflection.isTuple(resolved)
    {
        return false
    }

    if Reflection.hasInterface(resolved, ISerialize)
    {
        return true
    }

    let typeStruct = assume cast(const *TypeInfoStruct, resolved)
    for &field in typeStruct.fields
    {
        if Reflection.hasAttribute(field, NoSerialize) or
           Reflection.hasAttribute(field.pointedType, NoSerialize)
        {
            continue
        }

        if not xmlCanWrite(field.pointedType)
        {
            return false
        }
    }

    return true
}

// Writes XML whose element order matches the serialized Swag type.
//
// The document root is named `root`, each struct field becomes an element named after its
// source field, and Boolean or numeric sequences store values separated by spaces. [[Core.String]]
// values escape the five predefined XML entities, and carriage returns use a character
// reference so XML line-ending normalization preserves them. Unsupported value shapes fail
// with [[Core.Errors.UnsupportedFormatError]]; XML 1.0 forbidden characters fail with
// [[Core.Errors.SerializationError]] when the document ends.
struct Xml
{
    internal
    {
        output:               *ConcatBuffer?
        sequenceCounts:       Array!{u64}
        sequenceStructDepths: Array!{u64}
        structDepth:          u64
        invalidCharacters:    bool
        unsupportedValues:    bool
        fmtInt:               StrConv.ConvertFormatInt
        fmtFloat:             StrConv.ConvertFormatFloat = {fmt: 'g'_u8}
    }
}

impl Xml
{
    internal mtd getOutput()->*ConcatBuffer => unwrap .output

    // Returns true, because XML is a textual format.
    mtd isTextual()->bool => true

    // Returns the runtime CRC written when a value contains type information.
    mtd typeCrcOf(type: typeinfo?)->u32
    {
        if not type
        {
            return 0
        }

        return type.crc
    }

    #[Swag.NoDoc]
    mtd setRootType(type: typeinfo) fail
    {
        if not xmlCanWrite(type)
        {
            fail UnsupportedFormatError{"XML does not support the serialized root type"}
        }
    }

    internal mtd writeString(value: string?)
    {
        if not value
        {
            return
        }

        let bytes  = cast(const [..] u8, value)
        let output = .getOutput()
        var start  = 0'u64
        for c, index in bytes
        {
            var entity: string
            switch c
            {
            case '&':  entity = "&amp;"
            case '<':  entity = "&lt;"
            case '>':  entity = "&gt;"
            case '"':  entity = "&quot;"
            case '\'': entity = "&apos;"
            case '\r': entity = "&#13;"
            default:   continue
            }

            output.addBytes(bytes[start until index], contiguous: false)
            output.addBytes(entity)
            start = index + 1
        }

        output.addBytes(bytes[start until bytes.count], contiguous: false)
        if not Utf8.isValid(bytes)
        {
            .invalidCharacters = true
            return
        }

        var offset = 0_u64
        while offset < bytes.count
        {
            let {c, eat} = Utf8.decodeRune(bytes[offset to])
            if (c < 0x20 and c != '\t' and c != '\n' and c != '\r') or c == 0xFFFE or c == 0xFFFF
            {
                .invalidCharacters = true
            }

            offset += eat
        }
    }

    // Starts writing a document to `buf`.
    mtd startWrite(buf: *ConcatBuffer)
    {
        .output = buf
        .sequenceCounts.clear()
        .sequenceStructDepths.clear()
        .structDepth       = 0
        .invalidCharacters = false
        .unsupportedValues = false
    }

    #[Swag.NoDoc]
    mtd abortWrite()
    {
        .output = null
    }

    // Writes the fixed root element around the serialized value.
    mtd beginRoot()
    {
        .getOutput().addBytes("<root>")
    }

    // Closes the root element and reports unsupported shapes or characters forbidden by XML 1.0.
    mtd endRoot() fail
    {
        defer .output = null
        .getOutput().addBytes("</root>")
        if .unsupportedValues
        {
            fail UnsupportedFormatError{"XML does not support the serialized value shape"}
        }

        if .invalidCharacters
        {
            fail SerializationError{"XML output contains a character forbidden by XML 1.0"}
        }
    }

    // Opens the element named by the serialized field.
    mtd beginElement(val: TypeValue)
    {
        if not xmlCanWrite(val.pointedType)
        {
            .unsupportedValues = true
        }

        .getOutput().addNative('<'_u8)
        .getOutput().addBytes(val.name orelse "")
        .getOutput().addNative('>'_u8)
    }

    // Closes the element named by the serialized field.
    mtd endElement(val: TypeValue)
    {
        .getOutput().addBytes("</")
        .getOutput().addBytes(val.name orelse "")
        .getOutput().addNative('>'_u8)
    }

    // Returns false, so the encoder writes the struct fields in declaration order.
    mtd beginStruct(type: typeinfo?, _: const *u8?)->bool
    {
        if not xmlCanWrite(type)
        {
            .unsupportedValues = true
        }

        .structDepth += 1
        return false
    }

    // Closes the current struct depth used to frame scalar sequences.
    mtd endStruct()
    {
        .structDepth -= 1
    }

    // Returns false, so the encoder writes sequence values in order.
    mtd beginSequence(type: typeinfo?, _: const *void?, count: u64)->bool
    {
        let dynamicElementType = Reflection.dynamicArrayElementType(type)
        let elementType        = dynamicElementType orelse type
        if not xmlCanWrite(elementType) or
           xmlIsStringValue(elementType) or
           (dynamicElementType and Reflection.isStruct(elementType) and count > 0) or
           (dynamicElementType and Reflection.dynamicArrayElementType(elementType) and count > 0)
        {
            .unsupportedValues = true
        }

        .sequenceCounts.add(0)
        .sequenceStructDepths.add(.structDepth)
        return false
    }

    // Closes the current sequence.
    mtd endSequence()
    {
        discard .sequenceCounts.popBack()
        discard .sequenceStructDepths.popBack()
    }

    // Does nothing: XML values need no opening mark.
    mtd beginValue() {}

    // Does nothing: XML values need no closing mark.
    mtd endValue() {}

    // Does nothing: XML sections use their containing field element.
    mtd beginSection(_: SectionKind) {}

    // Does nothing: XML sections use their containing field element.
    mtd endSection() {}

    // Writes a Boolean, number, or string as XML text.
    mtd(NT) writeNative(value: NT)
    {
        if not .sequenceCounts.isEmpty() and .sequenceStructDepths.back() == .structDepth
        {
            let count = .sequenceCounts.backPtr()
            if count[]
            {
                .getOutput().addNative(' '_u8)
            }

            count[] += 1
        }

        #static if NT == bool
        {
            .getOutput().addBytes(value ? "true" : "false")
        }
        else if Reflection.isFloat(NT)
        {
            StrConv.convertFloatInvariant(.getOutput(), value, .fmtFloat)
        }
        else if Reflection.isInteger(NT)
        {
            StrConv.convertInt(.getOutput(), value, .fmtInt)
        }
        else if Reflection.isString(NT)
        {
            .writeString(value)
        }
        else
        {
            #error("invalid type")
        }
    }
}
