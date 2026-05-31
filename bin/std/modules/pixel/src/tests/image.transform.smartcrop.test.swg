#global #if #command == Swag.CompilerCommand.Test
using Swag, Core

#test
{
    const pixels = [
        20'u8, 20'u8, 20'u8, 255'u8,     20'u8, 20'u8, 20'u8, 255'u8,     255'u8, 0'u8, 0'u8, 255'u8,     0'u8, 255'u8, 0'u8, 255'u8,
        20'u8, 20'u8, 20'u8, 255'u8,     20'u8, 20'u8, 20'u8, 255'u8,     255'u8, 0'u8, 0'u8, 255'u8,     0'u8, 255'u8, 0'u8, 255'u8,
    ]

    let src = makeImage(4, 2, .RGBA8, pixels)

    var opts: Image.SmartCropSearchOpts
    opts.minCoverage  = 1.0
    opts.thirdsWeight = 0.0
    opts.centerWeight = 0.0
    opts.shrinkPrior  = 0.0
    opts.edgePenalty  = 0.0

    var leftRect: Math.Rectangle
    leftRect.width  = 2
    leftRect.height = 2

    var rightRect: Math.Rectangle
    rightRect.x      = 2
    rightRect.width  = 2
    rightRect.height = 2

    var targetRect: Math.Rectangle
    targetRect.width  = 2
    targetRect.height = 2

    var cropped = src
    cropped.smartCrop(targetRect, opts)
    assertImage(cropped, 2, 2, .RGBA8)
    assertPixel(cropped, 0, 1, Color.fromArgb(255'u8, 255'u8, 0'u8, 0'u8))
    assertPixel(cropped, 1, 1, Color.fromArgb(255'u8, 0'u8, 255'u8, 0'u8))
    assertPixel(cropped, 0, 0, Color.fromArgb(255'u8, 255'u8, 0'u8, 0'u8))
    assertPixel(cropped, 1, 0, Color.fromArgb(255'u8, 0'u8, 255'u8, 0'u8))
}
