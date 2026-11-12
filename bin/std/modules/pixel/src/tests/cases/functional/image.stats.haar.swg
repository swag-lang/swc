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
