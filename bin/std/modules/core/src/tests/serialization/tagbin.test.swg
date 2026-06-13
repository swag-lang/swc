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

func corruptTagBinFieldType(bytes: String, fieldName: string, typeCrc: u32)->Array'u8
{
    var result: retval
    result.add(bytes.toSlice())

    var stream = ByteStream.openRead(result.toSlice())
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
        if crc == fieldCrc
        {
            var writer = ByteStream.openWrite(&result)
            writer.setSeek(seek + #sizeof(u32))
            writer.writeNative(typeCrc)
            return result
        }
    }

    @assert(false)
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
