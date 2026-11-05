#global if #command == Swag.CompilerCommand.Test
#global private

using Swag

#[Serialization.Final]
struct TagBinFinalPoint
{
    x: s16
    y: s16
}

#[Serialization.Final]
struct TagBinEmptyFinal {}

struct TagBinEmptyArray
{
    values: Array'TagBinEmptyFinal
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
    primitive:   typeinfo?
    staticArray: typeinfo?
    payload:     typeinfo?
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

#[Serialization.Final]
struct TagBinEnumRecord
{
    mode:  TagBinModeU8
    extra: [2] TagBinModeU8
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

struct TagBinEnumArrays
{
    fixed:        [3] TagBinModeU8
    values:       Array'TagBinModeU8
    records:      [2] TagBinEnumRecord
    recordValues: Array'TagBinEnumRecord
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

var g_TagBinFailedInterfaceDrops = 0

public interface ITagBinFailingScore
{
    mtd score()->s32
}

#[Serialization.TypeKey("core.test.tagbin-failing-score")]
struct TagBinFailingInterfaceProbe
{
    value: s32
}

#[Serialization.TypeKey("core.test.tagbin-earlier-score")]
struct TagBinEarlierInterfaceProbe
{
    value: s32
}

impl ITagBinFailingScore for TagBinFailingInterfaceProbe
{
    mtd impl score()->s32 => .value
}

impl ITagBinFailingScore for TagBinEarlierInterfaceProbe
{
    mtd impl score()->s32 => .value
}

impl TagBinEarlierInterfaceProbe
{
    mtd opDrop() { g_TagBinFailedInterfaceDrops += 1 }
}

impl TagBinFailingInterfaceProbe
{
    mtd opDrop() { g_TagBinFailedInterfaceDrops += 1 }
}

public impl Serialization.ISerialize for TagBinFailingInterfaceProbe
{
    mtd impl read(_: Serialization.IDecoder)->bool fail
    {
        fail SerializationError{"intentional interface decode failure"}
    }

    mtd impl write(_: Serialization.IEncoder)->bool fail => false

    mtd impl readElement(_: TypeValue, _: *void?, _: Serialization.IDecoder)->bool fail => false

    mtd impl writeElement(_: TypeValue, _: const *void?, _: Serialization.IEncoder)->bool fail => false

    mtd impl postRead(_: *void?, _: Serialization.IDecoder) fail {}
}

struct TagBinFailingInterfacePayload
{
    value: ITagBinFailingScore?
}

struct TagBinLaterFailurePayload
{
    earlier: ITagBinFailingScore?
    failing: ITagBinFailingScore?
}

public impl ITagBinScore for TagBinInterfaceProbe
{
    mtd impl score()->s32        => .value + 5
    mtd impl labelText()->string => .label.toString()
}

struct TagBinInterfacePayload
{
    score: ITagBinScore?
    other: s32
}

public struct TagBinHookPayload
{
    public
    {
        direct:   s32
        remapped: s32
        customEnum: TagBinModeU8
        bytes:    Array'u8

        #[Serialization.NoSerialize]
        postReadSeen: bool
    }
}

public impl Serialization.ISerialize for TagBinHookPayload
{
    mtd impl read(_: Serialization.IDecoder)->bool fail  => false
    mtd impl write(_: Serialization.IEncoder)->bool fail => false

