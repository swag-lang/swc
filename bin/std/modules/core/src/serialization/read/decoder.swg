#global export
#global namespace Serialization

using Swag, Core.Errors

// Reads serialized values, as seen from [[Core.Serialization.ISerialize]] and [[Core.Serialization.Serializer]].
interface IDecoder
{
    // Returns the version of the struct being read, or zero when the format records none.
    mtd version()->u32

    // Returns whether the format is textual, such as JSON, rather than binary.
    mtd isTextual()->bool

    // Starts reading `input`, which stays borrowed until [[Core.Serialization.IDecoder.end]].
    mtd start(input: const [..] u8) fail

    // Finishes reading the document.
    mtd end() fail

    // Opens the field `val` and returns whether the input contains it.
    mtd beginField(val: Swag.TypeValue)->bool fail

    // Closes a field that [[Core.Serialization.IDecoder.beginField]] opened.
    mtd endField(val: Swag.TypeValue) fail

    // Opens a section of kind `kind`.
    mtd beginSection(kind: SectionKind) fail

    // Closes the current section.
    mtd endSection() fail

    // Reads one value of type `dataType` into `data`.
    mtd read(data: *void, dataType: typeinfo) fail

    // Reads `count` bytes into a new block and returns it, or null when `count` is zero.
    //
    // The caller owns the block and releases it with `Memory.free(block, count)`.
    mtd readBufferU8(count: u64)->*u8? fail

    // Reads a `bool`.
    mtd readBool()->bool fail

    // Reads an `s8`.
    mtd readS8()->s8 fail

    // Reads an `s16`.
    mtd readS16()->s16 fail

    // Reads an `s32`.
    mtd readS32()->s32 fail

    // Reads an `s64`.
    mtd readS64()->s64 fail

    // Reads a `u8`.
    mtd readU8()->u8 fail

    // Reads a `u16`.
    mtd readU16()->u16 fail

    // Reads a `u32`.
    mtd readU32()->u32 fail

    // Reads a `u64`.
    mtd readU64()->u64 fail

    // Reads an `f32`.
    mtd readF32()->f32 fail

    // Reads an `f64`.
    mtd readF64()->f64 fail

    // Reads a string and returns an owned copy.
    mtd readString()->String fail
}

// Relaxes how a [[Core.Serialization.Decoder]] treats input that does not decode.
#[Swag.EnumFlags]
enum DecoderFlags
{
    None = 0                   // No optional decoding behavior.
    IgnoreStructFieldError     // Skips a struct field that fails to decode, leaving it at its default value, instead of failing the read.
}

/*
Decodes reflected Swag values through a format backend such as [[Core.Serialization.Read.TagBin]] or [[Core.Serialization.Read.Json]].

[[Core.Serialization.Decoder.readAll]] returns a new value that the caller releases:

```swag
let bytes   = try File.readAllBytes(fileName)
var decoder: Decoder'Read.TagBin
let value   = try decoder.readAll'MyStruct(bytes.toSlice())!
defer Memory.delete(value)
```
*/
struct(T) Decoder
{
    public
    {
        serializer: T                       // Format backend.
        flags:      DecoderFlags = None     // Optional decoding behavior.
    }
}

impl Decoder
{
    // Reads a framed type value into caller-owned storage described by its runtime type.
    mtd readTypeValue(typedVal: TypeValue, data: [*] void?) fail
    {
        if not typedVal.pointedType do
            fail SerializationError{"missing type value pointed type"}
        if not data do
            fail SerializationError{"missing data for type value"}
        discard try .serializer.beginElement(typedVal)
        try .readTypedContent(data, typedVal.pointedType)
        try .serializer.endElement(typedVal)
    }

