#global if #command == Swag.CompilerCommand.Test
#global private

using Swag, Core

// Native clipboard storage can be padded, truncated, or supplied by another process.
#test
{
    let type: typeinfo = s32
    let source         = [1'u8, 2, 3]
    let payload        = Clipboard.TypedPayload{crc: type.crc, data: source}
    var encoded        = payload.encode()
    let decoded        = expect Clipboard.TypedPayload.decode(encoded.toSlice())
    Swag.assert(decoded.matches(s32) and not decoded.matches(u64))
    Swag.assert(decoded.matches(null))
    Swag.assert(decoded.data != null and decoded.data.count == 3 and decoded.data[2] == 3)

    // Every incomplete header and payload fails before any out-of-bounds read or slice.
    for size in encoded.count
    {
        discard catch Clipboard.TypedPayload.decode(encoded.toSlice()[0 until size]) as error
        Swag.assert(error != null)
    }

    for i in 8 do
        encoded[4 + i] = 255
    discard catch Clipboard.TypedPayload.decode(encoded.toSlice()) as oversized
    Swag.assert(oversized != null)

    let empty      = Clipboard.TypedPayload{crc: type.crc}
    var emptyBytes = empty.encode()
    emptyBytes.add(0xA5)
    let withPadding = expect Clipboard.TypedPayload.decode(emptyBytes.toSlice())
    Swag.assert(withPadding.matches(s32) and withPadding.data.count == 0)
}
