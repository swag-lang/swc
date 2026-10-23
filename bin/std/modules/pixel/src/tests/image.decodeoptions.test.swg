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
    discard catch options.checkImage(2, 3, .RGBA8) as &tooLargeOutcome
    let tooLarge = tooLargeOutcome.value()
    Swag.assert((tooLarge is UnsupportedFormatError))

    // The pixel count fits u64, but multiplying it by sixteen bytes would wrap to zero.
    var overflowOutcome: Swag.Error
    discard catch options.checkImage(1 << 30, 1 << 30, .RGBAF32) as &overflowOutcome
    let overflow = overflowOutcome.value()
    Swag.assert((overflow is UnsupportedFormatError))

    options.maxDecodedBytes = 0
    expect options.checkImage(1 << 30, 1 << 30, .RGBAF32)
}