    // Reads one value into caller-owned storage large and aligned enough for `dataType`.
    mtd readTypedContent(data: [*] void, dataType: typeinfo?) fail
    {
        if not dataType do
            fail SerializationError{"missing data type"}
        var type = Reflection.resolveAliases(dataType orelse #typeof(u8))
        type = Reflection.enumUnderlyingType(type)

        try .serializer.beginValue()
        defer #nofail try .serializer.endValue()

        // Native
        if type.kind == .Native
        {
            let typeNative = cast #assume(const *TypeInfoNative) type
            switch typeNative.nativeKind
            {
            case .Bool:       (cast(*bool) data)[] = try .serializer.readNative'bool()
            case .U8:         (cast(*u8) data)[] = try .serializer.readNative'u8()
            case .U16:        (cast(*u16) data)[] = try .serializer.readNative'u16()
            case .U32, .Rune: (cast(*u32) data)[] = try .serializer.readNative'u32()
            case .U64:        (cast(*u64) data)[] = try .serializer.readNative'u64()
            case .S8:         (cast(*s8) data)[] = try .serializer.readNative's8()
            case .S16:        (cast(*s16) data)[] = try .serializer.readNative's16()
            case .S32:        (cast(*s32) data)[] = try .serializer.readNative's32()
            case .S64:        (cast(*s64) data)[] = try .serializer.readNative's64()
            case .F32:        (cast(*f32) data)[] = try .serializer.readNative'f32()
            case .F64:        (cast(*f64) data)[] = try .serializer.readNative'f64()
            }

            return
        }

        if Reflection.isType(type)
        {
            let crc      = try .serializer.readNative'u32()
            let typeType = Reflection.typeFromCrc(crc)
            (cast(*(typeinfo?)) data)[] = typeType
            return
        }

        if Reflection.isInterface(type)
        {
            let itf = cast(*Swag.Interface) data

            try .serializer.beginSection(.Raw)
            defer #nofail try .serializer.endSection()

            var objType, itfType: typeinfo?
            var typeVal: TypeValue
            typeVal.pointedType = #typeof(typeinfo?)

            #static if T == Read.TagBin
            {
                objType = try .serializer.readInterfaceType()
                itfType = type
                if objType and not Reflection.hasInterface(objType, type) do
                    fail SerializationError{"interface object type does not implement the requested interface"}
            }
            else
            {
                try .readTypeValue(typeVal, &objType)
                if objType do
                    try .readTypeValue(typeVal, &itfType)
            }

            if objType
            {
                itf.itable = Swag.tableOf(objType, itfType)

                typeVal.pointedType = objType
                itf.obj = Memory.new(objType)
                if not itf.obj do
                    fail SerializationError{"cannot allocate interface object"}
                try .readTypeValue(typeVal, itf.obj)
            }

            return
        }

        if Reflection.isStruct(type)
        {
            // Core.String
            if type == String
            {
                let strBuf = cast(*String) data
                strBuf[] = #nodrop try .serializer.readNative'String()
                strBuf.opPostMove()
                return
            }

            // Core.Array
            let valueType = Reflection.dynamicArrayElementType(type)
            if valueType
            {
                let safeValueType = valueType
                var count         = 0'u64
                let treated       = try .serializer.beginSequence(type, data, &count)
                defer #nofail try .serializer.endSequence()

                if not treated
                {
                    Reflection.clearDynamicArray(data, safeValueType)
                    while .serializer.toNextSequenceElement(&count)
                    {
                        let bufArr = Reflection.appendDynamicArrayElement(data, safeValueType, initialize: false)
                        try .readTypedContent(bufArr!, safeValueType)
                    }
                }

                return
            }

            // A structure with an implementation of ISerialize
            let idecoder = cast(IDecoder) me[]
            let itf      = Swag.makeInterface(data, type, ISerialize)
            if itf != null
            {
                if try itf.read(idecoder) do
                    return
            }

            // Generic struct load, driven by the shared per-type plan.
            let structType = cast #assume(const *TypeInfoStruct) type
            let treated    = try .serializer.beginStruct(structType, data)
            defer #nofail try .serializer.endStruct()
            if treated do
                return

            let plan = try planFor(structType)
            for &pf in plan.fields
            {
                let fieldType = pf.value.pointedType
                if not itf or not (try itf.readElement(pf.value, cast([*] u8) data + pf.value.offset, idecoder))
                {
                    let fieldData = cast([*] u8) data + pf.value.offset
                    let doIt      = catch .serializer.beginElement(pf.value) as beginErr

                    // A failed 'beginElement' has already unwound itself, so there is
                    // no element left open to close. Only pair the two once it returned.
                    if beginErr != null
                    {
                        if not (.flags & .IgnoreStructFieldError) do
                            fail beginErr
                        #static if T == Read.TagBin do
                            .serializer.diag.fieldErrors += 1
                        continue
                    }

                    defer #nofail try .serializer.endElement(pf.value)
                    if not doIt do
                        continue

                    catch .readTypedContent(fieldData, fieldType) as readErr
                    if readErr != null and (.flags & .IgnoreStructFieldError)
                    {
                        #static if T == Read.TagBin do
                            .serializer.diag.fieldErrors += 1
                        Reflection.reset(fieldData, fieldType)
                        continue
                    }

                    if readErr != null and not (.flags & .IgnoreStructFieldError) do
                        fail readErr
                }
            }

            // Inform user code we are done
            if itf do
                try itf.postRead(data, idecoder)

            return
        }

        // Static array
        if Reflection.isStaticArray(type)
        {
            let typeArr  = cast #assume(const *TypeInfoArray) type
            let elemType = typeArr.pointedType
            var count    = typeArr.count
            let treated  = try .serializer.beginSequence(elemType, data, &count)
            defer #nofail try .serializer.endSequence()
            if treated do
                return

            var bufArr = cast([*] u8) data
            for count
            {
                try .readTypedContent(bufArr, elemType)
                bufArr += elemType.sizeof
            }

            return
        }
    }

    // Starts reading `input`, which stays borrowed until [[Core.Serialization.Decoder.end]].
    mtd start(input: const [..] u8) fail
    {
        try .serializer.startRead(input)
        try .serializer.beginRoot()
    }

    // Starts deserialization with a reflected root type.
    //
    // TagBin validates its document schema against [[Core.Serialization.Schema]] on
    // `rootType`. Textual decoders ignore the additional type information.
    mtd start(input: const [..] u8, rootType: typeinfo) fail
    {
        #static if T == Read.TagBin do
            .serializer.setExpectedRootType(rootType)
        try .start(input)
    }

    // Finishes reading, and fails when a strict decode met corrupt payloads.
    mtd end() fail
    {
        try .serializer.endRoot()

        // Payload corruption is detected inside no-fail cleanup paths, so it surfaces
        // here: a strict decode refuses the result, a tolerant one keeps it and reports
        // through the diagnostics.
        #static if T == Read.TagBin
        {
            if .serializer.diag.corruptPayloads and not (.flags & .IgnoreStructFieldError) do
                fail SerializationError{"stream carried corrupt payloads"}
        }
    }

    // Reads a whole document whose root is a `TR` struct and returns it in a new allocation.
    //
    // The caller owns the result and releases it with [[Core.Memory.delete]].
    mtd(TR) readAll(input: const [..] u8)->*TR? fail
    {
        Swag.assert(Reflection.isStruct(TR))

        try .start(input, TR)

        let val = Memory.new'TR()
        defer #fail Memory.delete(val)

        try .readTypedContent(val, TR)

        try .end()
        return val
    }
}

impl IDecoder for Decoder
{
    mtd impl start(input: const [..] u8) fail
    {
        try .serializer.startRead(input)
        try .serializer.beginRoot()
    }

