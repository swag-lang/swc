#global #if #command == Swag.CompilerCommand.Test
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

func assertIntArray(values: const &Array's32, expected: const [..] s32)->bool
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

func assertJsonPayload(value: const &JsonPayload)->bool
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

    var encoder: Serialization.Encoder'Serialization.Write.JSon
    encoder.serializer.options.saveBlanks = false

    var buffer: ConcatBuffer
    catch encoder.writeAll(&buffer, payload)
    @assert(@err == null)

    let json = buffer.toString()
    @assert(json == "{\"id\":7,\"active\":true,\"name\":\"core\",\"counts\":[-1,0,4],\"pair\":{\"x\":3,\"y\":-2},\"fixed\":[1,2,3]}")
    @assert(json.indexOf("transient") == Swag.U64.Max)

    var decoder: Serialization.Decoder'Serialization.Read.JSon
    let decoded = notnull catch decoder.readAll'JsonPayload(json.toSlice())
    @assert(@err == null)
    @assert(assertJsonPayload(dref decoded))
    @assert(decoded.transient == 0)

    Memory.delete(decoded)
}

#test
{
    let payload = makeJsonPayload()

    var encoder: Serialization.Encoder'Serialization.Write.JSon
    encoder.serializer.options.saveBlanks  = true
    encoder.serializer.options.indentLevel = 2

    var buffer: ConcatBuffer
    catch encoder.writeAll(&buffer, payload)
    @assert(@err == null)

    let json = buffer.toString()
    @assert(json == "{\n  \"id\": 7,\n  \"active\": true,\n  \"name\": \"core\",\n  \"counts\": [\n    -1,\n    0,\n    4\n  ],\n  \"pair\": {\n    \"x\": 3,\n    \"y\": -2\n  },\n  \"fixed\": [\n    1,\n    2,\n    3\n  ]\n}")
}

#test
{
    let json: String = "{\n  \"id\": 8,\n  \"active\": false,\n  \"name\": null,\n  \"counts\": [9, 8],\n  \"pair\": {\"x\": -1, \"y\": 2},\n  \"fixed\": [5, 6, 7]\n}"

    var decoder: Serialization.Decoder'Serialization.Read.JSon
    let decoded = notnull catch decoder.readAll'JsonPayload(json.toSlice())
    @assert(@err == null)

    @assert(decoded.id == 8)
    @assert(!decoded.active)
    @assert(decoded.name.isNullOrEmpty())
    @assert(assertIntArray(decoded.counts, [9, 8]))
    @assert(decoded.pair.x == -1)
    @assert(decoded.pair.y == 2)
    @assert(decoded.fixed[0] == 5)
    @assert(decoded.fixed[1] == 6)
    @assert(decoded.fixed[2] == 7)
    @assert(decoded.transient == 0)

    Memory.delete(decoded)
}

#test
{
    let invalid: String = "{\"id\":7,\"active\":true,\"wrong\":\"core\",\"counts\":[-1,0,4],\"pair\":{\"x\":3,\"y\":-2},\"fixed\":[1,2,3]}"

    var decoder: Serialization.Decoder'Serialization.Read.JSon
    let decoded = catch decoder.readAll'JsonPayload(invalid.toSlice())
    @assert(decoded == null)
    @assert(@err != null)
}
