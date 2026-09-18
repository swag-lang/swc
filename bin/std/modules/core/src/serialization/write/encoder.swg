#global export
#global namespace Serialization

using Swag, Core.Errors

// Selects how the values of a section are framed.
enum SectionKind
{
    Raw           // Unkeyed values, read back in the order they were written
    Unordered     // Keyed values a reader finds in any order, so fields can be added or removed
    Ordered       // Keyed values, read back in the order they were written
}

// Writes serialized values, as seen from [[Core.Serialization.ISerialize]] and [[Core.Serialization.Serializer]].
interface IEncoder
{
    // Returns whether the format is textual, such as JSON, rather than binary.
    mtd isTextual()->bool

    // Starts writing the document to `result`.
    mtd start(result: *ConcatBuffer) fail

    // Finishes writing the document.
    mtd end() fail

    // Opens the field `val`.
    mtd beginField(val: Swag.TypeValue) fail

    // Closes a field that [[Core.Serialization.IEncoder.beginField]] opened.
    mtd endField(val: Swag.TypeValue) fail

    // Opens a section of kind `kind`.
    mtd beginSection(kind: SectionKind) fail

    // Closes the current section.
    mtd endSection() fail

    // Writes the value of type `type` stored at `data`.
    mtd write(data: const [*] void, type: typeinfo) fail

    // Writes the `count` bytes at `data` as one byte sequence.
    //
    // `data` can be null only when `count` is zero.
    mtd writeBufferU8(data: const [*] u8?, count: u64) fail

    // Writes a `bool`.
    mtd writeBool(value: bool)

    // Writes an `s8`.
    mtd writeS8(value: s8)

    // Writes an `s16`.
    mtd writeS16(value: s16)

    // Writes an `s32`.
    mtd writeS32(value: s32)

    // Writes an `s64`.
    mtd writeS64(value: s64)

    // Writes a `u8`.
    mtd writeU8(value: u8)

    // Writes a `u16`.
    mtd writeU16(value: u16)

    // Writes a `u32`.
    mtd writeU32(value: u32)

    // Writes a `u64`.
    mtd writeU64(value: u64)

    // Writes an `f32`.
    mtd writeF32(value: f32)

    // Writes an `f64`.
    mtd writeF64(value: f64)

    // Writes a string.
    mtd writeString(value: string?)
}

/*
Encodes reflected Swag values through a format backend such as [[Core.Serialization.Write.TagBin]] or [[Core.Serialization.Write.Json]].

```swag
var buf:     ConcatBuffer
var encoder: Encoder'Write.TagBin
try encoder.writeAll(&buf, myStruct)
try File.writeAllBytes(file, buf)
```

Can be serialized:
- All simple types: `bool/u8/u16/u32/u64/s8/s16/s32/s64/rune/f32/f64`
- A type value 'typeinfo', which will be saved as a CRC.
- An interface. TagBin stores the concrete struct's stable [[Core.Serialization.TypeKey]] and value.
- A struct.
- A `Core.String`.
- A `Core.Array` of valid values.
- A static array of valid values.

> NOTE:
> Type 'string' is not supported. Consider using [[Core.String]] instead.

A struct can implement [[Core.Serialization.ISerialize]] to drive its own serialization. Otherwise it is saved field by field.
*/
struct(T) Encoder
{
    public
    {
        serializer:     T        // Serializer associated with this value.
        errorIfUnknown: bool     // Whether a value of an unsupported type fails the write instead of being skipped
    }
}

impl Encoder
{
    // Starts writing the document to `result`.
    mtd start(result: *ConcatBuffer) fail
    {
        .serializer.startWrite(result)
        .serializer.beginRoot()
    }

    // Starts serialization with a reflected root type.
    //
    // TagBin derives its document schema from [[Core.Serialization.Schema]] on `rootType`.
    // Textual encoders ignore the additional type information.
    mtd start(result: *ConcatBuffer, rootType: typeinfo) fail
    {
        #static if T == Write.TagBin do
            .serializer.setRootType(rootType)
        try .start(result)
    }

    // Finishes writing the document.
    mtd end() fail
    {
        .serializer.endRoot()
    }

    // Writes the field or element `typeVal`, whose value is stored at `data`.
    mtd writeTypeValue(typeVal: TypeValue, data: const [*] void?) fail
    {
        if not typeVal.pointedType do
            fail SerializationError{"missing type value pointed type"}
        if not data do
            fail SerializationError{"missing data for type value"}
        #static if T == Write.TagBin do
            try .serializer.beginElement(typeVal)
        else do
            .serializer.beginElement(typeVal)
        try .writeValue(data, typeVal.pointedType)
        .serializer.endElement(typeVal)
    }

