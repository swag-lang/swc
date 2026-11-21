#global if #command == Swag.CompilerCommand.Test
#global private

using Swag, Core

#test
{
    let bytes = loadFontBytes("arial.ttf")
    let face  = expect Face.load(bytes.toSlice())
    defer face.destroy()

    expect face.setPixelSize(12, 24)
    Swag.require(expect face.size.scaleHorizontal(1000) == expect scale26_6(1000, 12, face.unitsPerEm))
    Swag.require(expect face.size.scaleVertical(1000) == expect scale26_6(1000, 24, face.unitsPerEm))
    Swag.require(expect face.size.scaleHorizontal(-500) == expect scale26_6(-500, 12, face.unitsPerEm))
    Swag.require(expect face.size.scaleVertical(0) == expect scale26_6(0, 24, face.unitsPerEm))
}

#test
{
    let bytes = loadFontBytes("arial.ttf")
    let face  = expect Face.load(bytes.toSlice())
    defer face.destroy()

    var outcome: Swag.Error
    discard catch face.size.scaleHorizontal(1000) as outcome
    Swag.require(outcome.value() != null)

    expect face.setPixelSize(65535, 65535)
    outcome = {}
    discard catch face.size.scaleHorizontal(Swag.S32.Max) as outcome
    Swag.require(outcome.value() != null)

    outcome = {}
    discard catch face.size.scaleVertical(Swag.S32.Min) as outcome
    Swag.require(outcome.value() != null)
}
