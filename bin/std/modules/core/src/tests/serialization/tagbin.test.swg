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

#[Serialization.Schema("core.test.schema-a")]
struct TagBinSchemaA
{
    value: s32
}

#[Serialization.Schema("core.test.schema-b")]
struct TagBinSchemaB
{
    value: s32
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

    #[Serialization.Key("legacyName")]
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

struct TagBinReadableKeyCollision
{
    #[Serialization.Key("7MhoTAnbgQsL")]
    first: s32

    #[Serialization.Key("6WMZ2VaaUabd")]
    second: s32
}

public interface ITagBinScore
{
    mtd score()->s32
    mtd labelText()->string
}

#[Serialization.TypeKey("core.test.tagbin-score")]
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

// Where a field of the root struct sits inside a version 1 stream, plus the location
// of its shape metadata.
struct TagBinV1Field
{
    seek:          u64     // Absolute file position of the field payload.
    shapeFlags:    u8      // Shape flags of the field.
    shapeTypeSeek: u64     // Absolute file position of the crcType word of its shape entry.
}

// Walks the version 1 header, the root section header, its fat and the shape
// directory to locate one field of the root struct.
func findTagBinV1Field(bytes: const [..] u8, fieldName: string)->TagBinV1Field
{
    var result: retval
    var stream = ByteStream.openRead(bytes)
    Swag.assert((expect stream.readNative'u32()) == Serialization.Write.TagBinSignature.Root)
    Swag.assert((expect stream.readNative'u32()) == cast(u32) Serialization.Write.TagBinVersion1)
    let schemaLength = expect stream.readVarint()
    Swag.assert(schemaLength == 0)
    Swag.assert((expect stream.readNative'u32()) == 0)
    let shapeDirOffset = expect stream.readNative'u64()
    let bodyStart      = stream.position()

    // Root struct section header.
    Swag.assert((expect stream.readNative'u32()) == Serialization.Write.TagBinSignature.Version)
    discard expect stream.readNative'u32()
    Swag.assert((expect stream.readNative'u32()) == Serialization.Write.TagBinSignature.Fat)
    let shapeId = expect stream.readNative'u32()
    Swag.assert(shapeId != Serialization.Write.TagBinAdHocShape)
    let fatOffset    = expect stream.readNative'u64()
    let payloadStart = stream.position() - bodyStart

    // Walk the shape directory up to the field entry.
    stream.setPosition(bodyStart + shapeDirOffset)
    Swag.assert((expect stream.readNative'u32()) == Serialization.Write.TagBinSignature.ShapeDir)
    let shapeCount = expect stream.readVarint()
    Swag.assert(shapeId < shapeCount)

    for s in shapeCount
    {
        let fieldCount = expect stream.readVarint()
        for i in fieldCount
        {
            let keyLength = expect stream.readVarint()
            var key: String
            key.reserve(keyLength)
            expect stream.readBytes(key.buffer, keyLength)
            key.length = keyLength
            let typeSeek = stream.position()
            discard expect stream.readNative'u32()
            let flags = expect stream.readNative'u8()
            if s == shapeId and key == fieldName
            {
                result.shapeFlags    = flags
                result.shapeTypeSeek = typeSeek

                // The matching fat entry holds the payload offset of the field.
                stream.setPosition(bodyStart + fatOffset + i * #sizeof(u32))
                let rel = expect stream.readNative'u32()
                result.seek = bodyStart + payloadStart + rel
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

    let field  = findTagBinV1Field(result.toSlice(), fieldName)
    var writer = ByteStream.openWrite(&result)
    writer.setPosition(field.shapeTypeSeek)
    writer.writeNative(typeCrc)
    return result
}

// An interface payload is a raw section: its byte length, then the readable object key.
func corruptTagBinInterfaceObjectKey(bytes: String, fieldName, replacement: string)->Array'u8
{
    var result: retval
    result.add(bytes.toSlice())

    let field  = findTagBinV1Field(result.toSlice(), fieldName)
    var reader = ByteStream.openRead(result.toSlice())
    reader.setPosition(field.seek + #sizeof(u64))
    let keyLength = expect reader.readVarint()
    Swag.assert(keyLength == replacement.count)

    var writer = ByteStream.openWrite(&result)
    writer.setPosition(reader.position())
    writer.writeBytes(Swag.makeSlice(replacement.buffer, replacement.count))
    return result
}

// A nested final struct is a raw signature followed by the raw byte length.
func corruptTagBinRawLen(bytes: String, fieldName: string, newLen: u64)->Array'u8
{
    var result: retval
    result.add(bytes.toSlice())

    let field  = findTagBinV1Field(result.toSlice(), fieldName)
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

// The root schema is readable in the header and prevents decoding a document through
// an unrelated type that happens to have the same shape.
#test
{
    let bytes = encodeTagBin(TagBinSchemaA{value: 42})
    Swag.assert(bytes.contains("core.test.schema-a"))

    var decoder: Serialization.Decoder'Serialization.Read.TagBin
    let decoded = catch decoder.readAll'TagBinSchemaB(bytes.toSlice()) as err
    Swag.assert(decoded == null)
    Swag.assert(err != null)
    Swag.assert(Utf8.contains(Errors.message(err), "document schema"))
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
    let patched = corruptTagBinInterfaceObjectKey(bytes, "score", "core.test.unknown-type")

    var decoder: Serialization.Decoder'Serialization.Read.TagBin
    let decoded = catch decoder.readAll'TagBinInterfacePayload(patched.toSlice()) as err
    Swag.assert(decoded == null)
    Swag.assert(err != null)
    Swag.assert(Utf8.contains(Errors.message(err), "cannot resolve interface object key"))
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
    Swag.assert((expect stream.readNative'u32()) == cast(u32) Serialization.Write.TagBinVersion1)
    Swag.assert((expect stream.readVarint()) == 0)
    Swag.assert((expect stream.readNative'u32()) == 1)

    var decoder: Serialization.Decoder'Serialization.Read.TagBin
    let decoded = expect decoder.readAll'TagBinPayload(bytes.toSlice())!
    Swag.assert(decoded.id == 17)
    Swag.assert(decoded.name == "tagbin")
    Swag.assert(assertS32Array(decoded.counts, [-8, 0, 7, 42]))
    Swag.assert(assertCompressedBlob(decoded.blob))

    Memory.delete(decoded)
}

// The value and shape flags of a version 1 stream are on-disk format, so their
// sizes and values are pinned.
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
    Swag.assert(findTagBinV1Field(bytes.toSlice(), "id").shapeFlags == 0)
    Swag.assert(findTagBinV1Field(bytes.toSlice(), "blob").shapeFlags == 1)
}

// Earlier experimental markers are rejected instead of being guessed from their layout.
#test
{
    let bytes = encodeTagBin(makeTagBinPayload())
    var patched: Array'u8
    patched.add(bytes.toSlice())

    var writer = ByteStream.openWrite(&patched)
    writer.setPosition(#sizeof(u32))
    writer.writeNative(0xFAFAFAFA'u32)

    var decoder: Serialization.Decoder'Serialization.Read.TagBin
    let decoded = catch decoder.readAll'TagBinPayload(patched.toSlice()) as err
    Swag.assert(decoded == null)
    Swag.assert(err != null)
    Swag.assert(Utf8.contains(Errors.message(err), "unsupported TagBin format version"))
}

// Field keys are compared as text. These two deliberately share one CRC32, so a
// hash-only format would silently conflate them.
#test
{
    const FirstKey  = "7MhoTAnbgQsL"
    const SecondKey = "6WMZ2VaaUabd"
    Swag.assert(Hash.Crc32.compute(FirstKey) == Hash.Crc32.compute(SecondKey))

    let bytes = encodeTagBin(TagBinReadableKeyCollision{first: 1130, second: 1138})
    Swag.assert(bytes.contains(FirstKey))
    Swag.assert(bytes.contains(SecondKey))

    var decoder: Serialization.Decoder'Serialization.Read.TagBin
    let decoded = expect decoder.readAll'TagBinReadableKeyCollision(bytes.toSlice())!
    defer Memory.delete(decoded)

    Swag.assert(decoded.first == 1130)
    Swag.assert(decoded.second == 1138)
}

func readTagBinCompressedSizes(bytes: const [..] u8, fieldName: string)->{ uncompressed: u64, compressed: u64 }
{
    let field  = findTagBinV1Field(bytes, fieldName)
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

    let field  = findTagBinV1Field(result.toSlice(), fieldName)
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
    let field  = findTagBinV1Field(patched.toSlice(), "counts")
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
    let field  = findTagBinV1Field(patched.toSlice(), "name")
    var writer = ByteStream.openWrite(&patched)
    writer.setPosition(field.seek)
    writer.writeNative(0xFF'u8)
    writer.writeNative(0x7F'u8)

    var decoder: Serialization.Decoder'Serialization.Read.TagBin
    let decoded = catch decoder.readAll'TagBinLongText(patched.toSlice()) as errln
    Swag.assert(errln != null)
    Swag.assert(decoded == null)
}
