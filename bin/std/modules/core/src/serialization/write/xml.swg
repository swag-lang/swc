#global namespace Serialization
#global namespace Write
#global public

using Swag, Core.Errors

// Returns whether the reader consumes `type` as one undelimited text value.
internal func xmlIsStringValue(type: typeinfo?)->bool
{
    if not type do
        return false

    var resolved = Reflection.resolveAliases(type)
    if Reflection.isEnum(resolved) do
        resolved = Reflection.enumUnderlyingType(resolved)
    return Reflection.isString(resolved) or resolved == Core.String
}

// Returns whether the XML reader can consume values of `type` in its ordered element format.
internal func xmlCanWrite(type: typeinfo?)->bool
{
    if not type do
        return false

    var resolved = Reflection.resolveAliases(type)
    if Reflection.isEnum(resolved)
    {
        resolved = Reflection.enumUnderlyingType(resolved)
        return xmlCanWrite(resolved)
    }

    if Reflection.isNative(resolved)
    {
        return Reflection.isBool(resolved) or Reflection.isInteger(resolved) or
               Reflection.isFloat(resolved) or Reflection.isRune(resolved)
    }

    if resolved == Core.String do
        return true
    if Reflection.isType(resolved) do
        return true
    if Reflection.isInterface(resolved) do
        return false

    let elementType = Reflection.dynamicArrayElementType(resolved)
    if elementType
    {
        // The reader has no end marker for dynamic arrays of structs and reads string text as one value.
        return not Reflection.isStruct(elementType) and not xmlIsStringValue(elementType) and
               not Reflection.dynamicArrayElementType(elementType) and xmlCanWrite(elementType)
    }

    if Reflection.isStaticArray(resolved)
    {
        let arrayType = assume cast(const *TypeInfoArray, resolved)
        return not xmlIsStringValue(arrayType.pointedType) and
               not Reflection.dynamicArrayElementType(arrayType.pointedType) and
               xmlCanWrite(arrayType.pointedType)
    }

    if not Reflection.isStruct(resolved) or Reflection.isTuple(resolved) do
        return false
    if Reflection.hasInterface(resolved, ISerialize) do
        return true

    let typeStruct = assume cast(const *TypeInfoStruct, resolved)
    for &field in typeStruct.fields
    {
        if Reflection.hasAttribute(field, NoSerialize) or
           Reflection.hasAttribute(field.pointedType, NoSerialize) do
            continue
        if not xmlCanWrite(field.pointedType) do
            return false
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
        output:         *ConcatBuffer?
        sequenceCounts:       Array'u64
        sequenceStructDepths: Array'u64
        structDepth:          u64
        invalidCharacters:    bool
        unsupportedValues:    bool
        fmtInt:               StrConv.ConvertFormatInt
        fmtFloat:             StrConv.ConvertFormatFloat = {fmt: 'g'u8}
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
        if not type do
            return 0
        return type.crc
    }

    internal mtd setRootType(type: typeinfo) fail
    {
        if not xmlCanWrite(type) do
            fail UnsupportedFormatError{"XML does not support the serialized root type"}
    }

    internal mtd writeString(value: string?)
    {
        if not value do
            return

        let text = value
        for c in text
        {
            switch c
            {
            case '&':  .getOutput().addBytes("&amp;")
            case '<':  .getOutput().addBytes("&lt;")
            case '>':  .getOutput().addBytes("&gt;")
            case '"': .getOutput().addBytes("&quot;")
            case '\'': .getOutput().addBytes("&apos;")
            case '\r': .getOutput().addBytes("&#13;")
            default:   .getOutput().addNative(c)
            }
        }

        let bytes = cast(const [..] u8, text)
        if not Utf8.isValid(bytes)
        {
            .invalidCharacters = true
            return
        }

        var offset = 0'u64
        while offset < bytes.count
        {
            let {c, eat} = Utf8.decodeRune(bytes[offset to])
            if (c < 0x20 and c != '\t' and c != '\n' and c != '\r') or c == 0xFFFE or c == 0xFFFF do
                .invalidCharacters = true
            offset += eat
        }
    }

    // Starts writing a document to `buf`.
    mtd startWrite(buf: *ConcatBuffer)
    {
        .output = buf
        .sequenceCounts.clear()
        .sequenceStructDepths.clear()
        .structDepth = 0
        .invalidCharacters = false
        .unsupportedValues = false
    }

    internal mtd abortWrite()
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
        if .unsupportedValues do
            fail UnsupportedFormatError{"XML does not support the serialized value shape"}
        if .invalidCharacters do
            fail SerializationError{"XML output contains a character forbidden by XML 1.0"}
    }

    // Opens the element named by the serialized field.
    mtd beginElement(val: TypeValue)
    {
        if not xmlCanWrite(val.pointedType) do
            .unsupportedValues = true
        .getOutput().addNative('<'u8)
        .getOutput().addBytes(val.name orelse "")
        .getOutput().addNative('>'u8)
    }

    // Closes the element named by the serialized field.
    mtd endElement(val: TypeValue)
    {
        .getOutput().addBytes("</")
        .getOutput().addBytes(val.name orelse "")
        .getOutput().addNative('>'u8)
    }

    // Returns false, so the encoder writes the struct fields in declaration order.
    mtd beginStruct(type: typeinfo?, _: const *u8?)->bool
    {
        if not xmlCanWrite(type) do
            .unsupportedValues = true
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
        let elementType = dynamicElementType orelse type
        if not xmlCanWrite(elementType) or xmlIsStringValue(elementType) or
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
            if count[] do .getOutput().addNative(' 'u8)
            count[] += 1
        }

        #static if NT == bool
        {
            .getOutput().addBytes(value ? "true" : "false")
        }
        elif Reflection.isFloat(NT)
        {
            StrConv.convertFloatInvariant(.getOutput(), value, .fmtFloat)
        }
        elif Reflection.isInteger(NT)
        {
            StrConv.convertInt(.getOutput(), value, .fmtInt)
        }
        elif Reflection.isString(NT)
        {
            .writeString(value)
        }
        else
        {
            #error("invalid type")
        }
    }
}
