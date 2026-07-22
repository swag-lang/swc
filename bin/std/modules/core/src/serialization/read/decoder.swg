#global export
#global namespace Serialization
using Swag, Core.Errors

interface IDecoder
{
    mtd getVersion()->u32;
    mtd isTextual()->bool;

    mtd start(input: const [..] u8) throw;
    mtd end() throw;

    mtd beginField(val: Swag.TypeValue)->bool throw;
    mtd endField(val: Swag.TypeValue) throw;
    mtd beginSection(kind: SectionKind) throw;
    mtd endSection() throw;

    mtd read(data: *void, dataType: typeinfo) throw;
    mtd readBufferU8(count: u64)->#null *u8 throw;

    mtd readBool()->bool throw;
    mtd readS8()->s8 throw;
    mtd readS16()->s16 throw;
    mtd readS32()->s32 throw;
    mtd readS64()->s64 throw;
    mtd readU8()->u8 throw;
    mtd readU16()->u16 throw;
    mtd readU32()->u32 throw;
    mtd readU64()->u64 throw;
    mtd readF32()->f32 throw;
    mtd readF64()->f64 throw;
    mtd readString()->String throw;
}

#[Swag.EnumFlags]
enum DecoderFlags
{
    Zero
    IgnoreStructFieldError
}

/*
Serialization decoder.
This is a high level decoder that needs a specific implementation like [[Core.Serialization.Read.TagBin]] or [[Core.Serialization.Read.JSon]].

```swag
var res = File.readAllBytes(file)
var decoder: Decoder'Read.TagBin
let myStruct = catch decoder.readAll'MyStruct(res.toSlice())
```
*/
struct(T) Decoder
{
    serializer:     T
    flags:          DecoderFlags = Zero
}

impl Decoder
{
    mtd inferStructTypeForInterface(itfType: typeinfo, fieldCrcs: const [..] u32)->#null typeinfo
    {
        return Reflection.inferTypeWithInterfaceFields(itfType, fieldCrcs)
    }

