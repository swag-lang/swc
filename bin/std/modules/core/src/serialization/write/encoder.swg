#global export
#global namespace Serialization

using Swag, Core.Errors

// Selects section kind.
enum SectionKind
{
    Raw           // Selects the raw kind.
    Unordered     // Selects the unordered kind.
    Ordered       // Selects the ordered kind.
}

// Defines the operations supported by i encoder.
interface IEncoder
{
    // Returns whether textual.
    mtd isTextual()->bool

    // Starts the operation.
    mtd start(result: *ConcatBuffer) fail

    // Finishes the operation.
    mtd end() fail

    // Begins field.
    mtd beginField(val: Swag.TypeValue) fail

    // Performs the end field operation.
    mtd endField(val: Swag.TypeValue) fail

    // Begins section.
    mtd beginSection(kind: SectionKind) fail

    // Performs the end section operation.
    mtd endSection() fail

    // Defines write.
    mtd write(data: const [*] void, type: typeinfo) fail

    // Writes buffer u8.
    mtd writeBufferU8(data: const [*] u8?, count: u64) fail

    // Writes bool.
    mtd writeBool(value: bool)

    // Writes s8.
    mtd writeS8(value: s8)

    // Writes s16.
    mtd writeS16(value: s16)

    // Writes s32.
    mtd writeS32(value: s32)

    // Writes s64.
    mtd writeS64(value: s64)

    // Writes u8.
    mtd writeU8(value: u8)

    // Writes u16.
    mtd writeU16(value: u16)

    // Writes u32.
    mtd writeU32(value: u32)

    // Writes u64.
    mtd writeU64(value: u64)

    // Writes f32.
    mtd writeF32(value: f32)

    // Writes f64.
    mtd writeF64(value: f64)

    // Writes string.
    mtd writeString(value: string?)
}

/*
Serialization encoder.
This is a high level encoder that needs a specific implementation like [[Core.Serialization.Write.TagBin]] or [[Core.Serialization.Write.Json]].

```swag
var buf:     ConcatBuffer
var encoder: Encoder'Write.TagBin
encoder.writeAll(&buf, myStruct)
File.writeAllBytes(file, buf)
```

Can be serialized:
- All simple types: `bool/u8/u16/u32/u64/s8/s16/s32/s64/rune/f32/f64`
- A type value 'typeinfo', which will be saved as a CRC.
- An interface. TagBin stores the concrete struct's stable 'Serialization.TypeKey' and value.
- A struct.
- A `Core.String`.
- A `Core.Array` of valid values.
- A static array of valid values.

> NOTE:
> Type 'string' is not supported. Consider using [[Core.String]] instead.

A struct can implement the 'ISerialize' interface in order to have a specific serialization. If not defined, then the struct will be saved field by field.
*/
struct(T) Encoder
{
    public
    {
        serializer:     T        // Serializer associated with this value.
        errorIfUnknown: bool     // If true, an error will be raised if a type cannot be saved. The field will be ignored if set to false
    }
}