    mtd impl readElement(type: TypeValue, data: *void?, decoder: Serialization.IDecoder)->bool fail
    {
        if type.name == "customEnum"
        {
            if not (try decoder.beginField(type)) do
                return true
            defer #nofail try decoder.endField(type)

            let value = try decoder.readU8()
            // Exercise the post-hook validation path with a forged closed enum.
            cast(*u8, unwrap data)[] = value == cast(u8, TagBinModeU8.Precise) ? 0xFF'u8 : value
            return true
        }

        if type.name == "remapped"
        {
            if not (try decoder.beginField(type)) do
                return true
            defer #nofail try decoder.endField(type)

            cast(*s32, unwrap data)[] = try decoder.readS32() - 6
            return true
        }

        if type.name == "bytes"
        {
            if not (try decoder.beginField(type)) do
                return true
            defer #nofail try decoder.endField(type)

            let raw = try decoder.readBufferU8(4)
            defer Memory.free(raw, 4)

            let values = cast(*Array'u8, unwrap data)
            let rawPtr = cast([*] u8, unwrap raw)
            values.clear()
            for i in 4 do
                values.add(rawPtr[3 - i])
            return true
        }

        return false
    }

    mtd impl writeElement(type: TypeValue, data: const *void?, encoder: Serialization.IEncoder)->bool fail
    {
        if type.name == "remapped"
        {
            try encoder.beginField(type)
            defer #nofail try encoder.endField(type)

            encoder.writeS32(cast(const *s32, unwrap data)[] + 10)
            return true
        }

        if type.name == "bytes"
        {
            try encoder.beginField(type)
            defer #nofail try encoder.endField(type)

            let values = cast(const *Array'u8, unwrap data)
            try encoder.writeBufferU8(values.buffer, values.count)
            return true
        }

        return false
    }

    mtd impl postRead(data: *void?, _: Serialization.IDecoder) fail
    {
        let value = cast(*TagBinHookPayload, unwrap data)
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
    mtd impl read(_: Serialization.IDecoder)->bool fail  => false
    mtd impl write(_: Serialization.IEncoder)->bool fail => false

    mtd impl readElement(_: TypeValue, _: *void?, _: Serialization.IDecoder)->bool fail => false

    mtd impl writeElement(_: TypeValue, _: const *void?, _: Serialization.IEncoder)->bool fail => false

    mtd impl postRead(data: *void?, decoder: Serialization.IDecoder) fail
    {
        let value = cast(*TagBinVersionProbe, unwrap data)
        value.seenVersion = decoder.version()
    }
}

func makeTagBinPayload()->TagBinPayload
{
    var result: #returntype

    let seed: [4] s32 = [-8, 0, 7, 42]
    result.id     = 17
    result.active = true
    result.name   = "tagbin"
    result.counts.add(seed)
    result.pair       = {x: -3, y: 11}
    result.fixed      = [9, 8, 7]
    result.finalPoint = {x: -2, y: 5}
    result.transient  = 123

    for i in 512
    {
        result.blob.add(cast(u8, (i % 4)))
    }

    return result
}

func(T) encodeTagBin(value: T)->String
{
    var buffer:  ConcatBuffer
    var encoder: Serialization.Encoder'Serialization.Write.TagBin

    expect encoder.writeAll(&buffer, value)
    return buffer.toString()
}

// Where a field of the root struct sits inside a version 1 stream, plus the location
// of its shape metadata.
struct TagBinV1Field
{
    seek:           u64     // Absolute file position of the field payload.
    fatEntrySeek:   u64     // Absolute file position of the field's relative offset.
    fatStartOffset: u32     // Relative offset of the fat table from the payload start.
    shapeFlags:     u8      // Shape flags of the field.
    shapeTypeSeek:  u64     // Absolute file position of the crcType word of its shape entry.
}

// Walks the version 1 header, the root section header, its fat and the shape
// directory to locate one field of the root struct.
func findTagBinV1Field(bytes: const [..] u8, fieldName: string)->TagBinV1Field
{
    var result: #returntype
    var stream = ByteStream.openRead(bytes)
    Swag.require((expect stream.readNative'u32()) == Serialization.Write.TagBinSignature.Root)
    Swag.require((expect stream.readNative'u32()) == cast(u32, Serialization.Write.TagBinVersion1))
    let schemaLength = expect stream.readVarint()
    Swag.require(schemaLength == 0)
    Swag.require((expect stream.readNative'u32()) == 0)
    let shapeDirOffset = expect stream.readNative'u64()
    let bodyStart      = stream.position()

    // Root struct section header.
    Swag.require((expect stream.readNative'u32()) == Serialization.Write.TagBinSignature.Version)
    discard expect stream.readNative'u32()
    Swag.require((expect stream.readNative'u32()) == Serialization.Write.TagBinSignature.Fat)
    let shapeId = expect stream.readNative'u32()
    Swag.require(shapeId != Serialization.Write.TagBinAdHocShape)
    let fatOffset    = expect stream.readNative'u64()
    let payloadStart = stream.position() - bodyStart
    result.fatStartOffset = cast(u32, fatOffset - payloadStart)

    // Walk the shape directory up to the field entry.
    stream.setPosition(bodyStart + shapeDirOffset)
    Swag.require((expect stream.readNative'u32()) == Serialization.Write.TagBinSignature.ShapeDir)
    let shapeCount = expect stream.readVarint()
    Swag.require(shapeId < shapeCount)

    for s in shapeCount
    {
        let fieldCount = expect stream.readVarint()
        for i in fieldCount
        {
            let keyLength = expect stream.readVarint()
            var key: String
            key.reserve(keyLength)
            expect stream.readBytes(unwrap key.buffer, keyLength)
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
                result.fatEntrySeek = stream.position()
                let rel = expect stream.readNative'u32()
                result.seek = bodyStart + payloadStart + rel
                return result
            }
        }
    }

    Swag.require(false)
    return result
}

func corruptTagBinFieldType(bytes: String, fieldName: string, typeCrc: u32)->Array'u8
{
    var result: #returntype
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
    var result: #returntype
    result.add(bytes.toSlice())

    let field  = findTagBinV1Field(result.toSlice(), fieldName)
    var reader = ByteStream.openRead(result.toSlice())
    reader.setPosition(field.seek + #sizeof(u64))
    let keyLength = expect reader.readVarint()
    Swag.require(keyLength == replacement.count)

    var writer = ByteStream.openWrite(&result)
    writer.setPosition(reader.position())
    writer.writeBytes(cast(const [..] u8, replacement))
    return result
}

// A nested final struct is a raw signature followed by the raw byte length.
func corruptTagBinRawLen(bytes: String, fieldName: string, newLen: u64)->Array'u8
{
    var result: #returntype
    result.add(bytes.toSlice())

    let field  = findTagBinV1Field(result.toSlice(), fieldName)
    var writer = ByteStream.openWrite(&result)
    writer.setPosition(field.seek + #sizeof(u32))
    writer.writeNative(newLen)
    return result
}

func corruptTagBinRootFatSeek(bytes: String, fatSeek: u64)->Array'u8
{
    var result: #returntype
    result.add(bytes.toSlice())

    var stream = ByteStream.openRead(result.toSlice())
    discard expect stream.readNative'u32()
    discard expect stream.readNative'u32()
    let schemaLength = expect stream.readVarint()
    stream.advance(schemaLength)
    discard expect stream.readNative'u32()
    discard expect stream.readNative'u64()
    discard expect stream.readNative'u32()     // Root section version signature.
    discard expect stream.readNative'u32()     // Struct version.
    discard expect stream.readNative'u32()     // Fat signature.
    discard expect stream.readNative'u32()     // Shape id.
    let fatSeekPosition = stream.position()

    var writer = ByteStream.openWrite(&result)
    writer.setPosition(fatSeekPosition)
    writer.writeNative(fatSeek)
    return result
}

func corruptTagBinFieldOffset(bytes: String, fieldName: string, offset: u32)->Array'u8
{
    var result: #returntype
    result.add(bytes.toSlice())

    let field  = findTagBinV1Field(result.toSlice(), fieldName)
    var writer = ByteStream.openWrite(&result)
    writer.setPosition(field.fatEntrySeek)
    writer.writeNative(offset)
    return result
}

func assertCompressedBlob(values: Array'u8)->bool
{
    if values.count != 512 do
        return false

    for index in values.count
    {
        if values[index] != cast(u8, (index % 4)) do
            return false
    }

    return true
}

func releaseTagBinInterface(value: *(ITagBinScore?))
{
    let runtime = cast(*Swag.Interface, value)
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

    Swag.require(not writer.isTextual())
    Swag.require(not reader.isTextual())
    Swag.require(raw)
    Swag.require(sizeof == #sizeof(TagBinFinalPoint))
    Swag.require(Reflection.hasAttribute(#typeof(TagBinFinalPoint), Serialization.Final))
    Swag.require(not Reflection.hasAttribute(#typeof(TagBinFinalPoint), Serialization.NoSerialize))

    let blobField = Reflection.findField(#typeof(TagBinPayload), "blob")
    Swag.require(blobField != null)
    Swag.require(Reflection.hasAttribute(blobField, Serialization.Compress))
    Swag.require(not Reflection.hasAttribute(blobField, Serialization.NoSerialize))
}

#test
{
    let oldPoint = TagBinFieldWisePoint{x: -9, y: 12}
    let oldBytes = encodeTagBin(oldPoint)

    var finalDecoder: Serialization.Decoder'Serialization.Read.TagBin
    let finalPoint = expect finalDecoder.readAll'TagBinFinalMigrationPoint(oldBytes.toSlice())
    defer Memory.delete(finalPoint)
    Swag.require(finalPoint.x == -9)
    Swag.require(finalPoint.y == 12)

    let rawBytes = encodeTagBin(TagBinFinalMigrationPoint{x: 3, y: 4})

    var fieldWiseDecoder: Serialization.Decoder'Serialization.Read.TagBin
    var errfwOutcome:     Swag.Error
    catch CoreTests.readAndDelete'(TagBinFieldWisePoint, Serialization.Read.TagBin)(&fieldWiseDecoder, rawBytes.toSlice()) as errfwOutcome
    let errfw = errfwOutcome.value()
    Swag.require(errfw != null)
}

#test
{
    let payload = makeTagBinPayload()
    Swag.require(payload.finalPoint.x == -2)
    Swag.require(payload.finalPoint.y == 5)

    var buffer:  ConcatBuffer
    var encoder: Serialization.Encoder'Serialization.Write.TagBin
    expect encoder.writeAll(&buffer, payload)
    let bytes     = buffer.toString()
    let byteSlice = bytes.toSlice()

    var decoder: Serialization.Decoder'Serialization.Read.TagBin
    let decoded = expect decoder.readAll'TagBinPayload(byteSlice)
    defer Memory.delete(decoded)
    Swag.require(decoded.id == 17)
    Swag.require(decoded.active)
    Swag.require(decoded.name == "tagbin")
    decoded.name = "decoded"
    Swag.require(decoded.name == "decoded")
    Swag.require(Slice.equals(decoded.counts.toSlice(), [-8, 0, 7, 42]))
    Swag.require(decoded.pair.x == -3)
    Swag.require(decoded.pair.y == 11)
    Swag.require(decoded.fixed[0] == 9)
    Swag.require(decoded.fixed[1] == 8)
    Swag.require(decoded.fixed[2] == 7)
    Swag.require(decoded.finalPoint.x == -2)
    Swag.require(decoded.finalPoint.y == 5)
    Swag.require(assertCompressedBlob(decoded.blob))
    Swag.require(decoded.transient == 0)

    // A stream produced and consumed by the same types decodes without a single
    // diagnostic: this is the positional fast path.
    Swag.require(decoder.serializer.diag.fieldErrors == 0)
    Swag.require(decoder.serializer.diag.droppedStreamFields == 0)
    Swag.require(decoder.serializer.diag.unknownTypes == 0)
    Swag.require(decoder.serializer.diag.recoveredFields == 0)
    Swag.require(decoder.serializer.diag.corruptPayloads == 0)
}

// The root schema is readable in the header and prevents decoding a document through
// an unrelated type that happens to have the same shape.
#test
{
    let bytes = encodeTagBin(TagBinSchemaA{value: 42})
    Swag.require(bytes.contains("core.test.schema-a"))

    var decoder:    Serialization.Decoder'Serialization.Read.TagBin
    var errOutcome: Swag.Error
    catch CoreTests.readAndDelete'(TagBinSchemaB, Serialization.Read.TagBin)(&decoder, bytes.toSlice()) as errOutcome
    let err = errOutcome.value()
    Swag.require(err != null)
    Swag.require(Utf8.contains(Errors.message(err), "document schema"))
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
    var errstOutcome:  Swag.Error
    catch CoreTests.readAndDelete'(TagBinPayload, Serialization.Read.TagBin)(&strictDecoder, patched.toSlice()) as errstOutcome
    let errst = errstOutcome.value()
    Swag.require(errst != null)

    var decoder: Serialization.Decoder'Serialization.Read.TagBin
    decoder.flags |= .IgnoreStructFieldError
    let decoded = expect decoder.readAll'TagBinPayload(patched.toSlice())
    defer Memory.delete(decoded)
    Swag.require(decoded.id == 0)
    Swag.require(decoded.name == "tagbin")
    Swag.require(assertCompressedBlob(decoded.blob))
    Swag.require(decoder.serializer.diag.unknownTypes >= 1)
    Swag.require(decoder.serializer.diag.fieldErrors >= 1)
}

#test
{
    let payload = makeTagBinPayload()
    let bytes   = encodeTagBin(payload)

    var decoder: Serialization.Decoder'Serialization.Read.TagBin
    decoder.serializer.ignoreElements.add("name")
    let decoded = expect decoder.readAll'TagBinPayload(bytes.toSlice())
    defer Memory.delete(decoded)
    Swag.require(decoded.id == 17)
    Swag.require(decoded.name.isNullOrEmpty())
    Swag.require(assertCompressedBlob(decoded.blob))
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
    let decoded = expect decoder.readAll'TagBinCurrentPayload(bytes.toSlice())
    defer Memory.delete(decoded)
    Swag.require(decoded.renamed == -6)
    Swag.require(decoded.value == 21)
    Swag.require(decoded.numbers[0] == 4)
    Swag.require(decoded.numbers[1] == 5)
    Swag.require(decoded.numbers[2] == 6)
    Swag.require(decoded.single == 33)

    // The stream field 'removed' is data the current type no longer requests, and the
    // diagnostics say so.
    Swag.require(decoder.serializer.diag.droppedStreamFields == 1)
    Swag.require(decoder.serializer.diag.fieldErrors == 0)
}

#test
{
    let future = TagBinFuturePayload{value: 44}
    let bytes  = encodeTagBin(future)

    var strictDecoder: Serialization.Decoder'Serialization.Read.TagBin
    var errsvOutcome:  Swag.Error
    catch CoreTests.readAndDelete'(TagBinOlderPayload, Serialization.Read.TagBin)(&strictDecoder, bytes.toSlice()) as errsvOutcome
    let errsv = errsvOutcome.value()
    Swag.require(errsv != null)

    var forwardDecoder: Serialization.Decoder'Serialization.Read.TagBin
    forwardDecoder.serializer.options.tryForward = true
    let forwardValue = expect forwardDecoder.readAll'TagBinOlderPayload(bytes.toSlice())
    defer Memory.delete(forwardValue)
    Swag.require(forwardValue.value == 44)
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
    let decoded = expect decoder.readAll'TagBinTypeInfoPayload(bytes.toSlice())
    defer Memory.delete(decoded)
    Swag.require(decoded.primitive == s32)
    Swag.require(decoded.staticArray == #typeof(#type [3] u8))
    Swag.require(decoded.payload == TagBinPayload)
}

#test
{
    var concrete = TagBinInterfaceProbe{value: 32}
    concrete.label = "iface"

    let payload = TagBinInterfacePayload{
        score: cast(ITagBinScore, concrete),
        other: -11}

    Reflection.registerType(#typeof(TagBinInterfaceProbe))
    Reflection.registerType(#typeof(TagBinInterfacePayload))
    Swag.require(Reflection.hasInterface(#typeof(TagBinInterfaceProbe), ITagBinScore))
    Swag.require(payload.score!.score() == 37)

    let bytes = encodeTagBin(payload)

    var decoder: Serialization.Decoder'Serialization.Read.TagBin
    let decoded = expect decoder.readAll'TagBinInterfacePayload(bytes.toSlice())
    defer
    {
        releaseTagBinInterface(&decoded.score)
        Memory.delete(decoded)
    }

    Swag.require(decoded.other == -11)
    let score = unwrap decoded.score
    Swag.require(score.score() == 37)
    Swag.require(score.labelText() == "iface")
}

#test
{
    var concrete = TagBinFailingInterfaceProbe{value: 23}
    let payload  = TagBinFailingInterfacePayload{value: cast(ITagBinFailingScore, concrete)}

    Reflection.registerType(#typeof(TagBinFailingInterfaceProbe))
    Reflection.registerType(#typeof(TagBinFailingInterfacePayload))

    let bytes = encodeTagBin(payload)
    g_TagBinFailedInterfaceDrops = 0

    var decoder:    Serialization.Decoder'Serialization.Read.TagBin
    var errOutcome: Swag.Error
    discard catch decoder.readAll'TagBinFailingInterfacePayload(bytes.toSlice()) as errOutcome
    let err = errOutcome.value()

    Swag.require(err != null)
    Swag.require(g_TagBinFailedInterfaceDrops == 1)
}

#test
{
    var earlier = TagBinEarlierInterfaceProbe{value: 11}
    var failing = TagBinFailingInterfaceProbe{value: 23}
    let payload = TagBinLaterFailurePayload{
        earlier: cast(ITagBinFailingScore, earlier),
        failing: cast(ITagBinFailingScore, failing)}

    Reflection.registerType(#typeof(TagBinEarlierInterfaceProbe))
    Reflection.registerType(#typeof(TagBinFailingInterfaceProbe))
    Reflection.registerType(#typeof(TagBinLaterFailurePayload))

    let bytes = encodeTagBin(payload)
    g_TagBinFailedInterfaceDrops = 0

    var decoder:    Serialization.Decoder'Serialization.Read.TagBin
    var errOutcome: Swag.Error
    discard catch decoder.readAll'TagBinLaterFailurePayload(bytes.toSlice()) as errOutcome
    let err = errOutcome.value()

    Swag.require(err != null)
    Swag.require(g_TagBinFailedInterfaceDrops == 2)
}

#test
{
    var concrete = TagBinInterfaceProbe{value: 41}
    concrete.label = "inferred"

    let payload = TagBinInterfacePayload{
        score: cast(ITagBinScore, concrete),
        other: 12}

    let bytes   = encodeTagBin(payload)
    let patched = corruptTagBinInterfaceObjectKey(bytes, "score", "core.test.unknown-type")

    var decoder:    Serialization.Decoder'Serialization.Read.TagBin
    var errOutcome: Swag.Error
    catch CoreTests.readAndDelete'(TagBinInterfacePayload, Serialization.Read.TagBin)(&decoder, patched.toSlice()) as errOutcome
    let err = errOutcome.value()
    Swag.require(err != null)
    Swag.require(Utf8.contains(Errors.message(err), "cannot resolve interface object key"))
}

#test
{
    let payload = TagBinInterfacePayload{other: 19}
    let bytes   = encodeTagBin(payload)

    var decoder: Serialization.Decoder'Serialization.Read.TagBin
    let decoded = expect decoder.readAll'TagBinInterfacePayload(bytes.toSlice())
    defer Memory.delete(decoded)
    Swag.require(decoded.other == 19)

    let runtime = cast(*Swag.Interface, &decoded.score)
    Swag.require(runtime.obj == null)
    Swag.require(runtime.itable == null)
}

#test
{
    var payload:  TagBinHookPayload
    let rawBytes: [4] u8 = [1, 3, 5, 7]

    payload.direct   = 20
    payload.remapped = 30
    payload.bytes.add(rawBytes)

    Reflection.registerType(#typeof(TagBinHookPayload))
    Swag.require(Reflection.hasInterface(#typeof(TagBinHookPayload), Serialization.ISerialize))
    let hookItf: Serialization.ISerialize = &payload
    Swag.require(hookItf != null)

    let bytes = encodeTagBin(payload)

    var decoder: Serialization.Decoder'Serialization.Read.TagBin
    let decoded = expect decoder.readAll'TagBinHookPayload(bytes.toSlice())
    defer Memory.delete(decoded)
    Swag.require(decoded.direct == 21)
    Swag.require(decoded.remapped == 34)
    Swag.require(decoded.customEnum == .Off)
    Swag.require(decoded.bytes.count == 4)
    Swag.require(decoded.bytes[0] == 7)
    Swag.require(decoded.bytes[1] == 5)
    Swag.require(decoded.bytes[2] == 3)
    Swag.require(decoded.bytes[3] == 1)
    Swag.require(decoded.postReadSeen)
}

#test
{
    var payload: TagBinHookPayload
    payload.customEnum = .Precise

    Reflection.registerType(#typeof(TagBinHookPayload))
    let bytes = encodeTagBin(payload)

    var decoder: Serialization.Decoder'Serialization.Read.TagBin
    var errOutcome: Swag.Error
    discard catch decoder.readAll'TagBinHookPayload(bytes.toSlice()) as errOutcome
    let err = errOutcome.value()
    Swag.require(err != null)
    Swag.require(Utf8.contains(Errors.message(err), "not a member of the requested enum"))
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
    source.nested = {left: -5, right: 23}

    Reflection.registerType(#typeof(TagBinConversionSource))
    Swag.require(Reflection.typeFromCrc(#typeof(#type [3] u8).crc) == #typeof(#type [3] u8))

    let bytes = encodeTagBin(source)

    var decoder: Serialization.Decoder'Serialization.Read.TagBin
    let decoded = expect decoder.readAll'TagBinConversionTarget(bytes.toSlice())
    defer Memory.delete(decoded)
    Swag.require(decoded.small == -123)
    Swag.require(decoded.floating == 1.5)
    Swag.require(decoded.staticToStatic[0] == 5)
    Swag.require(decoded.staticToStatic[1] == 6)
    Swag.require(decoded.staticToStatic[2] == 7)
    Swag.require(decoded.staticToStatic[3] == 0)
    Swag.require(decoded.staticToStatic[4] == 0)
    Swag.require(Slice.equals(decoded.staticToArray.toSlice(), [-7, 8, 19]))
    Swag.require(decoded.arrayToStatic[0] == -2)
    Swag.require(decoded.arrayToStatic[1] == 4)
    Swag.require(decoded.arrayToStatic[2] == 9)
    Swag.require(decoded.arrayToStatic[3] == 0)
    Swag.require(decoded.singleToStatic[0] == 42)
    Swag.require(decoded.singleToStatic[1] == 0)
    Swag.require(decoded.singleToStatic[2] == 0)
    Swag.require(Slice.equals(decoded.singleToArray.toSlice(), [12'u32]))
    Swag.require(decoded.arrayToSingle == 55)
    Swag.require(decoded.nested.left == -5)
    Swag.require(decoded.nested.right == 23)
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
    let decoded = expect decoder.readAll'TagBinEnumTarget(bytes.toSlice())
    defer Memory.delete(decoded)
    Swag.require(decoded.mode == .Precise)
    Swag.require(decoded.tail == -9)
}

// Raw enum arrays still reject values that are not declared by a closed enum.
#test
{
    var source: TagBinEnumArrays
    source.fixed = [.Off, .Fast, .Precise]
    source.values.add([TagBinModeU8.Off, .Fast, .Precise])
    source.records[0] = {mode: .Off, extra: [.Fast, .Precise]}
    source.records[1] = {mode: .Fast, extra: [.Off, .Precise]}
    source.recordValues.add(source.records)
    let bytes = encodeTagBin(source)

    for fieldName in ["fixed", "values", "records", "recordValues"]
    {
        var patched: Array'u8
        patched.add(bytes.toSlice())
        let field = findTagBinV1Field(patched.toSlice(), fieldName)
        var reader = ByteStream.openRead(patched.toSlice())
        reader.setPosition(field.seek)
        Swag.require((expect reader.readNative'u32()) == Serialization.Write.TagBinSignature.Sequence)
        discard expect reader.readVarint()
        Swag.require((expect reader.readNative'u32()) == Serialization.Write.TagBinSignature.Raw)
        discard expect reader.readVarint()
        let valuesSeek = reader.position()

        var writer = ByteStream.openWrite(&patched)
        writer.setPosition(valuesSeek + 1)
        writer.writeNative(0x7F'u8)

        var decoder: Serialization.Decoder'Serialization.Read.TagBin
        var errorOutcome: Swag.Error
        catch CoreTests.readAndDelete'(TagBinEnumArrays, Serialization.Read.TagBin)(&decoder, patched.toSlice()) as errorOutcome
        Swag.require(errorOutcome.value() != null)
    }
}

// The stream version of a struct is visible from user code during the decode, which is
// what a deliberate data migration keys on.
#test
{
    var probe: TagBinVersionProbe
    probe.value = 3

    let bytes = encodeTagBin(probe)

    var decoder: Serialization.Decoder'Serialization.Read.TagBin
    let decoded = expect decoder.readAll'TagBinVersionProbe(bytes.toSlice())
    defer Memory.delete(decoded)
    Swag.require(decoded.value == 3)
    Swag.require(decoded.seenVersion == 5)
}

// Compressing the whole stream is a writer option: the header says so, and the decode
// is unchanged for the caller.
#test
{
    let payload = makeTagBinPayload()

    var buffer:  ConcatBuffer
    var encoder: Serialization.Encoder'Serialization.Write.TagBin
    encoder.serializer.compressStream = true
    expect encoder.writeAll(&buffer, payload)
    let bytes = buffer.toString()

    var stream = ByteStream.openRead(bytes.toSlice())
    discard expect stream.readNative'u32()
    Swag.require((expect stream.readNative'u32()) == cast(u32, Serialization.Write.TagBinVersion1))
    Swag.require((expect stream.readVarint()) == 0)
    Swag.require((expect stream.readNative'u32()) == 1)

    var decoder: Serialization.Decoder'Serialization.Read.TagBin
    let decoded = expect decoder.readAll'TagBinPayload(bytes.toSlice())
    defer Memory.delete(decoded)
    Swag.require(decoded.id == 17)
    Swag.require(decoded.name == "tagbin")
    Swag.require(Slice.equals(decoded.counts.toSlice(), [-8, 0, 7, 42]))
    Swag.require(assertCompressedBlob(decoded.blob))
}

// The value and shape flags of a version 1 stream are on-disk format, so their
// sizes and values are pinned.
#test
{
    Swag.require(#sizeof(Serialization.Write.TagBinValueFlags) == 1)
    Swag.require(cast(u8, Serialization.Write.TagBinValueFlags.None) == 1)
    Swag.require(cast(u8, Serialization.Write.TagBinValueFlags.Compressed) == 2)
    Swag.require(#sizeof(Serialization.Write.TagBinShapeFlags) == 1)
    Swag.require(cast(u8, Serialization.Write.TagBinShapeFlags.Zero) == 0)
    Swag.require(cast(u8, Serialization.Write.TagBinShapeFlags.Compressed) == 1)

    let payload = makeTagBinPayload()
    let bytes   = encodeTagBin(payload)
    Swag.require(findTagBinV1Field(bytes.toSlice(), "id").shapeFlags == 0)
    Swag.require(findTagBinV1Field(bytes.toSlice(), "blob").shapeFlags == 1)
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

    var decoder:    Serialization.Decoder'Serialization.Read.TagBin
    var errOutcome: Swag.Error
    catch CoreTests.readAndDelete'(TagBinPayload, Serialization.Read.TagBin)(&decoder, patched.toSlice()) as errOutcome
    let err = errOutcome.value()
    Swag.require(err != null)
    Swag.require(Utf8.contains(Errors.message(err), "unsupported TagBin format version"))
}

// Field keys are compared as text. These two deliberately share one CRC32, so a
// hash-only format would silently conflate them.
#test
{
    const FirstKey  = "7MhoTAnbgQsL"
    const SecondKey = "6WMZ2VaaUabd"
    Swag.require(Hash.Crc32.compute(FirstKey) == Hash.Crc32.compute(SecondKey))

    let bytes = encodeTagBin(TagBinReadableKeyCollision{first: 1130, second: 1138})
    Swag.require(bytes.contains(FirstKey))
    Swag.require(bytes.contains(SecondKey))

    var decoder: Serialization.Decoder'Serialization.Read.TagBin
    let decoded = expect decoder.readAll'TagBinReadableKeyCollision(bytes.toSlice())
    defer Memory.delete(decoded)

    Swag.require(decoded.first == 1130)
    Swag.require(decoded.second == 1138)
}

#test
{
    var payload: TagBinEmptyArray
    payload.values.resize(128)

    let bytes   = encodeTagBin(payload)
    var decoder: Serialization.Decoder'Serialization.Read.TagBin
    let decoded = expect decoder.readAll'TagBinEmptyArray(bytes.toSlice())
    defer Memory.delete(decoded)

    Swag.require(decoded.values.count == 128)
}

func readTagBinCompressedSizes(bytes: const [..] u8, fieldName: string)->{ uncompressed: u64, compressed: u64 }
{
    let field  = findTagBinV1Field(bytes, fieldName)
    var stream = ByteStream.openRead(bytes)
    stream.setPosition(field.seek)

    var result: #returntype
    result.uncompressed = expect stream.readNative'u64()
    result.compressed   = expect stream.readNative'u64()
    return result
}

func corruptTagBinCompressedSizes(bytes: String, fieldName: string, uncompressed, compressed: u64)->Array'u8
{
    var result: #returntype
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

    var decoder:      Serialization.Decoder'Serialization.Read.TagBin
    var err24Outcome: Swag.Error
    catch CoreTests.readAndDelete'(TagBinPayload, Serialization.Read.TagBin)(&decoder, patched.toSlice()) as err24Outcome
    let err24 = err24Outcome.value()
    Swag.require(err24 != null)
}

// The announced sizes must describe the payload truthfully: a lying uncompressed size
// is refused instead of decoding to something else than what was written.
#test
{
    let payload = makeTagBinPayload()
    let bytes   = encodeTagBin(payload)
    let sizes   = readTagBinCompressedSizes(bytes.toSlice(), "blob")
    let patched = corruptTagBinCompressedSizes(bytes, "blob", sizes.uncompressed + 1, sizes.compressed)

    var decoder:      Serialization.Decoder'Serialization.Read.TagBin
    var errszOutcome: Swag.Error
    catch CoreTests.readAndDelete'(TagBinPayload, Serialization.Read.TagBin)(&decoder, patched.toSlice()) as errszOutcome
    let errsz = errszOutcome.value()
    Swag.require(errsz != null)
}

// A compressed field cannot announce an expansion beyond Deflate's format bound.
#test
{
    let payload = makeTagBinPayload()
    let bytes   = encodeTagBin(payload)
    let sizes   = readTagBinCompressedSizes(bytes.toSlice(), "blob")
    let patched = corruptTagBinCompressedSizes(bytes, "blob", Swag.U64.Max, sizes.compressed)

    var decoder:      Serialization.Decoder'Serialization.Read.TagBin
    var errorOutcome: Swag.Error
    catch CoreTests.readAndDelete'(TagBinPayload, Serialization.Read.TagBin)(&decoder, patched.toSlice()) as errorOutcome
    Swag.require(errorOutcome.value() != null)
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

    let decoded = expect decoder.readAll'TagBinPayload(patched.toSlice())
    defer Memory.delete(decoded)
    Swag.require(decoded.id == 17)
    Swag.require(decoded.name == "tagbin")
    Swag.require(Slice.equals(decoded.counts.toSlice(), [-8, 0, 7, 42]))
    Swag.require(decoded.blob.isEmpty())
    Swag.require(decoder.serializer.diag.fieldErrors >= 1)
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
    var errrlOutcome:  Swag.Error
    catch CoreTests.readAndDelete'(TagBinPayload, Serialization.Read.TagBin)(&strictDecoder, patched.toSlice()) as errrlOutcome
    let errrl = errrlOutcome.value()
    Swag.require(errrl != null)

    var decoder: Serialization.Decoder'Serialization.Read.TagBin
    decoder.flags |= .IgnoreStructFieldError
    let decoded = expect decoder.readAll'TagBinPayload(patched.toSlice())
    defer Memory.delete(decoded)
    Swag.require(decoded.id == 17)
    Swag.require(decoded.name == "tagbin")
    Swag.require(Slice.equals(decoded.counts.toSlice(), [-8, 0, 7, 42]))
    Swag.require(decoder.serializer.diag.corruptPayloads >= 1)
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

    var decoder:      Serialization.Decoder'Serialization.Read.TagBin
    var errsqOutcome: Swag.Error
    catch CoreTests.readAndDelete'(TagBinPayload, Serialization.Read.TagBin)(&decoder, patched.toSlice()) as errsqOutcome
    let errsq = errsqOutcome.value()
    Swag.require(errsq != null)
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

    var decoder:      Serialization.Decoder'Serialization.Read.TagBin
    var errlnOutcome: Swag.Error
    catch CoreTests.readAndDelete'(TagBinLongText, Serialization.Read.TagBin)(&decoder, patched.toSlice()) as errlnOutcome
    let errln = errlnOutcome.value()
    Swag.require(errln != null)
}

// A fat offset near U64.Max is rejected without wrapping the computed table end.
#test
{
    let payload = makeTagBinPayload()
    let bytes   = encodeTagBin(payload)
    let patched = corruptTagBinRootFatSeek(bytes, Swag.U64.Max)

    var decoder:      Serialization.Decoder'Serialization.Read.TagBin
    var errorOutcome: Swag.Error
    catch CoreTests.readAndDelete'(TagBinPayload, Serialization.Read.TagBin)(&decoder, patched.toSlice()) as errorOutcome
    Swag.require(errorOutcome.value() != null)
}

// An indexed shaped field offset cannot point into the fat table itself.
#test
{
    let payload = makeTagBinPayload()
    let bytes   = encodeTagBin(payload)
    let field   = findTagBinV1Field(bytes.toSlice(), "id")
    let patched = corruptTagBinFieldOffset(bytes, "id", field.fatStartOffset)

    var decoder: Serialization.Decoder'Serialization.Read.TagBin
    decoder.serializer.ignoreElements.add("name")
    var errorOutcome: Swag.Error
    catch CoreTests.readAndDelete'(TagBinPayload, Serialization.Read.TagBin)(&decoder, patched.toSlice()) as errorOutcome
    Swag.require(errorOutcome.value() != null)
}
