#global if #command == Swag.CompilerCommand.Test
#global private

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
    blob: Array'u8

    #[Serialization.NoSerialize]
    transient: s32
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
    primitive:   #null typeinfo
    staticArray: #null typeinfo
    payload:     #null typeinfo
}

public interface ITagBinScore
{
    mtd score()->s32
    mtd labelText()->string
}

public struct TagBinInterfaceProbe
{
    value: s32
    label: String
}

public impl ITagBinScore for TagBinInterfaceProbe
{
    mtd impl score()->s32        => .value + 5
    mtd impl labelText()->string => .label.toString()
}

struct TagBinInterfacePayload
{
    score: #null ITagBinScore
    other: s32
}

public struct TagBinHookPayload
{
    direct:   s32
    remapped: s32
    bytes:    Array'u8

    #[Serialization.NoSerialize]
    postReadSeen: bool
}

public impl Serialization.ISerialize for TagBinHookPayload
{
    mtd impl read(_decoder: Serialization.IDecoder)->bool fail  => false
    mtd impl write(_encoder: Serialization.IEncoder)->bool fail => false

    mtd impl readElement(type: TypeValue, data: #null *void, decoder: Serialization.IDecoder)->bool fail
    {
        if type.name == "remapped"
        {
            if !decoder.beginField(type) do
                return true
            defer #nofail decoder.endField(type)

            dref cast(*s32) data! = decoder.readS32() - 6
            return true
        }

        if type.name == "bytes"
        {
            if !decoder.beginField(type) do
                return true
            defer #nofail decoder.endField(type)

            let raw = decoder.readBufferU8(4)
            defer Memory.free(raw, 4)

            let values = cast(*Array'u8) data!
            let rawPtr = cast([*] u8) raw!
            values.clear()
            for [i] in 4 do
                values.add(rawPtr[3 - i])
            return true
        }

        return false
    }

    mtd impl writeElement(type: TypeValue, data: #null const *void, encoder: Serialization.IEncoder)->bool fail
    {
        if type.name == "remapped"
        {
            encoder.beginField(type)
            defer #nofail encoder.endField(type)

            encoder.writeS32((dref cast(const *s32) data!) + 10)
            return true
        }

        if type.name == "bytes"
        {
            encoder.beginField(type)
            defer #nofail encoder.endField(type)

            let values = cast(const *Array'u8) data!
            encoder.writeBufferU8(values.buffer, values.count)
            return true
        }

        return false
    }

    mtd impl postRead(data: #null *void, _decoder: Serialization.IDecoder) fail
    {
        let value = cast(*TagBinHookPayload) data!
        value.postReadSeen = true
        value.direct       += 1
    }
}

func makeTagBinPayload()->TagBinPayload
{
    var result: retval

    let seed: [4] s32 = [-8, 0, 7, 42]
    result.id     = 17
    result.active = true
    result.name   = "tagbin"
    result.counts.add(seed)
    result.pair       = TagBinPair{x: -3, y: 11}
    result.fixed      = [9, 8, 7]
    result.finalPoint = TagBinFinalPoint{x: -2, y: 5}
    result.transient  = 123

    for [i] in 512
    {
        result.blob.add(cast(u8) (i % 4))
    }

    return result
}

func(T) encodeTagBin(value: T)->String
{
    var encoder: Serialization.Encoder'Serialization.Write.TagBin
    var buffer:  ConcatBuffer

    expect encoder.writeAll(&buffer, value)
    return buffer.toString()
}

func findTagBinFieldSeek(bytes: const [..] u8, fieldName: string)->u64
{
    var stream = ByteStream.openRead(bytes)
    @assert((expect stream.readNative'u32()) == Serialization.Write.TagBinSignature.Root)
    discard expect stream.readNative'u32()
    @assert((expect stream.readNative'u32()) == Serialization.Write.TagBinSignature.Version)
    discard expect stream.readNative'u32()
    @assert((expect stream.readNative'u32()) == Serialization.Write.TagBinSignature.Fat)
    let fatSeek  = expect stream.readNative'u64()
    let fatCount = expect stream.readNative'u64()
    stream.setPosition(fatSeek)
    @assert((expect stream.readNative'u32()) == Serialization.Write.TagBinSignature.Fat)
    let fieldCrc = Hash.Crc32.compute(fieldName)
    for fatCount
    {
        let crc  = expect stream.readNative'u32()
        let seek = expect stream.readNative'u64()
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

    let seek   = findTagBinFieldSeek(result.toSlice(), fieldName)
    var writer = ByteStream.openWrite(&result)
    writer.setPosition(seek + #sizeof(u32))
    writer.writeNative(typeCrc)
    return result
}

func corruptTagBinInterfaceObjectType(bytes: String, fieldName: string, typeCrc: u32)->Array'u8
{
    var result: retval
    result.add(bytes.toSlice())

    let seek   = findTagBinFieldSeek(result.toSlice(), fieldName)
    var writer = ByteStream.openWrite(&result)
    writer.setPosition(seek + #sizeof(u32) + #sizeof(u32) + #sizeof(Serialization.Write.TagBinValueFlags))
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

func releaseTagBinInterface(value: *#null ITagBinScore)
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
    let {raw, sizeof} = Serialization.isPodFinal(#typeof(TagBinFinalPoint))

    @assert(!writer.isTextual())
    @assert(!reader.isTextual())
    @assert(raw)
    @assert(sizeof == #sizeof(TagBinFinalPoint))
    @assert(Reflection.hasAttribute(#typeof(TagBinFinalPoint), Serialization.Final))
    @assert(!Reflection.hasAttribute(#typeof(TagBinFinalPoint), Serialization.NoSerialize))

    let blobField = Reflection.findField(#typeof(TagBinPayload), "blob")
    @assert(blobField != null)
    @assert(Reflection.hasAttribute(blobField, Serialization.Compress))
    @assert(!Reflection.hasAttribute(blobField, Serialization.NoSerialize))
}

#test
{
    let oldPoint = TagBinFieldWisePoint{x: -9, y: 12}
    let oldBytes = encodeTagBin(oldPoint)

    var finalDecoder: Serialization.Decoder'Serialization.Read.TagBin
    let finalPoint = expect finalDecoder.readAll'TagBinFinalMigrationPoint(oldBytes.toSlice())!
    @assert(finalPoint.x == -9)
    @assert(finalPoint.y == 12)

    let rawBytes = encodeTagBin(TagBinFinalMigrationPoint{x: 3, y: 4})

    var fieldWiseDecoder: Serialization.Decoder'Serialization.Read.TagBin
    let fieldWisePoint = catch fieldWiseDecoder.readAll'TagBinFieldWisePoint(rawBytes.toSlice()) as errfw
    @assert(fieldWisePoint == null)
    @assert(errfw != null)

    Memory.delete(finalPoint)
}

#test
{
    let payload = makeTagBinPayload()
    @assert(payload.finalPoint.x == -2)
    @assert(payload.finalPoint.y == 5)

    var encoder: Serialization.Encoder'Serialization.Write.TagBin
    var buffer:  ConcatBuffer
    expect encoder.writeAll(&buffer, payload)
    let bytes     = buffer.toString()
    let byteSlice = bytes.toSlice()

    var decoder: Serialization.Decoder'Serialization.Read.TagBin
    let decoded = expect decoder.readAll'TagBinPayload(byteSlice)!
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
    let decoded = expect decoder.readAll'TagBinPayload(patched.toSlice())!
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
    let decoded = expect decoder.readAll'TagBinPayload(bytes.toSlice())!
    @assert(decoded.id == 17)
    @assert(decoded.name.isNullOrEmpty())
    @assert(assertCompressedBlob(decoded.blob))

    Memory.delete(decoded)
}

#test
{
    let legacy = TagBinLegacyPayload{
        removed: 100,
        value: 21,
        legacyName: -6,
        numbers: [4, 5, 6],
        single: 33}
    let bytes = encodeTagBin(legacy)

    var decoder: Serialization.Decoder'Serialization.Read.TagBin
    let decoded = expect decoder.readAll'TagBinCurrentPayload(bytes.toSlice())!
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
    let strictValue = catch strictDecoder.readAll'TagBinOlderPayload(bytes.toSlice()) as errsv
    @assert(strictValue == null)
    @assert(errsv != null)

    var forwardDecoder: Serialization.Decoder'Serialization.Read.TagBin
    forwardDecoder.serializer.options.tryForward = true
    let forwardValue = expect forwardDecoder.readAll'TagBinOlderPayload(bytes.toSlice())!
    @assert(forwardValue.value == 44)

    Memory.delete(forwardValue)
}

#test
{
    Reflection.registerType(#typeof(TagBinPayload))
    Reflection.registerType(#typeof(#type [3] u8))

    let payload = TagBinTypeInfoPayload{
        primitive: #typeof(s32),
        staticArray: #typeof(#type [3] u8),
        payload: #typeof(TagBinPayload)}
    let bytes = encodeTagBin(payload)

    var decoder: Serialization.Decoder'Serialization.Read.TagBin
    let decoded = expect decoder.readAll'TagBinTypeInfoPayload(bytes.toSlice())!
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
        other: -11}

    Reflection.registerType(#typeof(TagBinInterfaceProbe))
    Reflection.registerType(#typeof(TagBinInterfacePayload))
    @assert(Reflection.hasInterface(#typeof(TagBinInterfaceProbe), ITagBinScore))
    @assert(payload.score!.score() == 37)

    let bytes = encodeTagBin(payload)

    var decoder: Serialization.Decoder'Serialization.Read.TagBin
    let decoded = expect decoder.readAll'TagBinInterfacePayload(bytes.toSlice())!
    @assert(decoded.other == -11)
    let score = decoded.score!
    @assert(score.score() == 37)
    @assert(score.labelText() == "iface")

    releaseTagBinInterface(&decoded.score)
    Memory.delete(decoded)
}

#test
{
    var concrete = TagBinInterfaceProbe{value: 41}
    concrete.label = "inferred"

    let payload = TagBinInterfacePayload{
        score: cast(ITagBinScore) concrete,
        other: 12}

    let bytes   = encodeTagBin(payload)
    let patched = corruptTagBinInterfaceObjectType(bytes, "score", 0xDEADBEEF)

    var decoder: Serialization.Decoder'Serialization.Read.TagBin
    let decoded = expect decoder.readAll'TagBinInterfacePayload(patched.toSlice())!
    @assert(decoded.other == 12)
    let score = decoded.score!
    @assert(score.score() == 46)
    @assert(score.labelText() == "inferred")

    releaseTagBinInterface(&decoded.score)
    Memory.delete(decoded)
}

#test
{
    let payload = TagBinInterfacePayload{other: 19}
    let bytes   = encodeTagBin(payload)

    var decoder: Serialization.Decoder'Serialization.Read.TagBin
    let decoded = expect decoder.readAll'TagBinInterfacePayload(bytes.toSlice())!
    @assert(decoded.other == 19)

    let runtime = cast(*Swag.Interface) &decoded.score
    @assert(runtime.obj == null)
    @assert(runtime.itable == null)

    Memory.delete(decoded)
}

#test
{
    var payload:  TagBinHookPayload
    let rawBytes: [4] u8 = [1, 3, 5, 7]

    payload.direct   = 20
    payload.remapped = 30
    payload.bytes.add(rawBytes)

    Reflection.registerType(#typeof(TagBinHookPayload))
    @assert(Reflection.hasInterface(#typeof(TagBinHookPayload), Serialization.ISerialize))
    let hookItf: Serialization.ISerialize = &payload
    @assert(hookItf != null)

    let bytes = encodeTagBin(payload)

    var decoder: Serialization.Decoder'Serialization.Read.TagBin
    let decoded = expect decoder.readAll'TagBinHookPayload(bytes.toSlice())!
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
    var source:        TagBinConversionSource
    let staticToArray: [3] s16 = [-7, 8, 19]
    let arrayToStatic: [3] s8  = [-2, 4, 9]
    let arrayToSingle: [2] s16 = [55, 66]

    source.small          = -123
    source.floating       = 1.5
    source.staticToStatic = [5, 6, 7]
    source.staticToArray  = staticToArray
    source.arrayToStatic.add(arrayToStatic)
    source.singleToStatic = 42
    source.singleToArray  = 12
    source.arrayToSingle.add(arrayToSingle)
    source.nested = TagBinLegacyNested{left: -5, right: 23}

    Reflection.registerType(#typeof(TagBinConversionSource))
    @assert(Reflection.typeFromCrc(#typeof(#type [3] u8).crc) == #typeof(#type [3] u8))

    let bytes = encodeTagBin(source)

    var decoder: Serialization.Decoder'Serialization.Read.TagBin
    let decoded = expect decoder.readAll'TagBinConversionTarget(bytes.toSlice())!
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

struct TagBinLegacyPair
{
    x: s32
    y: s32
}

// Builds a stream in the layout that shipped before the version word and the per-value flags
// byte existed: the root signature is followed straight away by the section, and an element is
// just its two CRCs and its payload. The type CRC is deliberately one no current type hashes
// to, which is also what those streams carry.
func buildLegacyTagBinStream(xValue, yValue: s32)->Array'u8
{
    const LegacyTypeCrc = 0x954A3BAB'u32

    var result: retval
    var writer = ByteStream.openWrite(&result)

    writer.writeNative(cast(u32) Serialization.Write.TagBinSignature.Root)
    writer.writeNative(cast(u32) Serialization.Write.TagBinSignature.Version)
    writer.writeNative(0'u32)
    writer.writeNative(cast(u32) Serialization.Write.TagBinSignature.Fat)

    let fatSeekField = writer.position()
    writer.writeNative(0'u64)
    writer.writeNative(2'u64)

    let xSeek = writer.position()
    writer.writeNative(Hash.Crc32.compute("x"))
    writer.writeNative(LegacyTypeCrc)
    writer.writeNative(xValue)

    let ySeek = writer.position()
    writer.writeNative(Hash.Crc32.compute("y"))
    writer.writeNative(LegacyTypeCrc)
    writer.writeNative(yValue)

    let fatSeek = writer.position()
    writer.writeNative(cast(u32) Serialization.Write.TagBinSignature.Fat)
    writer.writeNative(Hash.Crc32.compute("x"))
    writer.writeNative(xSeek)
    writer.writeNative(Hash.Crc32.compute("y"))
    writer.writeNative(ySeek)

    writer.setPosition(fatSeekField)
    writer.writeNative(fatSeek)
    return result
}

// A stream written before the format grew its version word still reads. Those streams also
// predate the per-value flags byte, so the two have to be recognized together: consuming a
// version word that is not there shifts the whole stream by four bytes, and reading a flags
// byte that is not there shifts every element by one.
#test
{
    let bytes = buildLegacyTagBinStream(1130, 1138)

    var decoder: Serialization.Decoder'Serialization.Read.TagBin
    let decoded = expect decoder.readAll'TagBinLegacyPair(bytes.toSlice())!
    defer Memory.delete(decoded)

    @assert(decoded.x == 1130)
    @assert(decoded.y == 1138)
}

func readTagBinValueFlags(bytes: const [..] u8, fieldName: string)->u8
{
    let seek   = findTagBinFieldSeek(bytes, fieldName)
    var stream = ByteStream.openRead(bytes)
    stream.setPosition(seek + #sizeof(u32) + #sizeof(u32))

    let flags = catch stream.readNative'u8() as errvf
    @assert(errvf == null)
    return flags
}

// The value-flags byte is on-disk format, not an internal detail: it is written as a
// raw number and every stream ever produced carries 1 for a plain value and 3 for a
// compressed one. Renumbering the enum silently reinterprets every plain value in an
// existing stream as a compressed one, so the byte is pinned here rather than compared
// against the enum cases it is meant to guard.
#test
{
    @assert(#sizeof(Serialization.Write.TagBinValueFlags) == 1)

    let payload = makeTagBinPayload()
    let bytes   = encodeTagBin(payload)
    @assert(readTagBinValueFlags(bytes.toSlice(), "id") == 1)
    @assert(readTagBinValueFlags(bytes.toSlice(), "blob") == 3)
}

func readTagBinCompressedSizes(bytes: const [..] u8, fieldName: string)->{ uncompressed: u64, compressed: u64 }
{
    let seek   = findTagBinFieldSeek(bytes, fieldName)
    var stream = ByteStream.openRead(bytes)
    stream.setPosition(seek + #sizeof(u32) + #sizeof(u32) + #sizeof(Serialization.Write.TagBinValueFlags))

    var result: retval
    result.uncompressed = expect stream.readNative'u64()
    result.compressed   = expect stream.readNative'u64()
    return result
}

func corruptTagBinCompressedSizes(bytes: String, fieldName: string, uncompressed, compressed: u64)->Array'u8
{
    var result: retval
    result.add(bytes.toSlice())

    let seek   = findTagBinFieldSeek(result.toSlice(), fieldName)
    var writer = ByteStream.openWrite(&result)
    writer.setPosition(seek + #sizeof(u32) + #sizeof(u32) + #sizeof(Serialization.Write.TagBinValueFlags))
    writer.writeNative(uncompressed)
    writer.writeNative(compressed)
    return result
}

// A compressed run that claims more bytes than the stream holds is refused before
// anything is reserved for it.
#test
{
    let payload = makeTagBinPayload()
    let bytes   = encodeTagBin(payload)
    let sizes   = readTagBinCompressedSizes(bytes.toSlice(), "blob")
    let patched = corruptTagBinCompressedSizes(bytes, "blob", sizes.uncompressed, bytes.length + 1)

    var decoder: Serialization.Decoder'Serialization.Read.TagBin
    let decoded = catch decoder.readAll'TagBinPayload(patched.toSlice()) as err24
    @assert(err24 != null)
    @assert(decoded == null)
}

// The announced uncompressed size is a sizing hint only: an implausible one is
// ignored and the payload still decodes from the compressed bytes themselves.
#test
{
    let payload = makeTagBinPayload()
    let bytes   = encodeTagBin(payload)
    let sizes   = readTagBinCompressedSizes(bytes.toSlice(), "blob")
    let patched = corruptTagBinCompressedSizes(bytes, "blob", Swag.U64.Max, sizes.compressed)

    var decoder: Serialization.Decoder'Serialization.Read.TagBin
    let decoded = expect decoder.readAll'TagBinPayload(patched.toSlice())!
    @assert(assertCompressedBlob(decoded.blob))

    Memory.delete(decoded)
}

// A field whose header does not decode is skipped without unbalancing the element
// stack, so the fields around it still read back.
#test
{
    let payload = makeTagBinPayload()
    let bytes   = encodeTagBin(payload)
    let sizes   = readTagBinCompressedSizes(bytes.toSlice(), "blob")
    let patched = corruptTagBinCompressedSizes(bytes, "blob", sizes.uncompressed, bytes.length + 1)

    var decoder: Serialization.Decoder'Serialization.Read.TagBin
    decoder.flags |= .IgnoreStructFieldError

    let decoded = expect decoder.readAll'TagBinPayload(patched.toSlice())!
    @assert(decoded.id == 17)
    @assert(decoded.name == "tagbin")
    @assert(assertS32Array(decoded.counts, [-8, 0, 7, 42]))
    @assert(decoded.blob.isEmpty())

    Memory.delete(decoded)
}