impl Encoder
{
    // Start serialization
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
        .start(result)
    }

    // End serialization
    mtd end() fail
    {
        .serializer.endRoot()
    }

    // Write a given Swag.TypeValue.
    mtd writeTypeValue(typeVal: TypeValue, data: const [*] void?) fail
    {
        if !typeVal.pointedType do
            fail SerializationError{"missing type value pointed type"}
        if !data do
            fail SerializationError{"missing data for type value"}
        .serializer.beginElement(typeVal)
        .writeValue(data, typeVal.pointedType)
        .serializer.endElement(typeVal)
    }

    // Write a given value with a given type.
    mtd writeValue(data: const [*] void, dataType: typeinfo?) fail
    {
        if !dataType do
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
                if !itf.itable and type.flags & .Nullable == 0 do
                    fail SerializationError{"non-null interface value is missing"}
                let objType = itf.itable ? cast(const *Swag.TypeInfoStruct?) itf.itable![] : null
                discard .serializer.interfaceTypeKey(objType)
            }
        }

        .serializer.beginValue()
        defer #nofail .serializer.endValue()

        // Native
        if type.kind == .Native
        {
            let typeNative = cast(const *TypeInfoNative) type
            switch typeNative.nativeKind
            {
            case .Bool:       .serializer.writeNative(data[as bool])
            case .U8:         .serializer.writeNative(data[as u8])
            case .U16:        .serializer.writeNative(data[as u16])
            case .U32, .Rune: .serializer.writeNative(data[as u32])
            case .U64:        .serializer.writeNative(data[as u64])
            case .S8:         .serializer.writeNative(data[as s8])
            case .S16:        .serializer.writeNative(data[as s16])
            case .S32:        .serializer.writeNative(data[as s32])
            case .S64:        .serializer.writeNative(data[as s64])
            case .F32:        .serializer.writeNative(data[as f32])
            case .F64:        .serializer.writeNative(data[as f64])
            }

            return
        }

        if Reflection.isType(type)
        {
            let typeType = data![as typeinfo?]
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
                objType = cast(const *Swag.TypeInfoStruct?) itf.itable![]
                itfType = type
            }

            #static if T == Write.TagBin
            {
                .serializer.writeInterfaceType(objType)
                if objType
                {
                    if !itf.obj do
                        fail SerializationError{"interface object is missing"}
                    var objValue: TypeValue
                    objValue.pointedType = objType
                    .writeTypeValue(objValue, itf.obj)
                }

                return
            }

            var typeVal: TypeValue
            typeVal.pointedType = #typeof(typeinfo?)
            .writeTypeValue(typeVal, &objType)

            if objType
            {
                .writeTypeValue(typeVal, &itfType)
                typeVal.pointedType = objType
                if !itf.obj do
                    fail SerializationError{"missing interface object"}
                .writeTypeValue(typeVal, itf.obj)
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

                if !treated
                {
                    var bufArr = cast(const [*] u8?) ptrArr.buffer
                    for i in ptrArr.count
                    {
                        .writeValue(bufArr!, safeValueType)
                        bufArr += safeValueType.sizeof
                    }
                }

                return
            }

            // A structure with an implementation of ISerialize
            let itf = Swag.makeInterface(data, type, ISerialize)
            if itf != null
            {
                if itf.write(cast(IEncoder) me[]) do
                    return
            }

            // Start a fields section
            let structType = cast(const *TypeInfoStruct) type
            let treated    = .serializer.beginStruct(structType, data)
            defer #nofail .serializer.endStruct()
            if treated do
                return

            // Generic structure save, driven by the shared per-type plan: the field
            // filter, the crcs and the compression policy are computed once per type
            // instead of once per instance.
            let plan = planFor(structType)
            for &pf in plan.fields
            {
                if !itf or !itf.writeElement(pf.value, cast(const [*] u8?) data + pf.value.offset, cast(IEncoder) me[])
                {
                    .writeTypeValue(pf.value, cast(const [*] u8?) data + pf.value.offset)
                }
            }

            return
        }

        // A static array
        if Reflection.isStaticArray(type)
        {
            let typeArr  = cast(const *TypeInfoArray) type
            let elemType = typeArr.pointedType
            let treated  = .serializer.beginSequence(elemType, data, typeArr.count)
            defer .serializer.endSequence()
            if treated do
                return

            var bufArr = cast(const [*] u8) data
            for typeArr.count
            {
                .writeValue(bufArr, elemType)
                bufArr += elemType.sizeof
            }

            return
        }

        if .errorIfUnknown do
            fail UnsupportedFormatError{Errors.mkString(Format.toString("cannot serialize type [[%]]", type.name))}
    }

    // Write a full struct.
    // Will call [[Encoder.start]], [[Encoder.writeValue]] and [[Encoder.end]]
    mtd writeAll(result: *ConcatBuffer, value: any) fail
    {
        Debug.assert(Reflection.isStruct(Swag.kindOf(value)))
        .start(result, Swag.kindOf(value))
        .writeValue(value.buffer, Swag.kindOf(value))
        end(me)
    }
}

impl IEncoder for Encoder
{
    // Returns whether textual.
    mtd impl isTextual()->bool
    {
        return .serializer.isTextual()
    }

    // Start serialization
    mtd impl start(result: *ConcatBuffer) fail
    {
        .serializer.startWrite(result)
        .serializer.beginRoot()
    }

    // End serialization
    mtd impl end() fail
    {
        .serializer.endRoot()
    }

    // Begins field.
    mtd impl beginField(val: Swag.TypeValue) fail
    {
        .serializer.beginElement(val)
        .serializer.beginValue()
    }

    // Performs the end field operation.
    mtd impl endField(val: Swag.TypeValue) fail
    {
        .serializer.endValue()
        .serializer.endElement(val)
    }

    // Begins section.
    mtd impl beginSection(kind: SectionKind) fail
    {
        .serializer.beginSection(kind)
    }

    // Performs the end section operation.
    mtd impl endSection() fail
    {
        .serializer.endSection()
    }

    // Defines write.
    mtd impl write(data: const [*] void, type: typeinfo) fail
    {
        .writeValue(data, type)
    }

    // Writes buffer u8.
    mtd impl writeBufferU8(data: const [*] u8?, count: u64) fail
    {
        if !data
        {
            if count do
                fail SerializationError{"cannot write a null u8 buffer"}
            return
        }

        let safeData = data
        let treated  = .serializer.beginSequence(u8, safeData, count)
        defer #nofail .serializer.endSequence()

        if !treated
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

    // Writes bool.
    mtd impl writeBool(value: bool) => .serializer.writeNative(value)

    // Writes s8.
    mtd impl writeS8(value: s8) => .serializer.writeNative(value)

    // Writes s16.
    mtd impl writeS16(value: s16) => .serializer.writeNative(value)

    // Writes s32.
    mtd impl writeS32(value: s32) => .serializer.writeNative(value)

    // Writes s64.
    mtd impl writeS64(value: s64) => .serializer.writeNative(value)

    // Writes u8.
    mtd impl writeU8(value: u8) => .serializer.writeNative(value)

    // Writes u16.
    mtd impl writeU16(value: u16) => .serializer.writeNative(value)

    // Writes u32.
    mtd impl writeU32(value: u32) => .serializer.writeNative(value)

    // Writes u64.
    mtd impl writeU64(value: u64) => .serializer.writeNative(value)

    // Writes f32.
    mtd impl writeF32(value: f32) => .serializer.writeNative(value)

    // Writes f64.
    mtd impl writeF64(value: f64) => .serializer.writeNative(value)

    // Writes string.
    mtd impl writeString(value: string?) => .serializer.writeNative(value)
}
