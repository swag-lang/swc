#global #if #command == Swag.CompilerCommand.Test
#global fileprivate
using Swag

#[Serialization.Final]
struct TagBinFinalPoint
{
    x: s16
    y: s16
}

struct TagBinPair
{
    x: s32
    y: s32
}

struct TagBinFieldWisePoint
{
    x: s16
    y: s16
}

#[Serialization.Final]
struct TagBinFinalMigrationPoint
{
    x: s16
    y: s16
}

struct TagBinPayload
{
    id:         u32
    active:     bool
    name:       String
    counts:     Array's32
    pair:       TagBinPair
    fixed:      [3] u8
    finalPoint: TagBinFinalPoint

    #[Serialization.Compress]
    blob:       Array'u8

    #[Serialization.NoSerialize]
    transient:  s32
}

#[Serialization.Version(1)]
struct TagBinLegacyPayload
{
    removed:    s32
    value:      s32
    legacyName: s32
    numbers:    [3] u8
    single:     s32
}

#[Serialization.Version(2)]
struct TagBinCurrentPayload
{
    single: s32

    #[Serialization.Alias("legacyName")]
    renamed: s32

    value:   s32
    numbers: [3] u8
}

#[Serialization.Version(3)]
struct TagBinFuturePayload
{
    value: s32
}

#[Serialization.Version(2)]
struct TagBinOlderPayload
{
    value: s32
}

struct TagBinLegacyNested
{
    left:  s16
    right: s16
}

#[Serialization.Alias("TagBinLegacyNested")]
struct TagBinCurrentNested
{
    left:  s32
    right: s32
}

struct TagBinConversionSource
{
    small:          s16
    floating:       f32
    staticToStatic: [3] u8
    staticToArray:  [3] s16
    arrayToStatic:  Array's8
    singleToStatic: s16
    singleToArray:  u8
    arrayToSingle:  Array's16
    nested:         TagBinLegacyNested
}

struct TagBinConversionTarget
{
    small:          s64
    floating:       f64
    staticToStatic: [5] u16
    staticToArray:  Array's32
    arrayToStatic:  [4] s32
    singleToStatic: [3] s32
    singleToArray:  Array'u32
    arrayToSingle:  s64
    nested:         TagBinCurrentNested
}

struct TagBinTypeInfoPayload
{
    primitive:   typeinfo
    staticArray: typeinfo
    payload:     typeinfo
}

public interface ITagBinScore
{
    mtd score()->s32;
    mtd labelText()->string;
}

public struct TagBinInterfaceProbe
{
    value: s32
    label: String
}

public impl ITagBinScore for TagBinInterfaceProbe
{
    mtd impl score()->s32 => .value + 5
    mtd impl labelText()->string => .label.toString()
}

struct TagBinInterfacePayload
{
    score: ITagBinScore
    other: s32
}

public struct TagBinHookPayload
{
    direct:       s32
    remapped:     s32
    bytes:        Array'u8

    #[Serialization.NoSerialize]
    postReadSeen: bool
}

public impl Serialization.ISerialize for TagBinHookPayload
{
    mtd impl read(_decoder: Serialization.IDecoder)->bool throw => false
    mtd impl write(_encoder: Serialization.IEncoder)->bool throw => false

