#global if #command == Swag.CompilerCommand.Test
#global private

using Swag

struct JsonPair
{
    x: s32
    y: s32
}

struct JsonPayload
{
    id:     u32
    active: bool
    name:   String
    counts: Array's32
    pair:   JsonPair
    fixed:  [3] u8

    #[Serialization.NoSerialize]
    transient: s32
}

struct JsonStringPayload
{
    text: String
}

struct JsonFloatPayload
{
    value: f64
}

struct JsonF32Payload
{
    value: f32
}

enum JsonStringState: string
{
    Idle = "idle"
    Busy = "busy"
}

enum JsonArrayState: const [3] u32
{
    Idle = [1, 2, 3]
    Busy = [4, 5, 6]
}

struct JsonStringEnumPayload
{
    state: JsonStringState = .Idle
}

struct JsonArrayEnumPayload
{
    state: JsonArrayState
}

struct JsonKeyPayload
{
    #[Serialization.Key("wireName")]
    sourceName: u32
}

func makeJsonPayload()->JsonPayload
{
    var result: #returntype

    let seed: [3] s32 = [-1, 0, 4]
    result.id     = 7
    result.active = true
    result.name   = "core"
    result.counts.add(seed)
    result.pair      = {x: 3, y: -2}
    result.fixed     = [1, 2, 3]
    result.transient = 99
    return result
}

func assertJsonPayload(value: JsonPayload)->bool
{
    return value.id == 7 and
           value.active and
           value.name == "core" and
           Slice.equals(value.counts.toSlice(), [-1, 0, 4]) and
           value.pair.x == 3 and
           value.pair.y == -2 and
           value.fixed[0] == 1 and
           value.fixed[1] == 2 and
           value.fixed[2] == 3
}

#test
{
    let payload = makeJsonPayload()

    var encoder: Serialization.Encoder'Serialization.Write.Json
    encoder.serializer.options.saveBlanks = false

    var buffer: ConcatBuffer
    expect encoder.writeAll(&buffer, payload)
    let json = buffer.toString()
    Swag.require(json == "{\"id\":7,\"active\":true,\"name\":\"core\",\"counts\":[-1,0,4],\"pair\":{\"x\":3,\"y\":-2},\"fixed\":[1,2,3]}")
    Swag.require(json.indexOf("transient") == Swag.U64.Max)

    var decoder: Serialization.Decoder'Serialization.Read.Json
    let decoded = expect decoder.readAll'JsonPayload(json.toSlice())
    #assert(#typeof(decoded) == *JsonPayload)
    defer Memory.delete(decoded)
    Swag.require(assertJsonPayload(decoded[]))
    Swag.require(decoded.transient == 0)
}

#test
{
    let validInput: string = "{\"state\":[4,5,6]}"
    var validDecoder: Serialization.Decoder'Serialization.Read.Json
    let decoded = expect validDecoder.readAll'JsonArrayEnumPayload(cast(const [..] u8, validInput))
    defer Memory.delete(decoded)
    Swag.require(decoded.state == .Busy)

    let invalidInput: string = "{\"state\":[4,5,7]}"
    var invalidDecoder: Serialization.Decoder'Serialization.Read.Json
    var errorOutcome: Swag.Error
    catch CoreTests.readAndDelete'(JsonArrayEnumPayload, Serialization.Read.Json)(&invalidDecoder, cast(const [..] u8, invalidInput)) as errorOutcome
    Swag.require(errorOutcome.value() != null)
}

#test
{
    let validInput: string = "{\"state\":\"busy\"}"
    var validDecoder: Serialization.Decoder'Serialization.Read.Json
    let decoded = expect validDecoder.readAll'JsonStringEnumPayload(cast(const [..] u8, validInput))
    defer Memory.delete(decoded)
    Swag.require(decoded.state == .Busy)

    let input = "{\"state\":\"missing\"}"
    var decoder: Serialization.Decoder'Serialization.Read.Json
    var errorOutcome: Swag.Error
    catch CoreTests.readAndDelete'(JsonStringEnumPayload, Serialization.Read.Json)(&decoder, cast(const [..] u8, input)) as errorOutcome
    Swag.require(errorOutcome.value() != null)
}

#test
{
    let source:  String = "{\"wireName\":42}"
    var decoder: Serialization.Decoder'Serialization.Read.Json
    let decoded         = expect decoder.readAll'JsonKeyPayload(source.toSlice())
    defer Memory.delete(decoded)
    Swag.require(decoded.sourceName == 42)
}

#test
{
    let payload = makeJsonPayload()

    var encoder: Serialization.Encoder'Serialization.Write.Json
    encoder.serializer.options.saveBlanks  = true
    encoder.serializer.options.indentLevel = 2

    var buffer: ConcatBuffer
    expect encoder.writeAll(&buffer, payload)
    let json = buffer.toString()
    Swag.require(json == "{\n  \"id\": 7,\n  \"active\": true,\n  \"name\": \"core\",\n  \"counts\": [\n    -1,\n    0,\n    4\n  ],\n  \"pair\": {\n    \"x\": 3,\n    \"y\": -2\n  },\n  \"fixed\": [\n    1,\n    2,\n    3\n  ]\n}")
}

