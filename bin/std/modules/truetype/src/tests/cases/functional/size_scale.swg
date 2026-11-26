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

// The reciprocal and division paths must round identically at signed limits.
#test
{
    const Units:       [8] u16  = [1, 16, 51, 1000, 1024, 2048, 16384, Swag.U16.Max]
    const PixelSizes:  [5] u32  = [1, 24, 64, 4096, Swag.U16.Max]
    const Coordinates: [13] s32 = [Swag.S32.Min, -32768, -1023, -51, -2, -1, 0, 1, 2, 51, 1023, 32767, Swag.S32.Max]
    for units in Units
    {
        let scale = expect PointScale.create(units)
        for size in PixelSizes
        {
            let factor = cast(s64, size) * 64
            for coordinate in Coordinates
            {
                var direct, reciprocal: s32
                var directError, reciprocalError: Swag.Error
                catch { direct = try scale26_6(coordinate, size, units) } as directError
                catch { reciprocal = try scale.apply(coordinate, factor) } as reciprocalError
                Swag.require(directError.isEmpty() == reciprocalError.isEmpty())
                if directError.isEmpty() do
                    Swag.require(direct == reciprocal)
            }
        }
    }
}
