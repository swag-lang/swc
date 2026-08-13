#global export
#global namespace Serialization

using Swag, Core.Errors

// Defines the operations supported by i decoder.
interface IDecoder
{
    // Returns version.
    mtd version()->u32

    // Returns whether textual.
    mtd isTextual()->bool

    // Starts the operation.
    mtd start(input: const [..] u8) fail

    // Finishes the operation.
    mtd end() fail

    // Begins field.
    mtd beginField(val: Swag.TypeValue)->bool fail

    // Performs the end field operation.
    mtd endField(val: Swag.TypeValue) fail

    // Begins section.
    mtd beginSection(kind: SectionKind) fail

    // Performs the end section operation.
    mtd endSection() fail

    // Performs the read operation.
    mtd read(data: *void, dataType: typeinfo) fail

    // Reads buffer u8.
    mtd readBufferU8(count: u64)->#null *u8 fail

    // Reads bool.
    mtd readBool()->bool fail

    // Reads s8.
    mtd readS8()->s8 fail

    // Reads s16.
    mtd readS16()->s16 fail

    // Reads s32.
    mtd readS32()->s32 fail

    // Reads s64.
    mtd readS64()->s64 fail

    // Reads u8.
    mtd readU8()->u8 fail

    // Reads u16.
    mtd readU16()->u16 fail

    // Reads u32.
    mtd readU32()->u32 fail

    // Reads u64.
    mtd readU64()->u64 fail

    // Reads f32.
    mtd readF32()->f32 fail

    // Reads f64.
    mtd readF64()->f64 fail

    // Reads string.
    mtd readString()->String fail
}

// Selects decoder flags.
#[Swag.EnumFlags]
enum DecoderFlags
{
    None = 0                   // No optional decoding behavior.
    IgnoreStructFieldError     // Enables ignore struct field error.
}

/*
Serialization decoder.
This is a high level decoder that needs a specific implementation like [[Core.Serialization.Read.TagBin]] or [[Core.Serialization.Read.Json]].

```swag
var res = File.readAllBytes(file)
var decoder: Decoder'Read.TagBin
let myStruct = catch decoder.readAll'MyStruct(res.toSlice())
```
*/
struct(T) Decoder
{
    public
    {
        serializer: T                       // Serializer associated with this value.
        flags:      DecoderFlags = None     // Optional decoding behavior.
    }
}

impl Decoder
{
    mtd inferStructTypeForInterface(itfType: typeinfo, fieldCrcs: const [..] u32)->#null typeinfo
    {
        return Reflection.inferInterfaceImplementation(itfType, fieldCrcs)
    }

