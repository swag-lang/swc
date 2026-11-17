#global if #command == Swag.CompilerCommand.Test
#global private

using Swag, Core

// Image creation and conversion preserve packed storage invariants in every build mode.
#test
{
    let source = Image.create(2, 2, .RGBA8)
    let sourcePointer = &source
    let rejectedConversion = Swag.catchPanic(func|sourcePointer|()
    {
        discard sourcePointer[].convertedTo(.Yuv420)
    })
    Swag.require(rejectedConversion.raised and source.isValid())

    let rejectedCreation = Swag.catchPanic(func()
    {
        discard Image.create(1, 1, .Yuv444)
    })
    Swag.require(rejectedCreation.raised and source.isValid() and source.pixelFormat == .RGBA8)

    let rejectedDimensions = Swag.catchPanic(func()
    {
        discard Image.create(0, 1, .RGBA8)
    })
    let rejectedRow = Swag.catchPanic(func()
    {
        discard Image.create(Swag.S32.Max, 1, .RGBA8)
    })
    let rejectedAlpha = Swag.catchPanic(func()
    {
        discard Image.create(1, 1, .RGB8, alphaMode: .Premultiplied)
    })
    Swag.require(rejectedDimensions.raised and rejectedRow.raised and rejectedAlpha.raised)
}

// Invalid buffer sizes are rejected before Memory.copy can cross an allocation boundary.
#test
{
    let tooShort: [3] u8 = [1, 2, 3]
    let tooLong: [5] u8  = [1, 2, 3, 4, 5]
    let shortPointer = &tooShort
    let longPointer  = &tooLong
    let rejectedShort = Swag.catchPanic(func|shortPointer|()
    {
        discard Image.create(1, 1, .RGBA8, Swag.makeSlice(shortPointer[].buffer, 3))
    })
    let rejectedLong = Swag.catchPanic(func|longPointer|()
    {
        discard Image.create(1, 1, .RGBA8, Swag.makeSlice(longPointer[].buffer, 5))
    })
    Swag.require(rejectedShort.raised and rejectedLong.raised)
}

