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

struct JsonKeyPayload
{
    #[Serialization.Key("wireName")]
    sourceName: u32
}

func makeJsonPayload()->JsonPayload
{
    var result: retval

    let seed: [3] s32 = [-1, 0, 4]
    result.id     = 7
    result.active = true
    result.name   = "core"
    result.counts.add(seed)
    result.pair      = JsonPair{x: 3, y: -2}
    result.fixed     = [1, 2, 3]
    result.transient = 99
    return result
}

func assertIntArray(values: Array's32, expected: const [..] s32)->bool
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

func assertJsonPayload(value: JsonPayload)->bool
{
    return value.id == 7 and
           value.active and
           value.name == "core" and
           assertIntArray(value.counts, [-1, 0, 4]) and
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
    Swag.assert(json == "{\"id\":7,\"active\":true,\"name\":\"core\",\"counts\":[-1,0,4],\"pair\":{\"x\":3,\"y\":-2},\"fixed\":[1,2,3]}")
    Swag.assert(json.indexOf("transient") == Swag.U64.Max)

    var decoder: Serialization.Decoder'Serialization.Read.Json
    let decoded = expect decoder.readAll'JsonPayload(json.toSlice())!
    Swag.assert(assertJsonPayload(decoded[]))
    Swag.assert(decoded.transient == 0)

    Memory.delete(decoded)
}

#test
{
    let source:  String = "{\"wireName\":42}"
    var decoder: Serialization.Decoder'Serialization.Read.Json
    let decoded         = expect decoder.readAll'JsonKeyPayload(source.toSlice())!
    Swag.assert(decoded.sourceName == 42)
    Memory.delete(decoded)
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
    Swag.assert(json == "{\n  \"id\": 7,\n  \"active\": true,\n  \"name\": \"core\",\n  \"counts\": [\n    -1,\n    0,\n    4\n  ],\n  \"pair\": {\n    \"x\": 3,\n    \"y\": -2\n  },\n  \"fixed\": [\n    1,\n    2,\n    3\n  ]\n}")
}

#test
{
    let json: String = "{\n  \"id\": 8,\n  \"active\": false,\n  \"name\": null,\n  \"counts\": [9, 8],\n  \"pair\": {\"x\": -1, \"y\": 2},\n  \"fixed\": [5, 6, 7]\n}"

    var decoder: Serialization.Decoder'Serialization.Read.Json
    let decoded = expect decoder.readAll'JsonPayload(json.toSlice())!
    Swag.assert(decoded.id == 8)
    Swag.assert(!decoded.active)
    Swag.assert(decoded.name.isNullOrEmpty())
    Swag.assert(assertIntArray(decoded.counts, [9, 8]))
    Swag.assert(decoded.pair.x == -1)
    Swag.assert(decoded.pair.y == 2)
    Swag.assert(decoded.fixed[0] == 5)
    Swag.assert(decoded.fixed[1] == 6)
    Swag.assert(decoded.fixed[2] == 7)
    Swag.assert(decoded.transient == 0)

    Memory.delete(decoded)
}

#test
{
    let interoperable: String = "{\"unknown\":{\"nested\":[true,null,{\"x\":1}]},\"fixed\":[1,2,3],\"name\":\"core\",\"pair\":{\"y\":-2,\"ignored\":9,\"x\":3},\"id\":7,\"active\":true,\"counts\":[-1,0,4]}"

    var decoder: Serialization.Decoder'Serialization.Read.Json
    let decoded = expect decoder.readAll'JsonPayload(interoperable.toSlice())!
    Swag.assert(assertJsonPayload(decoded[]))
    Memory.delete(decoded)

    let missing: String = "{\"id\":12}"
    let partial         = expect decoder.readAll'JsonPayload(missing.toSlice())!
    Swag.assert(partial.id == 12)
    Swag.assert(!partial.active)
    Swag.assert(partial.name.isNullOrEmpty())
    Swag.assert(partial.counts.count == 0)
    Memory.delete(partial)
}

#test
{
    var payload = JsonFloatPayload{value: cast #bit (f64) 0x7FF8000000000000'u64}
    var encoder: Serialization.Encoder'Serialization.Write.Json
    var buffer:  ConcatBuffer
    expect encoder.writeAll(&buffer, payload)
    Swag.assert(buffer.toString() == "{\"value\":null}")
}

#test
{
    var payload: JsonStringPayload
    payload.text = "quote=\" slash=\\ controls=\b\f\n\r\t caf\u00E9 \U0001F642"

    var encoder: Serialization.Encoder'Serialization.Write.Json
    var buffer:  ConcatBuffer
    expect encoder.writeAll(&buffer, payload)
    Swag.assert(buffer.toString() == "{\"text\":\"quote=\\\" slash=\\\\ controls=\\b\\f\\n\\r\\t caf\u00E9 \U0001F642\"}")

    var decoder: Serialization.Decoder'Serialization.Read.Json
    let decoded = expect decoder.readAll'JsonStringPayload(buffer.toSlice()!)!
    Swag.assert(decoded.text == payload.text)
    Memory.delete(decoded)

    let escaped: String = #raw """{"text":"A\u00E9\uD83D\uDE42"}"""
    let unicode = expect decoder.readAll'JsonStringPayload(escaped.toSlice())!
    Swag.assert(unicode.text == "A\u00E9\U0001F642")
    Memory.delete(unicode)

    let invalidEscape: String = #raw """{"text":"\q"}"""
    let rejected = catch decoder.readAll'JsonStringPayload(invalidEscape.toSlice()) as errInvalidEscape
    Swag.assert(rejected == null)
    Swag.assert(errInvalidEscape != null)
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
        var decoder: Serialization.Decoder'Serialization.Read.Json
        let decoded = catch decoder.readAll'JsonPayload(Swag.makeSlice(input.buffer, input.count)) as err
        Swag.assert(decoded == null)
        Swag.assert(err != null)
    }
}
