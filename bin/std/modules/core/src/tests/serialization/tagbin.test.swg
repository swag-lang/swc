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