#test
{
    let json: String = "{\n  \"id\": 8,\n  \"active\": false,\n  \"name\": null,\n  \"counts\": [9, 8],\n  \"pair\": {\"x\": -1, \"y\": 2},\n  \"fixed\": [5, 6, 7]\n}"

    var decoder: Serialization.Decoder'Serialization.Read.Json
    let decoded = expect decoder.readAll'JsonPayload(json.toSlice())
    defer Memory.delete(decoded)
    Swag.require(decoded.id == 8)
    Swag.require(not decoded.active)
    Swag.require(decoded.name.isNullOrEmpty())
    Swag.require(Slice.equals(decoded.counts.toSlice(), [9, 8]))
    Swag.require(decoded.pair.x == -1)
    Swag.require(decoded.pair.y == 2)
    Swag.require(decoded.fixed[0] == 5)
    Swag.require(decoded.fixed[1] == 6)
    Swag.require(decoded.fixed[2] == 7)
    Swag.require(decoded.transient == 0)
}

#test
{
    let interoperable: String = "{\"unknown\":{\"nested\":[true,null,{\"x\":1}]},\"fixed\":[1,2,3],\"name\":\"core\",\"pair\":{\"y\":-2,\"ignored\":9,\"x\":3},\"id\":7,\"active\":true,\"counts\":[-1,0,4]}"

    var decoder: Serialization.Decoder'Serialization.Read.Json
    let decoded = expect decoder.readAll'JsonPayload(interoperable.toSlice())
    defer Memory.delete(decoded)
    Swag.require(assertJsonPayload(decoded[]))

    let missing: String = "{\"id\":12}"
    let partial         = expect decoder.readAll'JsonPayload(missing.toSlice())
    defer Memory.delete(partial)
    Swag.require(partial.id == 12)
    Swag.require(not partial.active)
    Swag.require(partial.name.isNullOrEmpty())
    Swag.require(partial.counts.isEmpty())
}

#test
{
    var payload = JsonFloatPayload{value: cast #bit (f64, 0x7FF8000000000000'u64)}
    var encoder: Serialization.Encoder'Serialization.Write.Json
    var buffer:  ConcatBuffer
    expect encoder.writeAll(&buffer, payload)
    Swag.require(buffer.toString() == "{\"value\":null}")
}

#test
{
    const InvalidFloats = [
        "{\"value\":1e39}",
        "{\"value\":-1e39}"]
    for input in InvalidFloats
    {
        var decoder:    Serialization.Decoder'Serialization.Read.Json
        var errOutcome: Swag.Error
        catch CoreTests.readAndDelete'(JsonF32Payload, Serialization.Read.Json)(&decoder, cast(const [..] u8, input)) as errOutcome
        Swag.require(errOutcome.value() != null)
    }

    const InvalidF64 = ["{\"value\":1e309}", "{\"value\":-1e309}"]
    for input in InvalidF64
    {
        var decoder:    Serialization.Decoder'Serialization.Read.Json
        var errOutcome: Swag.Error
        catch CoreTests.readAndDelete'(JsonFloatPayload, Serialization.Read.Json)(&decoder, cast(const [..] u8, input)) as errOutcome
        Swag.require(errOutcome.value() != null)
    }
}

#test
{
    var payload: JsonStringPayload
    payload.text = "quote=\" slash=\\ controls=\b\f\n\r\t caf\u00E9 \U0001F642"

    var encoder: Serialization.Encoder'Serialization.Write.Json
    var buffer:  ConcatBuffer
    expect encoder.writeAll(&buffer, payload)
    Swag.require(buffer.toString() == "{\"text\":\"quote=\\\" slash=\\\\ controls=\\b\\f\\n\\r\\t caf\u00E9 \U0001F642\"}")

    var decoder: Serialization.Decoder'Serialization.Read.Json
    let decoded = expect decoder.readAll'JsonStringPayload(unwrap buffer.toSlice())
    defer Memory.delete(decoded)
    Swag.require(decoded.text == payload.text)

    let escaped: String = #raw """{"text":"A\u00E9\uD83D\uDE42"}"""
    let unicode = expect decoder.readAll'JsonStringPayload(escaped.toSlice())
    defer Memory.delete(unicode)
    Swag.require(unicode.text == "A\u00E9\U0001F642")

    let invalidEscape: String = #raw """{"text":"\q"}"""
    var errInvalidEscapeOutcome: Swag.Error
    catch CoreTests.readAndDelete'(JsonStringPayload, Serialization.Read.Json)(&decoder, invalidEscape.toSlice()) as errInvalidEscapeOutcome
    let errInvalidEscape = errInvalidEscapeOutcome.value()
    Swag.require(errInvalidEscape != null)
}

#test
{
    const InvalidJson = [
        "{\"id\":1,\"id\":2}",
        "{\"id\":01}",
        "{\"id\":1,}",
        "{\"id\":1} trailing",
        "{\"counts\":[1 2]}",
        "{\"counts\":[1,]}",
        "{\"active\":truth}"]

    for input in InvalidJson
    {
        var decoder:    Serialization.Decoder'Serialization.Read.Json
        var errOutcome: Swag.Error
        catch CoreTests.readAndDelete'(JsonPayload, Serialization.Read.Json)(&decoder, cast(const [..] u8, input)) as errOutcome
        let err = errOutcome.value()
        Swag.require(err != null)
    }
}

#test
{
    const InvalidUtf8: [12] u8 = [0x7B, 0x22, 0x74, 0x65, 0x78, 0x74, 0x22, 0x3A, 0x22, 0xFF, 0x22, 0x7D]
    var decoder:      Serialization.Decoder'Serialization.Read.Json
    var errorOutcome: Swag.Error
    catch CoreTests.readAndDelete'(JsonStringPayload, Serialization.Read.Json)(&decoder, InvalidUtf8) as errorOutcome
    Swag.require(errorOutcome.value() is Errors.SyntaxError)
}
