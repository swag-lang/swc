#global #static if #command == Swag.CompilerCommand.Test
#global private

using Swag

// Round-trip through Deflate -> Inflate (with the zlib header + adler32 trailer).
// Exercises the bulk-refill fast path and the post-stream checksum read.
#test
{
    var original: [4000] u8
    for [i] in 4000 do
        original[i] = cast #bit (u8) (i * 7 + (i >> 2) + (i & 13))

    var zl: Compress.ZLib
    let compressed = catch zl.compress(original) as err
    @assert(err == null)

    var zl2: Compress.ZLib
    let decompressed = catch zl2.decompress(compressed.toSlice()) as err2
    @assert(err2 == null)
    @assert(@countof(decompressed) == 4000)

    var ok = true
    for [i] in 4000 do
        if decompressed[i] != original[i] do
            ok = false
    @assert(ok)
}