    mtd readTypeValue(typedVal: TypeValue, data: #null [*] void) fail
    {
        if !typedVal.pointedType do
            fail SerializationError{"missing type value pointed type"}
        if !data do
            fail SerializationError{"missing data for type value"}
        discard .serializer.beginElement(typedVal)
        .readTypedContent(data, typedVal.pointedType)
        .serializer.endElement(typedVal)
    }

    mtd readTypedContent(data: [*] void, dataType: #null typeinfo) fail
    {
        if !dataType do
            fail SerializationError{"missing data type"}
        var type = Reflection.resolveAliases(dataType orelse #typeof(u8))
        type = Reflection.enumUnderlyingType(type)

        .serializer.beginValue()
        defer #nofail .serializer.endValue()

        // Native
        if type.kind == .Native
        {
            let typeNative = cast(const *TypeInfoNative) type
            switch typeNative.nativeKind
            {
            case .Bool:       dref cast(*bool) data = .serializer.readNative'bool()
            case .U8:         dref cast(*u8) data = .serializer.readNative'u8()
            case .U16:        dref cast(*u16) data = .serializer.readNative'u16()
            case .U32, .Rune: dref cast(*u32) data = .serializer.readNative'u32()
            case .U64:        dref cast(*u64) data = .serializer.readNative'u64()
            case .S8:         dref cast(*s8) data = .serializer.readNative's8()
            case .S16:        dref cast(*s16) data = .serializer.readNative's16()
            case .S32:        dref cast(*s32) data = .serializer.readNative's32()
            case .S64:        dref cast(*s64) data = .serializer.readNative's64()
            case .F32:        dref cast(*f32) data = .serializer.readNative'f32()
            case .F64:        dref cast(*f64) data = .serializer.readNative'f64()
            }

            return
        }

        if Reflection.isType(type)
        {
            let crc      = .serializer.readNative'u32()
            let typeType = Reflection.typeFromCrc(crc)
            dref cast(*#null typeinfo) data = typeType
            return
        }

        if Reflection.isInterface(type)
        {
            let itf = cast(*Swag.Interface) data

            .serializer.beginSection(.Raw)
            defer #nofail .serializer.endSection()

            var objType, itfType: #null typeinfo
            var typeVal:          TypeValue
            typeVal.pointedType = #typeof(#null typeinfo)

            #static if T == Read.TagBin
            {
                let objCrc = .serializer.readNative'u32()
                if objCrc == 0 do
                    return
                objType = Reflection.typeFromCrc(objCrc)

                let itfCrc = .serializer.readNative'u32()
                itfType = Reflection.typeFromCrc(itfCrc) orelse type

                if !objType
                {
                    var fieldCrcs: Array'u32
                    if .serializer.peekStructFieldCrcs(&fieldCrcs) do
                        objType = .inferStructTypeForInterface(type, fieldCrcs.toSlice())
                }

                if !objType do
                    fail SerializationError{"unknown interface object type"}
            }
            else
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
                    fail SerializationError{"cannot allocate interface object"}
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
            let valueType = Reflection.dynamicArrayElementType(type)
            if valueType
            {
                let safeValueType = valueType
                var count         = 0'u64
                let treated       = .serializer.beginSequence(type, data, &count)
                defer #nofail .serializer.endSequence()

                if !treated
                {
                    Reflection.clearDynamicArray(data, safeValueType)
                    while .serializer.toNextSequenceElement(&count)
                    {
                        let bufArr = Reflection.appendDynamicArrayElement(data, safeValueType, initialize: false)
                        .readTypedContent(bufArr!, safeValueType)
                    }
                }

                return
            }

            // A structure with an implementation of ISerialize
            let idecoder = cast(IDecoder) dref me
            let itf      = @mkinterface(data, type, ISerialize)
            if itf != null
            {
                if itf.read(idecoder) do
                    return
            }

            // Generic struct load, driven by the shared per-type plan.
            let structType = cast(const *TypeInfoStruct) type
            let treated    = .serializer.beginStruct(structType, data)
            defer #nofail .serializer.endStruct()
            if treated do
                return

            let plan = planFor(structType)
            for &pf in plan.fields
            {
                let fieldType = pf.value.pointedType
                if !itf or !itf.readElement(pf.value, cast([*] u8) data + pf.value.offset, idecoder)
                {
                    let fieldData = cast([*] u8) data + pf.value.offset
                    let doIt      = catch .serializer.beginElement(pf.value) as beginErr

                    // A failed 'beginElement' has already unwound itself, so there is
                    // no element left open to close. Only pair the two once it returned.
                    if beginErr != null
                    {
                        if !(.flags & .IgnoreStructFieldError) do
                            fail beginErr
                        #static if T == Read.TagBin do
                            .serializer.diag.fieldErrors += 1
                        continue
                    }

                    defer #nofail .serializer.endElement(pf.value)
                    if !doIt do
                        continue

                    catch .readTypedContent(fieldData, fieldType) as readErr
                    if readErr != null and (.flags & .IgnoreStructFieldError)
                    {
                        #static if T == Read.TagBin do
                            .serializer.diag.fieldErrors += 1
                        Reflection.reset(fieldData, fieldType)
                        continue
                    }

                    if readErr != null and !(.flags & .IgnoreStructFieldError) do
                        fail readErr
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
                fail SerializationError{"missing array pointed type"}
            let elemType = typeArr.pointedType orelse #typeof(u8)
            var count    = typeArr.count
            let treated  = .serializer.beginSequence(elemType, data, &count)
            defer #nofail .serializer.endSequence()
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
    mtd start(input: const [..] u8) fail
    {
        .serializer.startRead(input)
        .serializer.beginRoot()
    }

    // Finish reading
    mtd end() fail
    {
        .serializer.endRoot()

        // Payload corruption is detected inside no-fail cleanup paths, so it surfaces
        // here: a strict decode refuses the result, a tolerant one keeps it and reports
        // through the diagnostics.
        #static if T == Read.TagBin
        {
            if .serializer.diag.corruptPayloads and !(.flags & .IgnoreStructFieldError) do
                fail SerializationError{"stream carried corrupt payloads"}
        }
    }

    // Read a full struct
    mtd(TR) readAll(input: const [..] u8)->#null *TR fail
    {
        Debug.assert(Reflection.isStruct(TR))

        .start(input)

        let val = Memory.new'TR()
        defer #fail Memory.delete(val)

        .readTypedContent(val, TR)

        .end()
        return val
    }
}

impl IDecoder for Decoder
{
    // Starts the operation.
    mtd impl start(input: const [..] u8) fail
    {
        .serializer.startRead(input)
        .serializer.beginRoot()
    }

    // Finishes the operation.
    mtd impl end() fail
    {
        .serializer.endRoot()
    }

    // Begins field.
    mtd impl beginField(val: Swag.TypeValue)->bool fail
    {
        if !.serializer.beginElement(val) do
            return false
        .serializer.beginValue()
        return true
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

    // Returns version.
    mtd impl version()->u32
    {
        return .serializer.version()
    }

    // Returns whether textual.
    mtd impl isTextual()->bool
    {
        return .serializer.isTextual()
    }

    // Performs the read operation.
    mtd impl read(data: *void, dataType: typeinfo) fail
    {
        .readTypedContent(data, dataType)
    }

    // Reads buffer u8.
    mtd impl readBufferU8(count: u64)->#null *u8 fail
    {
        if !count do
            return null

        let safeData = cast([*] u8) Memory.alloc(count)

        var cpt     = count
        let treated = .serializer.beginSequence(u8, safeData, &cpt)
        defer #nofail .serializer.endSequence()

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

    // Reads bool.
    mtd impl readBool()->bool fail => .serializer.readNative'bool()

    // Reads s8.
    mtd impl readS8()->s8 fail => .serializer.readNative's8()

    // Reads s16.
    mtd impl readS16()->s16 fail => .serializer.readNative's16()

    // Reads s32.
    mtd impl readS32()->s32 fail => .serializer.readNative's32()

    // Reads s64.
    mtd impl readS64()->s64 fail => .serializer.readNative's64()

    // Reads u8.
    mtd impl readU8()->u8 fail => .serializer.readNative'u8()

    // Reads u16.
    mtd impl readU16()->u16 fail => .serializer.readNative'u16()

    // Reads u32.
    mtd impl readU32()->u32 fail => .serializer.readNative'u32()

    // Reads u64.
    mtd impl readU64()->u64 fail => .serializer.readNative'u64()

    // Reads f32.
    mtd impl readF32()->f32 fail => .serializer.readNative'f32()

    // Reads f64.
    mtd impl readF64()->f64 fail => .serializer.readNative'f64()

    // Reads string.
    mtd impl readString()->String fail => .serializer.readNative'String()
}
