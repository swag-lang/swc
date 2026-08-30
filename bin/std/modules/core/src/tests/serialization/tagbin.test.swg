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

enum TagBinModeU8: u8
{
    Off
    Fast
    Precise
}

enum TagBinModeU32: u32
{
    Off
    Fast
    Precise
}

struct TagBinEnumSource
{
    mode: TagBinModeU8 = .Off
    tail: s32
}

struct TagBinEnumTarget
{
    mode: TagBinModeU32 = .Off
    tail: s32
}

struct TagBinLongText
{
    name: String
}

#[Serialization.Version(7)]
struct TagBinV1VersionedPair
{
    x: s32
    y: s32
}

public interface ITagBinScore
{
    mtd score()->s32
    mtd labelText()->string
}

public struct TagBinInterfaceProbe
{
    public
    {
        value: s32
        label: String
    }
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
    public
    {
        direct:   s32
        remapped: s32
        bytes:    Array'u8

        #[Serialization.NoSerialize]
        postReadSeen: bool
    }
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

            data![as s32] = decoder.readS32() - 6
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
            for i in 4 do
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

            encoder.writeS32(data![as s32] + 10)
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

// Captures the stream version a struct decode observes, so the version plumbing is
// testable from user code.
#[Serialization.Version(5)]
public struct TagBinVersionProbe
{
    public
    {
        value: s32

        #[Serialization.NoSerialize]
        seenVersion: u32
    }
}

public impl Serialization.ISerialize for TagBinVersionProbe
{
    mtd impl read(_decoder: Serialization.IDecoder)->bool fail  => false
    mtd impl write(_encoder: Serialization.IEncoder)->bool fail => false