    mtd readTypeValue(typedVal: TypeValue, data: #null [*] void) throw
    {
        if !typedVal.pointedType do
            throw SerializationError{"missing type value pointed type"}
        if !data do
            throw SerializationError{"missing data for type value"}
        discard .serializer.beginElement(typedVal)
        .readTypedContent(data, typedVal.pointedType)
        .serializer.endElement(typedVal)
    }

    mtd readTypedContent(data: [*] void, dataType: #null typeinfo) throw
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
            let typeNative = cast(const *TypeInfoNative) type
            switch typeNative.nativeKind
            {
            case Bool:
                dref cast(*bool) data = .serializer.readNative'bool()
            case U8:
                dref cast(*u8) data = .serializer.readNative'u8()
            case U16:
                dref cast(*u16) data = .serializer.readNative'u16()
            case U32, Rune:
                dref cast(*u32) data = .serializer.readNative'u32()
            case U64:
                dref cast(*u64) data = .serializer.readNative'u64()
            case S8:
                dref cast(*s8) data = .serializer.readNative's8()
            case S16:
                dref cast(*s16) data = .serializer.readNative's16()
            case S32:
                dref cast(*s32) data = .serializer.readNative's32()
            case S64:
                dref cast(*s64) data = .serializer.readNative's64()
            case F32:
                dref cast(*f32) data = .serializer.readNative'f32()
            case F64:
                dref cast(*f64) data = .serializer.readNative'f64()
            }

            return
        }

        if Reflection.isType(type)
        {
            let crc      = .serializer.readNative'u32()
            let typeType = Reflection.crcToType(crc)
            dref cast(*#null typeinfo) data = typeType
            return
        }

        if Reflection.isInterface(type)
        {
            let itf = cast(*Swag.Interface) data

            .serializer.beginSection(.Raw)
            defer #noerr .serializer.endSection()

            var objType, itfType: #null typeinfo
            var typeVal: TypeValue
            typeVal.pointedType = #typeof(#null typeinfo)

            #if T == Read.TagBin
            {
                let objCrc = .serializer.readNative'u32()
                if objCrc == 0 do
                    return
                objType = Reflection.crcToType(objCrc)

                let itfCrc = .serializer.readNative'u32()
                itfType = Reflection.crcToType(itfCrc) orelse type

                if !objType
                {
                    var fieldCrcs: Array'u32
                    if .serializer.peekStructFieldCrcs(&fieldCrcs) do
                        objType = .inferStructTypeForInterface(type, fieldCrcs.toSlice())
                }

                if !objType do
                    throw SerializationError{"unknown interface object type"}
            }
            #else
            {
                .readTypeValue(typeVal, &objType)
                if objType do
                    .readTypeValue(typeVal, &itfType)
            }

            if objType
            {
                itf.itable = @tableof(cast(#null const *Swag.TypeInfoStruct) objType, cast(#null const *Swag.TypeInfoStruct) itfType)

                typeVal.pointedType = objType
                itf.obj             = Memory.new(objType)
                if !itf.obj do
                    throw SerializationError{"cannot allocate interface object"}
                .readTypeValue(typeVal, itf.obj)
            }

            return
        }

        if Reflection.isStruct(type)
        {
            // Core.String
            if type == String
            {
                let strBuf = cast(*String) data
                dref strBuf = #nodrop .serializer.readNative'String()
                strBuf.opPostMove()
                return
            }

            // Core.Array
            let valueType = Reflection.getStructArrayType(type)
            if valueType
            {
                let safeValueType = valueType
                var count   = 0'u64
                let treated = .serializer.beginSequence(type, data, &count)
                defer #noerr .serializer.endSequence()

                if !treated
                {
                    Reflection.clearStructArray(data, safeValueType)
                    while .serializer.toNextSequenceElement(&count)
                    {
                        let bufArr = Reflection.appendValueStructArray(data, safeValueType, defaultInitSlot: false)
                        .readTypedContent(notnull bufArr, safeValueType)
                    }
                }

                return
            }

            // A structure with an implementation of ISerialize
            let idecoder = cast(IDecoder) dref &me
            let itf      = @mkinterface(data, type, ISerialize)
            if itf != null
            {
                if itf.read(idecoder) do
                    return
            }

            // Generic struct load
            let structType = cast(const *TypeInfoStruct) type
            let treated    = .serializer.beginStruct(structType, data)
            defer #noerr .serializer.endStruct()
            if treated do
                return

            for field in structType.fields
            {
                if Reflection.hasAttribute(field, NoSerialize) or Reflection.hasAttribute(field.pointedType, NoSerialize) do
                    continue
                if !field.pointedType do
                    throw SerializationError{"missing field pointed type"}
                let fieldType = field.pointedType

                if !itf or !itf.readElement(field, cast([*] u8) data + field.offset, idecoder)
                {
                    let fieldData = cast([*] u8) data + field.offset
                    let doIt = catch .serializer.beginElement(field)
                    defer #noerr .serializer.endElement(field)

                    if @err != null and !(.flags & .IgnoreStructFieldError) do
                        throw @err
                    if !doIt do
                        continue

                    catch .readTypedContent(fieldData, fieldType)
                    if @err != null and (.flags & .IgnoreStructFieldError)
                    {
                        Reflection.reset(fieldData, fieldType)
                        continue
                    }
                    if @err != null and !(.flags & .IgnoreStructFieldError) do
                        throw @err
                }
            }

            // Inform user code we are done
            if itf do
                itf.postRead(data, idecoder)

            return
        }

        // Static array
        if Reflection.isStaticArray(type)
        {
            let typeArr = cast(const *TypeInfoArray) type
            if !typeArr.pointedType do
                throw SerializationError{"missing array pointed type"}
            let elemType = typeArr.pointedType orelse #typeof(u8)
            var count   = typeArr.count
            let treated = .serializer.beginSequence(elemType, data, &count)
            defer #noerr .serializer.endSequence()
            if treated do
                return

            var bufArr = cast([*] u8) data
            for count
            {
                .readTypedContent(bufArr, elemType)
                bufArr += elemType.sizeof
            }

            return
        }
    }

    // Start reading
    mtd start(input: const [..] u8) throw
    {
        .serializer.startRead(input)
        .serializer.beginRoot()
    }

    // Finish reading
    mtd end() throw
    {
        .serializer.endRoot()
    }

    // Read a full struct
    mtd(TR) readAll(input: const [..] u8)->#null *TR throw
    {
        Debug.assert(Reflection.isStruct(TR))

        .start(input)

        let val = Memory.new'TR()
        defer #err Memory.delete(val)

        .readTypedContent(val, TR)

        .end()
        return val
    }
}

impl IDecoder for Decoder
{
    mtd impl start(input: const [..] u8) throw
    {
        .serializer.startRead(input)
        .serializer.beginRoot()
    }

    mtd impl end() throw
    {
        .serializer.endRoot()
    }

    mtd impl beginField(val: Swag.TypeValue)->bool throw
    {
        if !.serializer.beginElement(val) do
            return false
        .serializer.beginValue()
        return true
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

    mtd impl getVersion()->u32
    {
        return .serializer.getVersion()
    }

    mtd impl isTextual()->bool
    {
        return .serializer.isTextual()
    }

    mtd impl read(data: *void, dataType: typeinfo) throw
    {
        .readTypedContent(data, dataType)
    }

    mtd impl readBufferU8(count: u64)->#null *u8 throw
    {
        if !count do
            return null

        let safeData = cast([*] u8) Memory.alloc(count)

        var cpt     = count
        let treated = .serializer.beginSequence(u8, safeData, &cpt)
        defer #noerr .serializer.endSequence()

        if !treated
        {
            var ptr = safeData
            for Math.min(cpt, count)
            {
                .serializer.beginValue()
                dref ptr = .serializer.readNative'u8()
                .serializer.endValue()
                ptr += 1
            }
        }

        return safeData
    }

    mtd impl readBool()->bool throw     => .serializer.readNative'bool()
    mtd impl readS8()->s8 throw         => .serializer.readNative's8()
    mtd impl readS16()->s16 throw       => .serializer.readNative's16()
    mtd impl readS32()->s32 throw       => .serializer.readNative's32()
    mtd impl readS64()->s64 throw       => .serializer.readNative's64()
    mtd impl readU8()->u8 throw         => .serializer.readNative'u8()
    mtd impl readU16()->u16 throw       => .serializer.readNative'u16()
    mtd impl readU32()->u32 throw       => .serializer.readNative'u32()
    mtd impl readU64()->u64 throw       => .serializer.readNative'u64()
    mtd impl readF32()->f32 throw       => .serializer.readNative'f32()
    mtd impl readF64()->f64 throw       => .serializer.readNative'f64()
    mtd impl readString()->String throw => .serializer.readNative'String()
}
