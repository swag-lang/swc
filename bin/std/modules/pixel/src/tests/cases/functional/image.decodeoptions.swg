#global if #command == Swag.CompilerCommand.Test
#global private

using Swag, Core.Errors

#test
{
    var options: DecodeOptions
    options.maxPixels       = 0
    options.maxDecodedBytes = 24
    expect options.checkImage(2, 3, .RGBA8)
    options.maxDecodedBytes = 23
    var tooLargeOutcome: Swag.Error
    discard catch options.checkImage(2, 3, .RGBA8) as tooLargeOutcome
    let tooLarge = tooLargeOutcome.value()
    Swag.require((tooLarge is UnsupportedFormatError))

    // The pixel count fits u64, but multiplying it by sixteen bytes would wrap to zero.
    var overflowOutcome: Swag.Error
    discard catch options.checkImage(1 << 30, 1 << 30, .RGBAF32) as overflowOutcome
    let overflow = overflowOutcome.value()
    Swag.require((overflow is UnsupportedFormatError))

    options.maxDecodedBytes = 0
    expect options.checkImage(1 << 30, 1 << 30, .RGBAF32)
}

// Planar byte limits account for both ceil-sized 4:2:0 chroma planes, including odd dimensions.
#test
{
    var options: DecodeOptions
    options.maxPixels = 0

    options.maxDecodedBytes = 2
    var tooSmall420Outcome: Swag.Error
    discard catch options.checkImage(1, 1, .Yuv420) as tooSmall420Outcome
    Swag.require((tooSmall420Outcome.value() is UnsupportedFormatError))
    options.maxDecodedBytes = 3
    expect options.checkImage(1, 1, .Yuv420)

    options.maxDecodedBytes = 16
    var odd420Outcome: Swag.Error
    discard catch options.checkImage(3, 3, .Yuv420) as odd420Outcome
    Swag.require((odd420Outcome.value() is UnsupportedFormatError))
    options.maxDecodedBytes = 17
    expect options.checkImage(3, 3, .Yuv420)

    options.maxDecodedBytes = 26
    var yuv444Outcome: Swag.Error
    discard catch options.checkImage(3, 3, .Yuv444) as yuv444Outcome
    Swag.require((yuv444Outcome.value() is UnsupportedFormatError))
    options.maxDecodedBytes = 27
    expect options.checkImage(3, 3, .Yuv444)

    options.maxDecodedBytes = 23
    var packedOutcome: Swag.Error
    discard catch options.checkImage(2, 3, .RGBA8) as packedOutcome
    Swag.require((packedOutcome.value() is UnsupportedFormatError))
    options.maxDecodedBytes = 24
    expect options.checkImage(2, 3, .RGBA8)

    options.maxDecodedBytes = Swag.U64.Max
    expect options.checkImage(Swag.S32.Max, Swag.S32.Max, .Yuv420)
}
