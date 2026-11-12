#global if #command == Swag.CompilerCommand.Test

using Swag, Core

// Downsampling alternating columns must apply the bilinear filter instead of aliasing to black.
#test
{
    var image  = Image.create(256, 256, .Gray8)
    let pixels = image.pixels.storage()
    for y in image.height
    {
        for x in image.width
        {
            pixels[y * image.width + x] = (x & 1) == 0 ? 0 : 255
        }
    }

    let features = ImageStatistics.extractHaarFeatures(image)
    Swag.require(features.size == 128)
    Swag.require(Math.abs(features.coefficients[0] - 64) < 0.01)
    for index in 1 until features.coefficients.count do
        Swag.require(Math.abs(features.coefficients[index]) < 0.001)
}

// Border clamping preserves a constant image through both upsampling and downsampling.
#test
{
    var small = Image.create(3, 3, .Gray8)
    for index in small.byteCount do
        small.pixels.storage()[index] = 100

    let smallFeatures = ImageStatistics.extractHaarFeatures(small)
    Swag.require(smallFeatures.size == 4)
    Swag.require(Math.abs(smallFeatures.coefficients[0] - 4 * (100.0 / 255.0)) < 0.001)

    var large = Image.create(256, 256, .Gray8)
    for index in large.byteCount do
        large.pixels.storage()[index] = 64

    let largeFeatures = ImageStatistics.extractHaarFeatures(large)
    Swag.require(largeFeatures.size == 128)
    Swag.require(Math.abs(largeFeatures.coefficients[0] - 128 * (64.0 / 255.0)) < 0.001)
}

// The quick nearest-neighbor thumbnail scales small images across the full window on both axes.
#test
{
    var vertical   = Image.create(3, 3, .Gray8)
    var horizontal = Image.create(3, 3, .Gray8)
    for y in 3
    {
        for x in 3
        {
            vertical.pixels.storage()[y * 3 + x]   = x == 1 ? 255 : 0
            horizontal.pixels.storage()[y * 3 + x] = y == 1 ? 255 : 0
        }
    }

    let verticalFeatures   = ImageStatistics.quickExtractHaarFeatures(vertical)
    let horizontalFeatures = ImageStatistics.quickExtractHaarFeatures(horizontal)
    Swag.require(verticalFeatures.size == 32 and horizontalFeatures.size == 32)
    Swag.require(Math.abs(verticalFeatures.coefficients[0] - 11) < 0.01)
    Swag.require(Math.abs(horizontalFeatures.coefficients[0] - 11) < 0.01)
}

// A one-pixel edge image expands uniformly, and an equal-size thumbnail keeps its luminance.
#test
{
    var single = Image.create(1, 1, .Gray8)
    single.pixels.storage()[0] = 80
    let singleFeatures = ImageStatistics.quickExtractHaarFeatures(single)
    Swag.require(Math.abs(singleFeatures.coefficients[0] - 32 * (80.0 / 255.0)) < 0.001)
    for index in 1 until singleFeatures.coefficients.count do
        Swag.require(Math.abs(singleFeatures.coefficients[index]) < 0.001)

    var equalSize = Image.create(32, 32, .Gray8)
    for index in equalSize.byteCount do
        equalSize.pixels.storage()[index] = 64
    let equalFeatures = ImageStatistics.quickExtractHaarFeatures(equalSize)
    Swag.require(Math.abs(equalFeatures.coefficients[0] - 32 * (64.0 / 255.0)) < 0.001)
}

// Normalized correlation distinguishes exact zero vectors from nonzero vectors at any scale.
#test
{
    var tiny: ImageStatistics.HaarFeatures
    tiny.size   = 1
    tiny.levels = 0
    tiny.coefficients.resize(1)
    tiny.coefficients[0] = 0.000001

    var inverted = tiny
    inverted.coefficients[0] = -tiny.coefficients[0]
    var zero: ImageStatistics.HaarFeatures
    zero.size   = 1
    zero.levels = 0
    zero.coefficients.resize(1)

    Swag.require(ImageStatistics.compareHaarCoefficients(tiny, tiny) == 1)
    Swag.require(ImageStatistics.compareHaarCoefficients(tiny, inverted) == 1)
    Swag.require(ImageStatistics.quickCompareHaarCoefficients(tiny, tiny) == 1)
    Swag.require(ImageStatistics.quickCompareHaarCoefficients(tiny, inverted) == 1)
    Swag.require(ImageStatistics.compareHaarCoefficients(zero, zero) == 1)
    Swag.require(ImageStatistics.quickCompareHaarCoefficients(zero, zero) == 1)
    Swag.require(ImageStatistics.compareHaarCoefficients(zero, tiny) == 0)
    Swag.require(ImageStatistics.quickCompareHaarCoefficients(zero, tiny) == 0)
}
