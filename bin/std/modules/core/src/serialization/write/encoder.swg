#global export
#global namespace Serialization
using Swag, Core.Errors

enum SectionKind
{
    Raw
    Unordered
    Ordered
}

interface IEncoder
{
    mtd isTextual()->bool;

    mtd start(result: *ConcatBuffer) throw;
    mtd end() throw;

    mtd beginField(val: Swag.TypeValue) throw;
    mtd endField(val: Swag.TypeValue) throw;
    mtd beginSection(kind: SectionKind) throw;
    mtd endSection() throw;

    mtd write(data: const [*] void, type: typeinfo) throw;
    mtd writeBufferU8(data: #null const [*] u8, count: u64) throw;

    mtd writeBool(value: bool);
    mtd writeS8(value: s8);
    mtd writeS16(value: s16);
    mtd writeS32(value: s32);
    mtd writeS64(value: s64);
    mtd writeU8(value: u8);
    mtd writeU16(value: u16);
    mtd writeU32(value: u32);
    mtd writeU64(value: u64);
    mtd writeF32(value: f32);
    mtd writeF64(value: f64);
    mtd writeString(value: #null string);
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
    serializer:         T
    errorIfUnknown:     bool     // If true, an error will be raised if a type cannot be saved. The field will be ignored if set to false
}

impl Encoder
{
    // Start serialization
    mtd start(result: *ConcatBuffer) throw
    {
        .serializer.startWrite(result)
        .serializer.beginRoot()
    }

    // End serialization
    mtd end() throw
    {
        .serializer.endRoot()
    }

    // Write a given Swag.TypeValue.
    mtd writeTypeValue(typeVal: TypeValue, data: #null const [*] void) throw
    {
        if !typeVal.pointedType do
            throw SerializationError{"missing type value pointed type"}
        if !data do
            throw SerializationError{"missing data for type value"}
        .serializer.beginElement(typeVal)
        .writeValue(data, typeVal.pointedType)
        .serializer.endElement(typeVal)
    }

    // Write a given value with a given type.
    mtd writeValue(data: const [*] void, dataType: #null typeinfo) throw
    {
        if !dataType do
            throw SerializationError{"missing data type"}
        var type = Reflection.makeConcreteAlias(dataType orelse #typeof(u8))
        type = Reflection.makeConcreteEnum(type)

        .serializer.beginValue()
        defer #noerr .serializer.endValue()

        // Native
        if type.kind == .Native
        {
            let typeNative = cast(#null const *TypeInfoNative) type
            switch typeNative.nativeKind
            {
            case Bool:
                .serializer.writeNative(dref cast(#null const *bool) data)
            case U8:
                .serializer.writeNative(dref cast(#null const *u8) data)
            case U16:
                .serializer.writeNative(dref cast(#null const *u16) data)
            case U32, Rune:
                .serializer.writeNative(dref cast(#null const *u32) data)
            case U64:
                .serializer.writeNative(dref cast(#null const *u64) data)
            case S8:
                .serializer.writeNative(dref cast(#null const *s8) data)
            case S16:
                .serializer.writeNative(dref cast(#null const *s16) data)
            case S32:
                .serializer.writeNative(dref cast(#null const *s32) data)
            case S64:
                .serializer.writeNative(dref cast(#null const *s64) data)
            case F32:
                .serializer.writeNative(dref cast(#null const *f32) data)
            case F64:
                .serializer.writeNative(dref cast(#null const *f64) data)
            }

            return
        }

        if Reflection.isType(type)
        {
            let typeType = dref cast(#null const **TypeInfo) data
            .serializer.writeNative(typeType ? typeType.crc : 0'u32)
            return
        }

        if Reflection.isInterface(type)
        {
            let itf = cast(#null const *Swag.Interface) data

            .serializer.beginSection(.Raw)
            defer #noerr .serializer.endSection()

            var objType, itfType: #null typeinfo
            if itf.itable
            {
                objType = dref cast(#null const *typeinfo) itf.itable
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
                    throw SerializationError{"missing interface object"}
                .writeTypeValue(typeVal, itf.obj)
            }

            return
        }

        if Reflection.isStruct(type)
        {
            if Reflection.isTuple(type)
            {
                if .errorIfUnknown do
                    throw UnsupportedFormatError{"cannot serialize an anonymous struct"}
                return
            }

            // Core.String
            if type == Core.String
            {
                let strBuf = cast(#null const *String) data
                .serializer.writeNative(strBuf.toString())
                return
            }

            // Core.Array
            let valueType = Reflection.getStructArrayType(type)
            if valueType
            {
                let safeValueType = valueType
                let ptrArr  = cast(#null const *Array'u8) data
                let treated = .serializer.beginSequence(type, data, ptrArr.count)
                defer .serializer.endSequence()

                if !treated
                {
                    var bufArr = cast(#null const [*] u8) ptrArr.buffer
                    for i in ptrArr.count
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
            let structType = cast(#null const *TypeInfoStruct) type
            let treated    = .serializer.beginStruct(structType, data)
            defer #noerr .serializer.endStruct()
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
                    throw SerializationError{"missing field pointed type"}
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
            let typeArr = cast(#null const *TypeInfoArray) type
            if !typeArr.pointedType do
                throw SerializationError{"missing array pointed type"}
            let elemType = typeArr.pointedType orelse #typeof(u8)
            let treated = .serializer.beginSequence(elemType, data, typeArr.count)
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
            throw UnsupportedFormatError{Errors.mkString(Format.toString("cannot serialize type [[%]]", type.name))}
    }

    // Write a full struct.
    // Will call [[Encoder.start]], [[Encoder.writeValue]] and [[Encoder.end]]
    mtd writeAll(result: *ConcatBuffer, value: any) throw
    {
        Debug.assert(Reflection.isStruct(@kindof(value)))
        start(me, result)
        .writeValue(@dataof(value), @kindof(value))
        end(me)
    }
}

impl IEncoder for Encoder
{
    mtd impl isTextual()->bool
    {
        return .serializer.isTextual()
    }

    // Start serialization
    mtd impl start(result: *ConcatBuffer) throw
    {
        .serializer.startWrite(result)
        .serializer.beginRoot()
    }

    // End serialization
    mtd impl end() throw
    {
        .serializer.endRoot()
    }

    mtd impl beginField(val: Swag.TypeValue) throw
    {
        .serializer.beginElement(val)
        .serializer.beginValue()
    }

    mtd impl endField(val: Swag.TypeValue) throw
    {
        .serializer.endValue()
        .serializer.endElement(val)
    }

    mtd impl beginSection(kind: SectionKind) throw
    {
        .serializer.beginSection(kind)
    }

    mtd impl endSection() throw
    {
        .serializer.endSection()
    }

    mtd impl write(data: const [*] void, type: typeinfo) throw
    {
        .writeValue(data, type)
    }

    mtd impl writeBufferU8(data: #null const [*] u8, count: u64) throw
    {
        if !data
        {
            if count do
                throw SerializationError{"cannot write a null u8 buffer"}
            return
        }
        let safeData = data
        let treated = .serializer.beginSequence(u8, safeData, count)
        defer #noerr .serializer.endSequence()

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

    mtd impl writeBool(value: bool)     => .serializer.writeNative(value)
    mtd impl writeS8(value: s8)         => .serializer.writeNative(value)
    mtd impl writeS16(value: s16)       => .serializer.writeNative(value)
    mtd impl writeS32(value: s32)       => .serializer.writeNative(value)
    mtd impl writeS64(value: s64)       => .serializer.writeNative(value)
    mtd impl writeU8(value: u8)         => .serializer.writeNative(value)
    mtd impl writeU16(value: u16)       => .serializer.writeNative(value)
    mtd impl writeU32(value: u32)       => .serializer.writeNative(value)
    mtd impl writeU64(value: u64)       => .serializer.writeNative(value)
    mtd impl writeF32(value: f32)       => .serializer.writeNative(value)
    mtd impl writeF64(value: f64)       => .serializer.writeNative(value)
    mtd impl writeString(value: #null string) => .serializer.writeNative(value)
}