    mtd impl end() fail
    {
        try .serializer.endRoot()
    }

    mtd impl beginField(val: Swag.TypeValue)->bool fail
    {
        if not (try .serializer.beginElement(val)) do
            return false
        try .serializer.beginValue()
        return true
    }

    mtd impl endField(val: Swag.TypeValue) fail
    {
        try .serializer.endValue()
        try .serializer.endElement(val)
    }

    mtd impl beginSection(kind: SectionKind) fail
    {
        try .serializer.beginSection(kind)
    }

    mtd impl endSection() fail
    {
        try .serializer.endSection()
    }

    mtd impl version()->u32 => .serializer.version()

    mtd impl isTextual()->bool => .serializer.isTextual()

    mtd impl read(data: *void, dataType: typeinfo) fail
    {
        try .readTypedContent(data, dataType)
    }

    mtd impl readBufferU8(count: u64)->*u8? fail
    {
        if not count do
            return null

        let safeData = cast([*] u8) Memory.alloc(count)
        Memory.clear(safeData, count)
        var decoded = false
        defer if not decoded do
            Memory.free(safeData, count)

        var cpt     = count
        let treated = try .serializer.beginSequence(u8, safeData, &cpt)
        defer #nofail try .serializer.endSequence()

        if not treated
        {
            var ptr = safeData
            for Math.min(cpt, count)
            {
                try .serializer.beginValue()
                ptr[] = try .serializer.readNative'u8()
                try .serializer.endValue()
                ptr += 1
            }
        }

        decoded = true
        return safeData
    }

    mtd impl readBool()->bool fail => try .serializer.readNative'bool()

    mtd impl readS8()->s8 fail => try .serializer.readNative's8()

    mtd impl readS16()->s16 fail => try .serializer.readNative's16()

    mtd impl readS32()->s32 fail => try .serializer.readNative's32()

    mtd impl readS64()->s64 fail => try .serializer.readNative's64()

    mtd impl readU8()->u8 fail => try .serializer.readNative'u8()

    mtd impl readU16()->u16 fail => try .serializer.readNative'u16()

    mtd impl readU32()->u32 fail => try .serializer.readNative'u32()

    mtd impl readU64()->u64 fail => try .serializer.readNative'u64()

    mtd impl readF32()->f32 fail => try .serializer.readNative'f32()

    mtd impl readF64()->f64 fail => try .serializer.readNative'f64()

    mtd impl readString()->String fail => try .serializer.readNative'String()
}