    mtd impl readElement(type: TypeValue, data: *void, decoder: Serialization.IDecoder)->bool throw
    {
        if type.name == "remapped"
        {
            if !decoder.beginField(type) do
                return true
            defer #noerr decoder.endField(type)

            dref cast(*s32) data = decoder.readS32() - 6
            return true
        }

        if type.name == "bytes"
        {
            if !decoder.beginField(type) do
                return true
            defer #noerr decoder.endField(type)

            let raw = decoder.readBufferU8(4)
            defer Memory.free(raw, 4)

            let values = cast(*Array'u8) data
            let rawPtr = cast([*] u8) raw
            values.clear()
            for i in 4 do
                values.add(rawPtr[3 - i])
            return true
        }

        return false
    }

    mtd impl writeElement(type: TypeValue, data: const *void, encoder: Serialization.IEncoder)->bool throw
    {
        if type.name == "remapped"
        {
            encoder.beginField(type)
            defer #noerr encoder.endField(type)

            encoder.writeS32(dref cast(const *s32) data + 10)
            return true
        }

        if type.name == "bytes"
        {
            encoder.beginField(type)
            defer #noerr encoder.endField(type)

            let values = cast(const *Array'u8) data
            encoder.writeBufferU8(values.buffer, values.count)
            return true
        }

        return false
    }

    mtd impl postRead(data: *void, _decoder: Serialization.IDecoder) throw
    {
        let value = cast(*TagBinHookPayload) data
        value.postReadSeen = true
        value.direct += 1
    }
}

func makeTagBinPayload()->TagBinPayload
{
    var result: retval

    let seed: [4] s32 = [-8, 0, 7, 42]
    result.id         = 17
    result.active     = true
    result.name       = "tagbin"
    result.counts.add(seed)
    result.pair       = TagBinPair{x: -3, y: 11}
    result.fixed      = [9, 8, 7]
    result.finalPoint = TagBinFinalPoint{x: -2, y: 5}
    result.transient  = 123

    for i in 512
    {
        result.blob.add(cast(u8) (i % 4))
    }

    return result
}

func(T) encodeTagBin(value: T)->String
{
    var encoder: Serialization.Encoder'Serialization.Write.TagBin
    var buffer:  ConcatBuffer

    catch encoder.writeAll(&buffer, value)
    @assert(@err == null)
    return buffer.toString()
}

func findTagBinFieldSeek(bytes: const [..] u8, fieldName: string)->u64
{
    var stream = ByteStream.openRead(bytes)
    @assert(catch stream.readNative'u32() == Serialization.Write.TagBinSignatures.Root)
    @assert(@err == null)
    discard catch stream.readNative'u32()
    @assert(@err == null)
    @assert(catch stream.readNative'u32() == Serialization.Write.TagBinSignatures.Version)
    @assert(@err == null)
    discard catch stream.readNative'u32()
    @assert(@err == null)
    @assert(catch stream.readNative'u32() == Serialization.Write.TagBinSignatures.Fat)
    @assert(@err == null)

    let fatSeek  = catch stream.readNative'u64()
    let fatCount = catch stream.readNative'u64()
    @assert(@err == null)

    stream.setSeek(fatSeek)
    @assert(catch stream.readNative'u32() == Serialization.Write.TagBinSignatures.Fat)
    @assert(@err == null)

    let fieldCrc = Hash.Crc32.compute(fieldName)
    for fatCount
    {
        let crc  = catch stream.readNative'u32()
        let seek = catch stream.readNative'u64()
        @assert(@err == null)
        if crc == fieldCrc do
            return seek
    }

    @assert(false)
    return 0
}

func corruptTagBinFieldType(bytes: String, fieldName: string, typeCrc: u32)->Array'u8
{
    var result: retval
    result.add(bytes.toSlice())

    let seek = findTagBinFieldSeek(result.toSlice(), fieldName)
    var writer = ByteStream.openWrite(&result)
    writer.setSeek(seek + #sizeof(u32))
    writer.writeNative(typeCrc)
    return result
}

func corruptTagBinInterfaceObjectType(bytes: String, fieldName: string, typeCrc: u32)->Array'u8
{
    var result: retval
    result.add(bytes.toSlice())

    let seek = findTagBinFieldSeek(result.toSlice(), fieldName)
    var writer = ByteStream.openWrite(&result)
    writer.setSeek(seek + #sizeof(u32) + #sizeof(u32) + #sizeof(Serialization.Write.TagBinValueFlags))
    writer.writeNative(typeCrc)
    return result
}

func assertS32Array(values: const &Array's32, expected: const [..] s32)->bool
{
    if values.count != @countof(expected) do
        return false

    for values.count
    {
        if values[@index] != expected[@index] do
            return false
    }

    return true
}

func assertCompressedBlob(values: const &Array'u8)->bool
{
    if values.count != 512 do
        return false

    for values.count
    {
        if values[@index] != cast(u8) (@index % 4) do
            return false
    }

    return true
}

func assertU32Array(values: const &Array'u32, expected: const [..] u32)->bool
{
    if values.count != @countof(expected) do
        return false

    for values.count
    {
        if values[@index] != expected[@index] do
            return false
    }

    return true
}

func releaseTagBinInterface(value: *ITagBinScore)
{
    let runtime = cast(*Swag.Interface) value
    if runtime.obj
    {
        Memory.delete(runtime.obj, #typeof(TagBinInterfaceProbe))
        runtime.obj    = null
        runtime.itable = null
    }
}

#test
{
    var writer: Serialization.Write.TagBin
    var reader: Serialization.Read.TagBin
    let (raw, sizeof) = Serialization.isPodFinal(#typeof(TagBinFinalPoint))

    @assert(!writer.isTextual())
    @assert(!reader.isTextual())
    @assert(raw)
    @assert(sizeof == #sizeof(TagBinFinalPoint))
    @assert(Reflection.hasAttribute(#typeof(TagBinFinalPoint), Serialization.Final))
    @assert(!Reflection.hasAttribute(#typeof(TagBinFinalPoint), Serialization.NoSerialize))

    let blobField = Reflection.getField(#typeof(TagBinPayload), "blob")
    @assert(blobField != null)
    @assert(Reflection.hasAttribute(blobField, Serialization.Compress))
    @assert(!Reflection.hasAttribute(blobField, Serialization.NoSerialize))
}

#test
{
    let oldPoint = TagBinFieldWisePoint{x: -9, y: 12}
    let oldBytes = encodeTagBin(oldPoint)

    var finalDecoder: Serialization.Decoder'Serialization.Read.TagBin
    let finalPoint = catch finalDecoder.readAll'TagBinFinalMigrationPoint(oldBytes.toSlice())
    @assert(@err == null)
    @assert(finalPoint != null)
    @assert(finalPoint.x == -9)
    @assert(finalPoint.y == 12)

    let rawBytes = encodeTagBin(TagBinFinalMigrationPoint{x: 3, y: 4})

    var fieldWiseDecoder: Serialization.Decoder'Serialization.Read.TagBin
    let fieldWisePoint = catch fieldWiseDecoder.readAll'TagBinFieldWisePoint(rawBytes.toSlice())
    @assert(fieldWisePoint == null)
    @assert(@err != null)

    Memory.delete(finalPoint)
}

#test
{
    let payload = makeTagBinPayload()
    @assert(payload.finalPoint.x == -2)
    @assert(payload.finalPoint.y == 5)

    var encoder: Serialization.Encoder'Serialization.Write.TagBin
    var buffer:  ConcatBuffer
    catch encoder.writeAll(&buffer, payload)
    @assert(@err == null)
    let bytes = buffer.toString()
    let byteSlice = bytes.toSlice()

    var decoder: Serialization.Decoder'Serialization.Read.TagBin
    let decoded = catch decoder.readAll'TagBinPayload(byteSlice)
    @assert(@err == null)
    @assert(decoded != null)
    @assert(decoded.id == 17)
    @assert(decoded.active)
    @assert(decoded.name == "tagbin")
    decoded.name = "decoded"
    @assert(decoded.name == "decoded")
    @assert(assertS32Array(decoded.counts, [-8, 0, 7, 42]))
    @assert(decoded.pair.x == -3)
    @assert(decoded.pair.y == 11)
    @assert(decoded.fixed[0] == 9)
    @assert(decoded.fixed[1] == 8)
    @assert(decoded.fixed[2] == 7)
    @assert(decoded.finalPoint.x == -2)
    @assert(decoded.finalPoint.y == 5)
    @assert(assertCompressedBlob(decoded.blob))
    @assert(decoded.transient == 0)

    Memory.delete(decoded)
}

#test
{
    let payload = makeTagBinPayload()
    let bytes   = encodeTagBin(payload)
    let patched = corruptTagBinFieldType(bytes, "id", 0xDEADBEEF)

    var decoder: Serialization.Decoder'Serialization.Read.TagBin
    let decoded = catch decoder.readAll'TagBinPayload(patched.toSlice())
    @assert(@err == null)
    @assert(decoded != null)
    @assert(decoded.id == 17)
    @assert(decoded.name == "tagbin")

    Memory.delete(decoded)
}

#test
{
    let payload = makeTagBinPayload()
    let bytes   = encodeTagBin(payload)

    var decoder: Serialization.Decoder'Serialization.Read.TagBin
    decoder.serializer.ignoreElements.add("name")
    let decoded = catch decoder.readAll'TagBinPayload(bytes.toSlice())
    @assert(@err == null)
    @assert(decoded != null)

    @assert(decoded.id == 17)
    @assert(decoded.name.isNullOrEmpty())
    @assert(assertCompressedBlob(decoded.blob))

    Memory.delete(decoded)
}

#test
{
    let legacy = TagBinLegacyPayload{
        removed:    100,
        value:      21,
        legacyName: -6,
        numbers:    [4, 5, 6],
        single:     33,
    }
    let bytes = encodeTagBin(legacy)

    var decoder: Serialization.Decoder'Serialization.Read.TagBin
    let decoded = catch decoder.readAll'TagBinCurrentPayload(bytes.toSlice())
    @assert(@err == null)
    @assert(decoded != null)

    @assert(decoded.renamed == -6)
    @assert(decoded.value == 21)
    @assert(decoded.numbers[0] == 4)
    @assert(decoded.numbers[1] == 5)
    @assert(decoded.numbers[2] == 6)
    @assert(decoded.single == 33)

    Memory.delete(decoded)
}

#test
{
    let future = TagBinFuturePayload{value: 44}
    let bytes  = encodeTagBin(future)

    var strictDecoder: Serialization.Decoder'Serialization.Read.TagBin
    let strictValue = catch strictDecoder.readAll'TagBinOlderPayload(bytes.toSlice())
    @assert(strictValue == null)
    @assert(@err != null)

    var forwardDecoder: Serialization.Decoder'Serialization.Read.TagBin
    forwardDecoder.serializer.options.tryForward = true
    let forwardValue = catch forwardDecoder.readAll'TagBinOlderPayload(bytes.toSlice())
    @assert(@err == null)
    @assert(forwardValue != null)
    @assert(forwardValue.value == 44)

    Memory.delete(forwardValue)
}

#test
{
    Reflection.registerType(#typeof(TagBinPayload))
    Reflection.registerType(#typeof(#type [3] u8))

    let payload = TagBinTypeInfoPayload{
        primitive:   #typeof(s32),
        staticArray: #typeof(#type [3] u8),
        payload:     #typeof(TagBinPayload),
    }
    let bytes = encodeTagBin(payload)

    var decoder: Serialization.Decoder'Serialization.Read.TagBin
    let decoded = catch decoder.readAll'TagBinTypeInfoPayload(bytes.toSlice())
    @assert(@err == null)
    @assert(decoded != null)
    @assert(decoded.primitive == s32)
    @assert(decoded.staticArray == #typeof(#type [3] u8))
    @assert(decoded.payload == TagBinPayload)

    Memory.delete(decoded)
}

#test
{
    var concrete = TagBinInterfaceProbe{value: 32}
    concrete.label = "iface"

    let payload = TagBinInterfacePayload{
        score: cast(ITagBinScore) concrete,
        other: -11,
    }

    Reflection.registerType(#typeof(TagBinInterfaceProbe))
    Reflection.registerType(#typeof(TagBinInterfacePayload))
    @assert(Reflection.hasInterface(#typeof(TagBinInterfaceProbe), ITagBinScore))
    @assert(payload.score.score() == 37)

    let bytes = encodeTagBin(payload)

    var decoder: Serialization.Decoder'Serialization.Read.TagBin
    let decoded = catch decoder.readAll'TagBinInterfacePayload(bytes.toSlice())
    @assert(@err == null)
    @assert(decoded != null)
    @assert(decoded.other == -11)
    @assert(decoded.score.score() == 37)
    @assert(decoded.score.labelText() == "iface")

    releaseTagBinInterface(&decoded.score)
    Memory.delete(decoded)
}

#test
{
    var concrete = TagBinInterfaceProbe{value: 41}
    concrete.label = "inferred"

    let payload = TagBinInterfacePayload{
        score: cast(ITagBinScore) concrete,
        other: 12,
    }

    let bytes   = encodeTagBin(payload)
    let patched = corruptTagBinInterfaceObjectType(bytes, "score", 0xDEADBEEF)

    var decoder: Serialization.Decoder'Serialization.Read.TagBin
    let decoded = catch decoder.readAll'TagBinInterfacePayload(patched.toSlice())
    @assert(@err == null)
    @assert(decoded != null)
    @assert(decoded.other == 12)
    @assert(decoded.score.score() == 46)
    @assert(decoded.score.labelText() == "inferred")

    releaseTagBinInterface(&decoded.score)
    Memory.delete(decoded)
}

#test
{
    let payload = TagBinInterfacePayload{other: 19}
    let bytes   = encodeTagBin(payload)

    var decoder: Serialization.Decoder'Serialization.Read.TagBin
    let decoded = catch decoder.readAll'TagBinInterfacePayload(bytes.toSlice())
    @assert(@err == null)
    @assert(decoded != null)
    @assert(decoded.other == 19)

    let runtime = cast(*Swag.Interface) &decoded.score
    @assert(runtime.obj == null)
    @assert(runtime.itable == null)

    Memory.delete(decoded)
}

#test
{
    var payload: TagBinHookPayload
    let rawBytes: [4] u8 = [1, 3, 5, 7]

    payload.direct   = 20
    payload.remapped = 30
    payload.bytes.add(rawBytes)

    Reflection.registerType(#typeof(TagBinHookPayload))
    @assert(Reflection.hasInterface(#typeof(TagBinHookPayload), Serialization.ISerialize))
    let hookItf = @mkinterface(&payload, #typeof(TagBinHookPayload), Serialization.ISerialize)
    @assert(hookItf != null)

    let bytes = encodeTagBin(payload)

    var decoder: Serialization.Decoder'Serialization.Read.TagBin
    let decoded = catch decoder.readAll'TagBinHookPayload(bytes.toSlice())
    @assert(@err == null)
    @assert(decoded != null)
    @assert(decoded.direct == 21)
    @assert(decoded.remapped == 34)
    @assert(decoded.bytes.count == 4)
    @assert(decoded.bytes[0] == 7)
    @assert(decoded.bytes[1] == 5)
    @assert(decoded.bytes[2] == 3)
    @assert(decoded.bytes[3] == 1)
    @assert(decoded.postReadSeen)

    Memory.delete(decoded)
}

#test
{
    var source: TagBinConversionSource
    let staticToArray: [3] s16 = [-7, 8, 19]
    let arrayToStatic: [3] s8 = [-2, 4, 9]
    let arrayToSingle: [2] s16 = [55, 66]

    source.small          = -123
    source.floating       = 1.5
    source.staticToStatic = [5, 6, 7]
    source.staticToArray  = staticToArray
    source.arrayToStatic.add(arrayToStatic)
    source.singleToStatic = 42
    source.singleToArray  = 12
    source.arrayToSingle.add(arrayToSingle)
    source.nested         = TagBinLegacyNested{left: -5, right: 23}

    Reflection.registerType(#typeof(TagBinConversionSource))
    @assert(Reflection.crcToType(#typeof(#type [3] u8).crc) == #typeof(#type [3] u8))

    let bytes = encodeTagBin(source)

    var decoder: Serialization.Decoder'Serialization.Read.TagBin
    let decoded = catch decoder.readAll'TagBinConversionTarget(bytes.toSlice())
    @assert(@err == null)
    @assert(decoded != null)

    @assert(decoded.small == -123)
    @assert(decoded.floating == 1.5)
    @assert(decoded.staticToStatic[0] == 5)
    @assert(decoded.staticToStatic[1] == 6)
    @assert(decoded.staticToStatic[2] == 7)
    @assert(decoded.staticToStatic[3] == 0)
    @assert(decoded.staticToStatic[4] == 0)
    @assert(assertS32Array(decoded.staticToArray, [-7, 8, 19]))
    @assert(decoded.arrayToStatic[0] == -2)
    @assert(decoded.arrayToStatic[1] == 4)
    @assert(decoded.arrayToStatic[2] == 9)
    @assert(decoded.arrayToStatic[3] == 0)
    @assert(decoded.singleToStatic[0] == 42)
    @assert(decoded.singleToStatic[1] == 0)
    @assert(decoded.singleToStatic[2] == 0)
    @assert(assertU32Array(decoded.singleToArray, [12]))
    @assert(decoded.arrayToSingle == 55)
    @assert(decoded.nested.left == -5)
    @assert(decoded.nested.right == 23)

    Memory.delete(decoded)
}