    // Writes the value of type `dataType` stored at `data`.
    mtd writeValue(data: const [*] void, dataType: typeinfo?) fail
    {
        if not dataType do
            fail SerializationError{"missing data type"}
        var type = Reflection.resolveAliases(dataType orelse #typeof(u8))
        type = Reflection.enumUnderlyingType(type)

        // Validate dynamic identity before opening any TagBin section. A failure here is
        // an ordinary serialization error; unwinding a half-open section would otherwise
        // ask the binary writer to finalize framing that was never completed.
        #static if T == Write.TagBin
        {
            if Reflection.isInterface(type)
            {
                let itf = cast(const *Swag.Interface) data
                if not itf.itable and type.flags & .Nullable == 0 do
                    fail SerializationError{"non-null interface value is missing"}
                let objType = itf.itable ? cast(const *Swag.TypeInfo?) itf.itable[] : null
                discard try .serializer.interfaceTypeKey(objType)
            }
        }

        .serializer.beginValue()
        defer #nofail .serializer.endValue()

        // Native
        if type.kind == .Native
        {
            let typeNative = cast #assume(const *TypeInfoNative) type
            switch typeNative.nativeKind
            {
            case .Bool:       .serializer.writeNative((cast(const *bool) data)[])
            case .U8:         .serializer.writeNative((cast(const *u8) data)[])
            case .U16:        .serializer.writeNative((cast(const *u16) data)[])
            case .U32, .Rune: .serializer.writeNative((cast(const *u32) data)[])
            case .U64:        .serializer.writeNative((cast(const *u64) data)[])
            case .S8:         .serializer.writeNative((cast(const *s8) data)[])
            case .S16:        .serializer.writeNative((cast(const *s16) data)[])
            case .S32:        .serializer.writeNative((cast(const *s32) data)[])
            case .S64:        .serializer.writeNative((cast(const *s64) data)[])
            case .F32:        .serializer.writeNative((cast(const *f32) data)[])
            case .F64:        .serializer.writeNative((cast(const *f64) data)[])
            }

            return
        }

        if Reflection.isType(type)
        {
            let typeType = (cast(const *(typeinfo?)) data!)[]
            .serializer.writeNative(typeType ? .serializer.typeCrcOf(typeType) : 0'u32)
            return
        }

        if Reflection.isInterface(type)
        {
            let itf = cast(const *Swag.Interface) data

            .serializer.beginSection(.Raw)
            defer #nofail .serializer.endSection()

            var objType, itfType: typeinfo?
            if itf.itable
            {
                objType = cast(const *Swag.TypeInfo?) itf.itable![]
                itfType = type
            }

            #static if T == Write.TagBin
            {
                try .serializer.writeInterfaceType(objType)
                if objType
                {
                    if not itf.obj do
                        fail SerializationError{"interface object is missing"}
                    var objValue: TypeValue
                    objValue.pointedType = objType
                    try .writeTypeValue(objValue, itf.obj)
                }

                return
            }

            var typeVal: TypeValue
            typeVal.pointedType = #typeof(typeinfo?)
            try .writeTypeValue(typeVal, &objType)

            if objType
            {
                try .writeTypeValue(typeVal, &itfType)
                typeVal.pointedType = objType
                if not itf.obj do
                    fail SerializationError{"missing interface object"}
                try .writeTypeValue(typeVal, itf.obj)
            }

            return
        }

        if Reflection.isStruct(type)
        {
            if Reflection.isTuple(type)
            {
                if .errorIfUnknown do
                    fail UnsupportedFormatError{"cannot serialize an anonymous struct"}
                return
            }

            // Core.String
            if type == Core.String
            {
                let strBuf = cast(const *String) data
                .serializer.writeNative(strBuf.toString())
                return
            }

            // Core.Array
            let valueType = Reflection.dynamicArrayElementType(type)
            if valueType
            {
                let safeValueType = valueType
                let ptrArr        = cast(const *Array'u8) data
                let treated       = .serializer.beginSequence(type, data, ptrArr.count)
                defer .serializer.endSequence()

                if not treated
                {
                    var bufArr = cast(const [*] u8?) ptrArr.buffer
                    for ptrArr.count
                    {
                        try .writeValue(bufArr!, safeValueType)
                        bufArr += safeValueType.sizeof
                    }
                }

                return
            }

            // A structure with an implementation of ISerialize
            let itf = Swag.makeInterface(data, type, ISerialize)
            if itf != null
            {
                if try itf.write(me) do
                    return
            }

            // Start a fields section
            let structType = cast #assume(const *TypeInfoStruct) type
            var treated: bool
            #static if T == Write.TagBin do
                treated = try .serializer.beginStruct(structType, data)
            else do
                treated = .serializer.beginStruct(structType, data)
            defer #nofail .serializer.endStruct()
            if treated do
                return

            // Generic structure save, driven by the shared per-type plan: the field
            // filter, the crcs and the compression policy are computed once per type
            // instead of once per instance.
            let plan = try planFor(structType)
            for &pf in plan.fields
            {
                if not itf or not (try itf.writeElement(pf.value, cast(const [*] u8?) data + pf.value.offset, me))
                {
                    try .writeTypeValue(pf.value, cast(const [*] u8?) data + pf.value.offset)
                }
            }

            return
        }

        // A static array
        if Reflection.isStaticArray(type)
        {
            let typeArr  = cast #assume(const *TypeInfoArray) type
            let elemType = typeArr.pointedType
            let treated  = .serializer.beginSequence(elemType, data, typeArr.count)
            defer .serializer.endSequence()
            if treated do
                return

            var bufArr = cast(const [*] u8) data
            for typeArr.count
            {
                try .writeValue(bufArr, elemType)
                bufArr += elemType.sizeof
            }

            return
        }

        if .errorIfUnknown do
            fail UnsupportedFormatError{Errors.mkString(Format.toString("cannot serialize type [[%]]", type.name))}
    }

    // Writes the struct `value` as a complete document to `result`.
    //
    // This is [[Core.Serialization.Encoder.start]], [[Core.Serialization.Encoder.writeValue]],
    // then [[Core.Serialization.Encoder.end]].
    mtd writeAll(result: *ConcatBuffer, value: any) fail
    {
        Swag.assert(Reflection.isStruct(Swag.kindOf(value)))
        try .start(result, Swag.kindOf(value))
        try .writeValue(value.buffer, Swag.kindOf(value))
        try .end()
    }
}

impl IEncoder for Encoder
{
    mtd impl isTextual()->bool => .serializer.isTextual()

    mtd impl start(result: *ConcatBuffer) fail
    {
        .serializer.startWrite(result)
        .serializer.beginRoot()
    }

    mtd impl end() fail
    {
        .serializer.endRoot()
    }

    mtd impl beginField(val: Swag.TypeValue) fail
    {
        #static if T == Write.TagBin do
            try .serializer.beginElement(val)
        else do
            .serializer.beginElement(val)
        .serializer.beginValue()
    }

    mtd impl endField(val: Swag.TypeValue) fail
    {
        .serializer.endValue()
        .serializer.endElement(val)
    }

    mtd impl beginSection(kind: SectionKind) fail
    {
        .serializer.beginSection(kind)
    }

    mtd impl endSection() fail
    {
        .serializer.endSection()
    }

    mtd impl write(data: const [*] void, type: typeinfo) fail
    {
        try .writeValue(data, type)
    }

    mtd impl writeBufferU8(data: const [*] u8?, count: u64) fail
    {
        if not data
        {
            if count do
                fail SerializationError{"cannot write a null u8 buffer"}
            return
        }

        let safeData = data
        let treated  = .serializer.beginSequence(u8, safeData, count)
        defer #nofail .serializer.endSequence()

        if not treated
        {
            var ptr = safeData
            for count
            {
                .serializer.beginValue()
                .serializer.writeNative(ptr[])
                .serializer.endValue()
                ptr += 1
            }
        }
    }

    mtd impl writeBool(value: bool) => .serializer.writeNative(value)

    mtd impl writeS8(value: s8) => .serializer.writeNative(value)

    mtd impl writeS16(value: s16) => .serializer.writeNative(value)

    mtd impl writeS32(value: s32) => .serializer.writeNative(value)

    mtd impl writeS64(value: s64) => .serializer.writeNative(value)

    mtd impl writeU8(value: u8) => .serializer.writeNative(value)

    mtd impl writeU16(value: u16) => .serializer.writeNative(value)

    mtd impl writeU32(value: u32) => .serializer.writeNative(value)

    mtd impl writeU64(value: u64) => .serializer.writeNative(value)

    mtd impl writeF32(value: f32) => .serializer.writeNative(value)

    mtd impl writeF64(value: f64) => .serializer.writeNative(value)

    mtd impl writeString(value: string?) => .serializer.writeNative(value)
}
