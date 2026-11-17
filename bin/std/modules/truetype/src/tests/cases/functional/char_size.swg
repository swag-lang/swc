#global if #command == Swag.CompilerCommand.Test
#global private

using Swag, Core

#test
{
    let bytes = loadFontBytes("arial.ttf")
    let face = expect Face.load(bytes.toSlice())
    defer face.destroy()

    // 12.5 points at 72 DPI rounds to 13 ppem; a fractional result at .5 rounds up.
    expect face.setCharSize(12 * 64 + 32, 12 * 64 + 32, 72, 72)
    Swag.require(face.size.metrics.xPpem == 13)
    Swag.require(face.size.metrics.yPpem == 13)

    // The axes use independent resolutions: 12 points gives 12x24 ppem here.
    expect face.setCharSize(12 * 64, 12 * 64, 72, 144)
    Swag.require(face.size.metrics.xPpem == 12)
    Swag.require(face.size.metrics.yPpem == 24)
}

#test
{
    let bytes = loadFontBytes("arial.ttf")
    let face = expect Face.load(bytes.toSlice())
    defer face.destroy()

    // A zero point dimension copies the other axis after its DPI conversion.
    expect face.setCharSize(0, 12 * 64, 144, 72)
    Swag.require(face.size.metrics.xPpem == 12)
    Swag.require(face.size.metrics.yPpem == 12)

    expect face.setCharSize(12 * 64, 0, 144, 72)
    Swag.require(face.size.metrics.xPpem == 24)
    Swag.require(face.size.metrics.yPpem == 24)
}

#test
{
    let bytes = loadFontBytes("arial.ttf")
    let face = expect Face.load(bytes.toSlice())
    defer face.destroy()

    var outcome: Swag.Error
    discard catch face.setCharSize(0, 0, 72, 72) as outcome
    Swag.require(outcome.value() != null)

    outcome = {}
    discard catch face.setCharSize(-64, 12 * 64, 72, 72) as outcome
    Swag.require(outcome.value() != null)

    outcome = {}
    discard catch face.setCharSize(12 * 64, 12 * 64, 0, 72) as outcome
    Swag.require(outcome.value() != null)

    outcome = {}
    discard catch face.setCharSize(1, 1, 1, 1) as outcome
    Swag.require(outcome.value() != null)

    outcome = {}
    discard catch face.setCharSize(12 * 64, 12 * 64, 1000000, 72) as outcome
    Swag.require(outcome.value() != null)
}
