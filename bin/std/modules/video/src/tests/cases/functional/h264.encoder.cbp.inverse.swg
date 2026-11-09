#global if #command == Swag.CompilerCommand.Test
#global private

using Swag

// Every inter coded-block pattern uses the same H.264 Golomb code as the decoder table.
#test
{
    for pattern in 48'u64
    {
        let code = cast(u64, H264.InterCbpToGolomb[pattern])
        Swag.require(code < 48)
        Swag.require(cast(u64, H264.GolombToInterCbp[code]) == pattern)
    }
}