    mtd impl readElement(_type: TypeValue, _data: #null *void, _decoder: Serialization.IDecoder)->bool fail => false

    mtd impl writeElement(_type: TypeValue, _data: #null const *void, _encoder: Serialization.IEncoder)->bool fail => false

    mtd impl postRead(data: #null *void, decoder: Serialization.IDecoder) fail
    {
        let value = cast(*TagBinVersionProbe) data!
        value.seenVersion = decoder.version()
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

    expect encoder.writeAll(&buffer, value)
    return buffer.toString()
}

// Where a field of the root struct sits inside a version 2 stream, plus the location
// of its shape metadata.
struct TagBinV2Field
{
    seek:          u64     // Absolute file position of the field payload.
    shapeFlags:    u8      // Shape flags of the field.
    shapeTypeSeek: u64     // Absolute file position of the crcType word of its shape entry.
}

// Walks the version 2 header, the root section header, its fat and the shape
// directory to locate one field of the root struct.
func findTagBinV2Field(bytes: const [..] u8, fieldName: string)->TagBinV2Field
{
    const BodyStart = 20'u64

    var result: retval
    var stream = ByteStream.openRead(bytes)
    Swag.assert((expect stream.readNative'u32()) == Serialization.Write.TagBinSignature.Root)
    Swag.assert((expect stream.readNative'u32()) == cast(u32) Serialization.Write.TagBinVersion2)
    Swag.assert((expect stream.readNative'u32()) == 0)
    let shapeDirOffset = expect stream.readNative'u64()

    // Root struct section header.
    Swag.assert((expect stream.readNative'u32()) == Serialization.Write.TagBinSignature.Version)
    discard expect stream.readNative'u32()
    Swag.assert((expect stream.readNative'u32()) == Serialization.Write.TagBinSignature.Fat)
    let shapeId = expect stream.readNative'u32()
    Swag.assert(shapeId != Serialization.Write.TagBinAdHocShape)
    let fatOffset    = expect stream.readNative'u64()
    let payloadStart = stream.position() - BodyStart

    // Walk the shape directory up to the field entry.
    stream.setPosition(BodyStart + shapeDirOffset)
    Swag.assert((expect stream.readNative'u32()) == Serialization.Write.TagBinSignature.ShapeDir)
    let shapeCount = expect stream.readVarint()
    Swag.assert(shapeId < shapeCount)

    let fieldCrc = Hash.Crc32.compute(fieldName)
    for s in shapeCount
    {
        let fieldCount = expect stream.readVarint()
        for i in fieldCount
        {
            let crcName  = expect stream.readNative'u32()
            let typeSeek = stream.position()
            discard expect stream.readNative'u32()
            let flags = expect stream.readNative'u8()
            if s == shapeId and crcName == fieldCrc
            {
                result.shapeFlags    = flags
                result.shapeTypeSeek = typeSeek

                // The matching fat entry holds the payload offset of the field.
                stream.setPosition(BodyStart + fatOffset + i * #sizeof(u32))
                let rel = expect stream.readNative'u32()
                result.seek = BodyStart + payloadStart + rel
                return result
            }
        }
    }

    Swag.assert(false)
    return result
}

func corruptTagBinFieldType(bytes: String, fieldName: string, typeCrc: u32)->Array'u8
{
    var result: retval
    result.add(bytes.toSlice())

    let field  = findTagBinV2Field(result.toSlice(), fieldName)
    var writer = ByteStream.openWrite(&result)
    writer.setPosition(field.shapeTypeSeek)
    writer.writeNative(typeCrc)
    return result
}

// An interface payload is a raw section: its byte length, then the object type crc.
func corruptTagBinInterfaceObjectType(bytes: String, fieldName: string, typeCrc: u32)->Array'u8
{
    var result: retval
    result.add(bytes.toSlice())

    let field  = findTagBinV2Field(result.toSlice(), fieldName)
    var writer = ByteStream.openWrite(&result)
    writer.setPosition(field.seek + #sizeof(u64))
    writer.writeNative(typeCrc)
    return result
}

// A nested final struct is a raw signature followed by the raw byte length.
func corruptTagBinRawLen(bytes: String, fieldName: string, newLen: u64)->Array'u8
{
    var result: retval
    result.add(bytes.toSlice())

    let field  = findTagBinV2Field(result.toSlice(), fieldName)
    var writer = ByteStream.openWrite(&result)
    writer.setPosition(field.seek + #sizeof(u32))
    writer.writeNative(newLen)
    return result
}

func assertS32Array(values: Array's32, expected: const [..] s32)->bool
{
    if values.count != expected.count do
        return false

    for values.count
    {
        if values[Swag.index] != expected[Swag.index] do
            return false
    }

    return true
}

func assertCompressedBlob(values: Array'u8)->bool
{
    if values.count != 512 do
        return false

    for values.count
    {
        if values[Swag.index] != cast(u8) (Swag.index % 4) do
            return false
    }

    return true
}

func assertU32Array(values: Array'u32, expected: const [..] u32)->bool
{
    if values.count != expected.count do
        return false

    for values.count
    {
        if values[Swag.index] != expected[Swag.index] do
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

    Swag.assert(!writer.isTextual())
    Swag.assert(!reader.isTextual())
    Swag.assert(raw)
    Swag.assert(sizeof == #sizeof(TagBinFinalPoint))
    Swag.assert(Reflection.hasAttribute(#typeof(TagBinFinalPoint), Serialization.Final))
    Swag.assert(!Reflection.hasAttribute(#typeof(TagBinFinalPoint), Serialization.NoSerialize))

    let blobField = Reflection.findField(#typeof(TagBinPayload), "blob")
    Swag.assert(blobField != null)
    Swag.assert(Reflection.hasAttribute(blobField, Serialization.Compress))
    Swag.assert(!Reflection.hasAttribute(blobField, Serialization.NoSerialize))
}

#test
{
    let oldPoint = TagBinFieldWisePoint{x: -9, y: 12}
    let oldBytes = encodeTagBin(oldPoint)

    var finalDecoder: Serialization.Decoder'Serialization.Read.TagBin
    let finalPoint = expect finalDecoder.readAll'TagBinFinalMigrationPoint(oldBytes.toSlice())!
    Swag.assert(finalPoint.x == -9)
    Swag.assert(finalPoint.y == 12)

    let rawBytes = encodeTagBin(TagBinFinalMigrationPoint{x: 3, y: 4})

    var fieldWiseDecoder: Serialization.Decoder'Serialization.Read.TagBin
    let fieldWisePoint = catch fieldWiseDecoder.readAll'TagBinFieldWisePoint(rawBytes.toSlice()) as errfw
    Swag.assert(fieldWisePoint == null)
    Swag.assert(errfw != null)

    Memory.delete(finalPoint)
}

#test
{
    let payload = makeTagBinPayload()
    Swag.assert(payload.finalPoint.x == -2)
    Swag.assert(payload.finalPoint.y == 5)

    var encoder: Serialization.Encoder'Serialization.Write.TagBin
    var buffer:  ConcatBuffer
    expect encoder.writeAll(&buffer, payload)
    let bytes     = buffer.toString()
    let byteSlice = bytes.toSlice()

    var decoder: Serialization.Decoder'Serialization.Read.TagBin
    let decoded = expect decoder.readAll'TagBinPayload(byteSlice)!
    Swag.assert(decoded.id == 17)
    Swag.assert(decoded.active)
    Swag.assert(decoded.name == "tagbin")
    decoded.name = "decoded"
    Swag.assert(decoded.name == "decoded")
    Swag.assert(assertS32Array(decoded.counts, [-8, 0, 7, 42]))
    Swag.assert(decoded.pair.x == -3)
    Swag.assert(decoded.pair.y == 11)
    Swag.assert(decoded.fixed[0] == 9)
    Swag.assert(decoded.fixed[1] == 8)
    Swag.assert(decoded.fixed[2] == 7)
    Swag.assert(decoded.finalPoint.x == -2)
    Swag.assert(decoded.finalPoint.y == 5)
    Swag.assert(assertCompressedBlob(decoded.blob))
    Swag.assert(decoded.transient == 0)

    // A stream produced and consumed by the same types decodes without a single
    // diagnostic: this is the positional fast path.
    Swag.assert(decoder.serializer.diag.fieldErrors == 0)
    Swag.assert(decoder.serializer.diag.droppedStreamFields == 0)
    Swag.assert(decoder.serializer.diag.unknownTypes == 0)
    Swag.assert(decoder.serializer.diag.recoveredFields == 0)
    Swag.assert(decoder.serializer.diag.corruptPayloads == 0)

    Memory.delete(decoded)
}

// A scalar whose stream type crc resolves to nothing has no self-validating framing,
// so a strict decode refuses it rather than reading garbage; a tolerant one resets the
// field and says so in the diagnostics.
#test
{
    let payload = makeTagBinPayload()
    let bytes   = encodeTagBin(payload)
    let patched = corruptTagBinFieldType(bytes, "id", 0xDEADBEEF)

    var strictDecoder: Serialization.Decoder'Serialization.Read.TagBin
    let strictValue = catch strictDecoder.readAll'TagBinPayload(patched.toSlice()) as errst
    Swag.assert(strictValue == null)
    Swag.assert(errst != null)

    var decoder: Serialization.Decoder'Serialization.Read.TagBin
    decoder.flags |= .IgnoreStructFieldError
    let decoded = expect decoder.readAll'TagBinPayload(patched.toSlice())!
    Swag.assert(decoded.id == 0)
    Swag.assert(decoded.name == "tagbin")
    Swag.assert(assertCompressedBlob(decoded.blob))
    Swag.assert(decoder.serializer.diag.unknownTypes >= 1)
    Swag.assert(decoder.serializer.diag.fieldErrors >= 1)

    Memory.delete(decoded)
}

#test
{
    let payload = makeTagBinPayload()
    let bytes   = encodeTagBin(payload)

    var decoder: Serialization.Decoder'Serialization.Read.TagBin
    decoder.serializer.ignoreElements.add("name")
    let decoded = expect decoder.readAll'TagBinPayload(bytes.toSlice())!
    Swag.assert(decoded.id == 17)
    Swag.assert(decoded.name.isNullOrEmpty())
    Swag.assert(assertCompressedBlob(decoded.blob))

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
    Swag.assert(decoded.renamed == -6)
    Swag.assert(decoded.value == 21)
    Swag.assert(decoded.numbers[0] == 4)
    Swag.assert(decoded.numbers[1] == 5)
    Swag.assert(decoded.numbers[2] == 6)
    Swag.assert(decoded.single == 33)

    // The stream field 'removed' is data the current type no longer requests, and the
    // diagnostics say so.
    Swag.assert(decoder.serializer.diag.droppedStreamFields == 1)
    Swag.assert(decoder.serializer.diag.fieldErrors == 0)

    Memory.delete(decoded)
}

#test
{
    let future = TagBinFuturePayload{value: 44}
    let bytes  = encodeTagBin(future)

    var strictDecoder: Serialization.Decoder'Serialization.Read.TagBin
    let strictValue = catch strictDecoder.readAll'TagBinOlderPayload(bytes.toSlice()) as errsv
    Swag.assert(strictValue == null)
    Swag.assert(errsv != null)

    var forwardDecoder: Serialization.Decoder'Serialization.Read.TagBin
    forwardDecoder.serializer.options.tryForward = true
    let forwardValue = expect forwardDecoder.readAll'TagBinOlderPayload(bytes.toSlice())!
    Swag.assert(forwardValue.value == 44)

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
    Swag.assert(decoded.primitive == s32)
    Swag.assert(decoded.staticArray == #typeof(#type [3] u8))
    Swag.assert(decoded.payload == TagBinPayload)

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
    Swag.assert(Reflection.hasInterface(#typeof(TagBinInterfaceProbe), ITagBinScore))
    Swag.assert(payload.score!.score() == 37)

    let bytes = encodeTagBin(payload)

    var decoder: Serialization.Decoder'Serialization.Read.TagBin
    let decoded = expect decoder.readAll'TagBinInterfacePayload(bytes.toSlice())!
    Swag.assert(decoded.other == -11)
    let score = decoded.score!
    Swag.assert(score.score() == 37)
    Swag.assert(score.labelText() == "iface")

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
    Swag.assert(decoded.other == 12)
    let score = decoded.score!
    Swag.assert(score.score() == 46)
    Swag.assert(score.labelText() == "inferred")

    releaseTagBinInterface(&decoded.score)
    Memory.delete(decoded)
}

#test
{
    let payload = TagBinInterfacePayload{other: 19}
    let bytes   = encodeTagBin(payload)

    var decoder: Serialization.Decoder'Serialization.Read.TagBin
    let decoded = expect decoder.readAll'TagBinInterfacePayload(bytes.toSlice())!
    Swag.assert(decoded.other == 19)

    let runtime = cast(*Swag.Interface) &decoded.score
    Swag.assert(runtime.obj == null)
    Swag.assert(runtime.itable == null)

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
    Swag.assert(Reflection.hasInterface(#typeof(TagBinHookPayload), Serialization.ISerialize))
    let hookItf: Serialization.ISerialize = &payload
    Swag.assert(hookItf != null)

    let bytes = encodeTagBin(payload)

    var decoder: Serialization.Decoder'Serialization.Read.TagBin
    let decoded = expect decoder.readAll'TagBinHookPayload(bytes.toSlice())!
    Swag.assert(decoded.direct == 21)
    Swag.assert(decoded.remapped == 34)
    Swag.assert(decoded.bytes.count == 4)
    Swag.assert(decoded.bytes[0] == 7)
    Swag.assert(decoded.bytes[1] == 5)
    Swag.assert(decoded.bytes[2] == 3)
    Swag.assert(decoded.bytes[3] == 1)
    Swag.assert(decoded.postReadSeen)

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
    Swag.assert(Reflection.typeFromCrc(#typeof(#type [3] u8).crc) == #typeof(#type [3] u8))

    let bytes = encodeTagBin(source)

    var decoder: Serialization.Decoder'Serialization.Read.TagBin
    let decoded = expect decoder.readAll'TagBinConversionTarget(bytes.toSlice())!
    Swag.assert(decoded.small == -123)
    Swag.assert(decoded.floating == 1.5)
    Swag.assert(decoded.staticToStatic[0] == 5)
    Swag.assert(decoded.staticToStatic[1] == 6)
    Swag.assert(decoded.staticToStatic[2] == 7)
    Swag.assert(decoded.staticToStatic[3] == 0)
    Swag.assert(decoded.staticToStatic[4] == 0)
    Swag.assert(assertS32Array(decoded.staticToArray, [-7, 8, 19]))
    Swag.assert(decoded.arrayToStatic[0] == -2)
    Swag.assert(decoded.arrayToStatic[1] == 4)
    Swag.assert(decoded.arrayToStatic[2] == 9)
    Swag.assert(decoded.arrayToStatic[3] == 0)
    Swag.assert(decoded.singleToStatic[0] == 42)
    Swag.assert(decoded.singleToStatic[1] == 0)
    Swag.assert(decoded.singleToStatic[2] == 0)
    Swag.assert(assertU32Array(decoded.singleToArray, [12]))
    Swag.assert(decoded.arrayToSingle == 55)
    Swag.assert(decoded.nested.left == -5)
    Swag.assert(decoded.nested.right == 23)

    Memory.delete(decoded)
}

// An enum travels as its underlying type: widening that type between the write and the
// read is an ordinary native conversion, and renaming the enum costs nothing.
#test
{
    var source: TagBinEnumSource
    source.mode = .Precise
    source.tail = -9

    let bytes = encodeTagBin(source)

    var decoder: Serialization.Decoder'Serialization.Read.TagBin
    let decoded = expect decoder.readAll'TagBinEnumTarget(bytes.toSlice())!
    Swag.assert(decoded.mode == .Precise)
    Swag.assert(decoded.tail == -9)

    Memory.delete(decoded)
}

// The stream version of a struct is visible from user code during the decode, which is
// what a deliberate data migration keys on.
#test
{
    var probe: TagBinVersionProbe
    probe.value = 3

    let bytes = encodeTagBin(probe)

    var decoder: Serialization.Decoder'Serialization.Read.TagBin
    let decoded = expect decoder.readAll'TagBinVersionProbe(bytes.toSlice())!
    Swag.assert(decoded.value == 3)
    Swag.assert(decoded.seenVersion == 5)

    Memory.delete(decoded)
}

// Compressing the whole stream is a writer option: the header says so, and the decode
// is unchanged for the caller.
#test
{
    let payload = makeTagBinPayload()

    var encoder: Serialization.Encoder'Serialization.Write.TagBin
    encoder.serializer.compressStream = true
    var buffer: ConcatBuffer
    expect encoder.writeAll(&buffer, payload)
    let bytes = buffer.toString()

    var stream = ByteStream.openRead(bytes.toSlice())
    discard expect stream.readNative'u32()
    Swag.assert((expect stream.readNative'u32()) == cast(u32) Serialization.Write.TagBinVersion2)
    Swag.assert((expect stream.readNative'u32()) == 1)

    var decoder: Serialization.Decoder'Serialization.Read.TagBin
    let decoded = expect decoder.readAll'TagBinPayload(bytes.toSlice())!
    Swag.assert(decoded.id == 17)
    Swag.assert(decoded.name == "tagbin")
    Swag.assert(assertS32Array(decoded.counts, [-8, 0, 7, 42]))
    Swag.assert(assertCompressedBlob(decoded.blob))

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

    Swag.assert(decoded.x == 1130)
    Swag.assert(decoded.y == 1138)
}

// Builds a version 1 stream: the version mark follows the root signature, elements carry
// their two CRCs and a value-flags byte, and the fat stores absolute positions. The
// writer no longer produces this layout, so reading it is pinned here by hand.
func buildV1TagBinStream(xValue, yValue: s32, version: u32, swapOrder: bool)->Array'u8
{
    const LegacyTypeCrc = 0x954A3BAB'u32

    var result: retval
    var writer = ByteStream.openWrite(&result)

    writer.writeNative(cast(u32) Serialization.Write.TagBinSignature.Root)
    writer.writeNative(cast(u32) Serialization.Write.TagBinVersion1)
    writer.writeNative(cast(u32) Serialization.Write.TagBinSignature.Version)
    writer.writeNative(version)
    writer.writeNative(cast(u32) Serialization.Write.TagBinSignature.Fat)

    let fatSeekField = writer.position()
    writer.writeNative(0'u64)
    writer.writeNative(2'u64)

    var firstName  = "x"
    var secondName = "y"
    var firstVal   = xValue
    var secondVal  = yValue
    if swapOrder
    {
        firstName  = "y"
        secondName = "x"
        firstVal   = yValue
        secondVal  = xValue
    }

    let firstSeek = writer.position()
    writer.writeNative(Hash.Crc32.compute(firstName))
    writer.writeNative(LegacyTypeCrc)
    writer.writeNative(1'u8)
    writer.writeNative(firstVal)

    let secondSeek = writer.position()
    writer.writeNative(Hash.Crc32.compute(secondName))
    writer.writeNative(LegacyTypeCrc)
    writer.writeNative(1'u8)
    writer.writeNative(secondVal)

    let fatSeek = writer.position()
    writer.writeNative(cast(u32) Serialization.Write.TagBinSignature.Fat)
    writer.writeNative(Hash.Crc32.compute(firstName))
    writer.writeNative(firstSeek)
    writer.writeNative(Hash.Crc32.compute(secondName))
    writer.writeNative(secondSeek)

    writer.setPosition(fatSeekField)
    writer.writeNative(fatSeek)
    return result
}

// The value-flags byte of a version 1 stream is on-disk format, not an internal detail:
// every stream ever produced carries 1 for a plain value and 3 for a compressed one, so
// the cases are pinned. The same applies to the shape flags of a version 2 stream.
#test
{
    Swag.assert(#sizeof(Serialization.Write.TagBinValueFlags) == 1)
    Swag.assert(cast(u8) Serialization.Write.TagBinValueFlags.None == 1)
    Swag.assert(cast(u8) Serialization.Write.TagBinValueFlags.Compressed == 2)
    Swag.assert(#sizeof(Serialization.Write.TagBinShapeFlags) == 1)
    Swag.assert(cast(u8) Serialization.Write.TagBinShapeFlags.Zero == 0)
    Swag.assert(cast(u8) Serialization.Write.TagBinShapeFlags.Compressed == 1)

    let payload = makeTagBinPayload()
    let bytes   = encodeTagBin(payload)
    Swag.assert(findTagBinV2Field(bytes.toSlice(), "id").shapeFlags == 0)
    Swag.assert(findTagBinV2Field(bytes.toSlice(), "blob").shapeFlags == 1)
}

// A version 1 stream reads through the fat exactly as it always did.
#test
{
    let bytes = buildV1TagBinStream(-52, 977, 0, false)

    var decoder: Serialization.Decoder'Serialization.Read.TagBin
    let decoded = expect decoder.readAll'TagBinLegacyPair(bytes.toSlice())!
    defer Memory.delete(decoded)

    Swag.assert(decoded.x == -52)
    Swag.assert(decoded.y == 977)
}

// Equal versions select the positional fast path of a version 1 stream. When the field
// order does not actually match, the fat is still in the stream: the decode falls back
// to it instead of failing the struct.
#test
{
    let bytes = buildV1TagBinStream(41, -18, 7, true)

    var decoder: Serialization.Decoder'Serialization.Read.TagBin
    let decoded = expect decoder.readAll'TagBinV1VersionedPair(bytes.toSlice())!
    defer Memory.delete(decoded)

    Swag.assert(decoded.x == 41)
    Swag.assert(decoded.y == -18)
    Swag.assert(decoder.serializer.diag.recoveredFields >= 1)
}

func readTagBinCompressedSizes(bytes: const [..] u8, fieldName: string)->{ uncompressed: u64, compressed: u64 }
{
    let field  = findTagBinV2Field(bytes, fieldName)
    var stream = ByteStream.openRead(bytes)
    stream.setPosition(field.seek)

    var result: retval
    result.uncompressed = expect stream.readNative'u64()
    result.compressed   = expect stream.readNative'u64()
    return result
}

func corruptTagBinCompressedSizes(bytes: String, fieldName: string, uncompressed, compressed: u64)->Array'u8
{
    var result: retval
    result.add(bytes.toSlice())

    let field  = findTagBinV2Field(result.toSlice(), fieldName)
    var writer = ByteStream.openWrite(&result)
    writer.setPosition(field.seek)
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
    Swag.assert(err24 != null)
    Swag.assert(decoded == null)
}

// The announced sizes must describe the payload truthfully: a lying uncompressed size
// is refused instead of decoding to something else than what was written.
#test
{
    let payload = makeTagBinPayload()
    let bytes   = encodeTagBin(payload)
    let sizes   = readTagBinCompressedSizes(bytes.toSlice(), "blob")
    let patched = corruptTagBinCompressedSizes(bytes, "blob", sizes.uncompressed + 1, sizes.compressed)

    var decoder: Serialization.Decoder'Serialization.Read.TagBin
    let decoded = catch decoder.readAll'TagBinPayload(patched.toSlice()) as errsz
    Swag.assert(errsz != null)
    Swag.assert(decoded == null)
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
    Swag.assert(decoded.id == 17)
    Swag.assert(decoded.name == "tagbin")
    Swag.assert(assertS32Array(decoded.counts, [-8, 0, 7, 42]))
    Swag.assert(decoded.blob.isEmpty())
    Swag.assert(decoder.serializer.diag.fieldErrors >= 1)

    Memory.delete(decoded)
}

// A raw payload records its byte length, so a final struct whose layout drifted away
// from the stream is detected instead of silently misread: a strict decode refuses the
// stream, a tolerant one reports through the diagnostics.
#test
{
    let payload = makeTagBinPayload()
    let bytes   = encodeTagBin(payload)
    let patched = corruptTagBinRawLen(bytes, "finalPoint", 6)

    var strictDecoder: Serialization.Decoder'Serialization.Read.TagBin
    let strictValue = catch strictDecoder.readAll'TagBinPayload(patched.toSlice()) as errrl
    Swag.assert(strictValue == null)
    Swag.assert(errrl != null)

    var decoder: Serialization.Decoder'Serialization.Read.TagBin
    decoder.flags |= .IgnoreStructFieldError
    let decoded = expect decoder.readAll'TagBinPayload(patched.toSlice())!
    Swag.assert(decoded.id == 17)
    Swag.assert(decoded.name == "tagbin")
    Swag.assert(assertS32Array(decoded.counts, [-8, 0, 7, 42]))
    Swag.assert(decoder.serializer.diag.corruptPayloads >= 1)

    Memory.delete(decoded)
}

// A sequence count is validated against the bytes that remain, and a raw payload
// against its written byte length, before any allocation happens.
#test
{
    let payload = makeTagBinPayload()
    let bytes   = encodeTagBin(payload)

    var patched: Array'u8
    patched.add(bytes.toSlice())
    let field  = findTagBinV2Field(patched.toSlice(), "counts")
    var writer = ByteStream.openWrite(&patched)
    writer.setPosition(field.seek + #sizeof(u32))
    writer.writeNative(0x7F'u8)

    var decoder: Serialization.Decoder'Serialization.Read.TagBin
    let decoded = catch decoder.readAll'TagBinPayload(patched.toSlice()) as errsq
    Swag.assert(errsq != null)
    Swag.assert(decoded == null)
}

// A string length beyond the remaining bytes is refused before reserving anything.
#test
{
    var payload: TagBinLongText
    for 200 do
        payload.name += "x"

    let bytes = encodeTagBin(payload)

    var patched: Array'u8
    patched.add(bytes.toSlice())
    let field  = findTagBinV2Field(patched.toSlice(), "name")
    var writer = ByteStream.openWrite(&patched)
    writer.setPosition(field.seek)
    writer.writeNative(0xFF'u8)
    writer.writeNative(0x7F'u8)

    var decoder: Serialization.Decoder'Serialization.Read.TagBin
    let decoded = catch decoder.readAll'TagBinLongText(patched.toSlice()) as errln
    Swag.assert(errln != null)
    Swag.assert(decoded == null)
}
