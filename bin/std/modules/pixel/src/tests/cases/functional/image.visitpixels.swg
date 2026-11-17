#global if #command == Swag.CompilerCommand.Test
#global private

using Swag, Core

// Pixel visits reject invalid storage and nonpositive strides before entering the loop.
#test
{
    var image = Image.create(3, 2, .Gray8, [1'u8, 2, 3, 4, 5, 6])
    image.visitPixels(stride: 2)
    {
        Swag.require(index == 0 or index == 2 or index == 4)
        Swag.require(x == cast(s32, index % 3) and y == cast(s32, index / 3))
    }

    let zeroStride = Swag.catchPanic(func|&image|()
    {
        image.visitPixels(stride: 0)
        {
            discard pix
        }
    })
    let negativeStride = Swag.catchPanic(func|&image|()
    {
        image.visitPixels(stride: -1)
        {
            discard pix
        }
    })
    Swag.require(zeroStride.raised and negativeStride.raised)
}

// An empty image or a shortened public pixel array cannot drive a raw pointer walk.
#test
{
    var empty: Image
    let emptyPointer  = &empty
    let rejectedEmpty = Swag.catchPanic(func|emptyPointer|()
    {
        emptyPointer[].visitPixels()
        {
            discard pix
        }
    })
    Swag.require(rejectedEmpty.raised)

    var truncated = Image.create(1, 1, .RGBA8)
    truncated.pixels.resize(3)
    let truncatedPointer  = &truncated
    let rejectedTruncated = Swag.catchPanic(func|truncatedPointer|()
    {
        truncatedPointer[].visitPixels()
        {
            discard pix
        }
    })
    Swag.require(rejectedTruncated.raised)
}
