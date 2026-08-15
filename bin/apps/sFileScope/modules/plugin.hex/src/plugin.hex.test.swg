#global if #command == Swag.CompilerCommand.Test
#global private

using Core

#test
{
    let text = formatHexPage([0'u8, 1'u8, 0x20'u8, 0x41'u8, 0xFF'u8], 0x20)
    @assert(Utf8.contains(text.toSlice(), "0000000000000020"))
    @assert(Utf8.contains(text.toSlice(), "00 01 20 41 FF"))
    @assert(Utf8.contains(text.toSlice(), ".. A."))
}
