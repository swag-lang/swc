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
    mtd writeBufferU8(data: #null const [*] u8, count: u64) fail

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
    mtd writeString(value: #null string)
}

/*
Serialization encoder.
This is a high level encoder that needs a specific implementation like [[Core.Serialization.Write.TagBin]] or [[Core.Serialization.Write.JSon]].

```swag
var buf:     ConcatBuffer
var encoder: Encoder'Write.TagBin
encoder.writeAll(&buf, myStruct)
File.writeAllBytes(file, buf)
```

Can be serialized:
* All simple types: `bool/u8/u16/u32/u64/s8/s16/s32/s64/rune/f32/f64`
* A type value 'typeinfo', which will be saved as a CRC.
* An interface. Will be stored as a type and a typed value.
* A struct.
* A `Core.String`.
* A `Core.Array` of valid values.
* A static array of valid values.

> NOTE:
> Type 'string' is not supported. Consider using [[Core.String]] instead.

A struct can implement the 'ISerialize' interface in order to have a specific serialization. If not defined, then the struct will be saved field by field.
*/
struct(T) Encoder
{
    serializer:     T        // Serializer associated with this value.
    errorIfUnknown: bool     // If true, an error will be raised if a type cannot be saved. The field will be ignored if set to false
}

impl Encoder
{
    // Start serialization
    mtd start(result: *ConcatBuffer) fail
    {
        .serializer.startWrite(result)
        .serializer.beginRoot()
    }

    // End serialization
    mtd end() fail
    {
        .serializer.endRoot()
    }

    // Write a given Swag.TypeValue.
    mtd writeTypeValue(typeVal: TypeValue, data: #null const [*] void) fail
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
    mtd writeValue(data: const [*] void, dataType: #null typeinfo) fail
    {
        if !dataType do
            fail SerializationError{"missing data type"}
        var type = Reflection.makeConcreteAlias(dataType orelse #typeof(u8))
        type = Reflection.makeConcreteEnum(type)

        .serializer.beginValue()
        defer #nofail .serializer.endValue()

        // Native
        if type.kind == .Native
        {
            let typeNative = cast(const *TypeInfoNative) type
            switch typeNative.nativeKind
            {
            case .Bool:       .serializer.writeNative(dref cast(const *bool) data)
            case .U8:         .serializer.writeNative(dref cast(const *u8) data)
            case .U16:        .serializer.writeNative(dref cast(const *u16) data)
            case .U32, .Rune: .serializer.writeNative(dref cast(const *u32) data)
            case .U64:        .serializer.writeNative(dref cast(const *u64) data)
            case .S8:         .serializer.writeNative(dref cast(const *s8) data)
            case .S16:        .serializer.writeNative(dref cast(const *s16) data)
            case .S32:        .serializer.writeNative(dref cast(const *s32) data)
            case .S64:        .serializer.writeNative(dref cast(const *s64) data)
            case .F32:        .serializer.writeNative(dref cast(const *f32) data)
            case .F64:        .serializer.writeNative(dref cast(const *f64) data)
            }

            return
        }

        if Reflection.isType(type)
        {
            let typeType = dref notnull cast(#null const **TypeInfo) data
            .serializer.writeNative(typeType ? typeType.crc : 0'u32)
            return
        }

        if Reflection.isInterface(type)
        {
            let itf = cast(const *Swag.Interface) data

            .serializer.beginSection(.Raw)
            defer #nofail .serializer.endSection()

            var objType, itfType: #null typeinfo
            if itf.itable
            {
                objType = dref notnull cast(#null const *typeinfo) itf.itable
                itfType = type
            }

            var typeVal: TypeValue
            typeVal.pointedType = #typeof(#null typeinfo)
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
            let valueType = Reflection.getStructArrayType(type)
            if valueType
            {
                let safeValueType = valueType
                let ptrArr        = cast(const *Array'u8) data
                let treated       = .serializer.beginSequence(type, data, ptrArr.count)
                defer .serializer.endSequence()

                if !treated
                {
                    var bufArr = cast(#null const [*] u8) ptrArr.buffer
                    for [i] in ptrArr.count
                    {
                        .writeValue(notnull bufArr, safeValueType)
                        bufArr += safeValueType.sizeof
                    }
                }

                return
            }

            // A structure with an implementation of ISerialize
            let itf = @mkinterface(data, type, ISerialize)
            if itf != null
            {
                if itf.write(cast(IEncoder) dref &me) do
                    return
            }

            // Start a fields section
            let structType = cast(const *TypeInfoStruct) type
            let treated    = .serializer.beginStruct(structType, data)
            defer #nofail .serializer.endStruct()
            if treated do
                return

            // Generic structure save
            for field in structType.fields
            {
                if Reflection.hasAttribute(field, NoSerialize) do
                    continue
                if Reflection.hasAttribute(field.pointedType, NoSerialize) do
                    continue
                if !field.pointedType do
                    fail SerializationError{"missing field pointed type"}
                let fieldType = field.pointedType

                if !itf or !itf.writeElement(field, cast(#null const [*] u8) data + field.offset, cast(IEncoder) dref &me)
                {
                    .writeTypeValue(field, cast(#null const [*] u8) data + field.offset)
                }
            }

            return
        }

        // A static array
        if Reflection.isStaticArray(type)
        {
            let typeArr = cast(const *TypeInfoArray) type
            if !typeArr.pointedType do
                fail SerializationError{"missing array pointed type"}
            let elemType = typeArr.pointedType orelse #typeof(u8)
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
        Debug.assert(Reflection.isStruct(@kindof(value)))
        start(me, result)
        .writeValue(@dataof(value), @kindof(value))
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
    mtd impl writeBufferU8(data: #null const [*] u8, count: u64) fail
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
                .serializer.writeNative(dref ptr)
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
    mtd impl writeString(value: #null string) => .serializer.writeNative(value)
}
