#global if #command == Swag.CompilerCommand.Test
#global private

using Swag

struct RoundTripInner
{
    name:  String
    value: f64
}

struct RoundTripOuter
{
    text:    String
    empty:   String
    small:   s8
    big:     u64
    neg:     s64
    tiny:    f32
    huge:    f64
    flag:    bool
    items:   Array'RoundTripInner
    none:    Array's32
    fixed:   [2] RoundTripInner
    runes:   rune
}

func makeRoundTrip()->RoundTripOuter
{
    var result: retval
    result.text  = "quote\" back\\ nl\n tab\t cr\r ctl\x01 del\x7F é € 😀 </tag>"
    result.small = -128
    result.big   = Swag.U64.Max
    result.neg   = Swag.S64.Min
    result.tiny  = 1.0e-38
    result.huge  = 1.7976931348623157e308
    result.flag  = true
    result.items.add(RoundTripInner{"a", -0.5})
    result.items.add(RoundTripInner{"", 123456789.125})
    result.fixed[1].name = "last"
    result.runes = '😀'
    return result
}

func sameRoundTrip(a, b: RoundTripOuter)->bool
{
    return a.text == b.text and b.empty.isEmpty() and a.small == b.small and a.big == b.big and a.neg == b.neg and
           a.tiny == b.tiny and a.huge == b.huge and a.flag == b.flag and b.items.count == 2 and
           b.items[0].name == "a" and b.items[0].value == -0.5 and b.items[1].name == "" and
           b.items[1].value == 123456789.125 and b.none.isEmpty() and b.fixed[1].name == "last" and a.runes == b.runes
}

// JSON, compact or indented, carries escapes, control characters, astral runes, integer extremes,
// and subnormal floats unchanged.
#test
{
    let source = makeRoundTrip()
    for blanks in [false, true]
    {
        var encoder: Serialization.Encoder'Serialization.Write.Json
        encoder.serializer.options.saveBlanks = blanks
        var buffer: ConcatBuffer
        expect encoder.writeAll(&buffer, source)
        let json = buffer.toString()

        var decoder: Serialization.Decoder'Serialization.Read.Json
        let decoded = expect decoder.readAll'RoundTripOuter(json.toSlice())!
        defer Memory.delete(decoded)
        Swag.assert(sameRoundTrip(source, decoded[]))
    }
}

// TagBin carries the same values unchanged.
#test
{
    let source = makeRoundTrip()
    var buffer:  ConcatBuffer
    var encoder: Serialization.Encoder'Serialization.Write.TagBin
    expect encoder.writeAll(&buffer, source)
    let bytes = buffer.toString()

    var decoder: Serialization.Decoder'Serialization.Read.TagBin
    let decoded = expect decoder.readAll'RoundTripOuter(bytes.toSlice())!
    defer Memory.delete(decoded)
    Swag.assert(sameRoundTrip(source, decoded[]))
}
