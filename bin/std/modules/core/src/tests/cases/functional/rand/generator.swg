#global if #command == Swag.CompilerCommand.Test
#global private

using Swag

struct MaxRandomSource {}

internal impl MaxRandomSource
{
    mtd seedU32(seed: u32) { discard seed }
    mtd nextU32()->u32 => Swag.U32.Max
}

#test
{
    var generator: Random.Generator
    generator.seedU32(12345)

    for 10_000
    {
        let unsigned32 = generator.nextU32(10, 37)
        Swag.require(unsigned32 >= 10 and unsigned32 < 37)

        let unsigned64 = generator.nextU64(100, 10_000)
        Swag.require(unsigned64 >= 100 and unsigned64 < 10_000)

        let signed32 = generator.nextS32(Swag.S32.Min, Swag.S32.Max)
        Swag.require(signed32 >= Swag.S32.Min and signed32 < Swag.S32.Max)

        let signed64 = generator.nextS64(Swag.S64.Min, Swag.S64.Max)
        Swag.require(signed64 >= Swag.S64.Min and signed64 < Swag.S64.Max)

        let unit32 = generator.nextF32()
        Swag.require(unit32 >= 0 and unit32 < 1)

        let unit64 = generator.nextF64()
        Swag.require(unit64 >= 0 and unit64 < 1)
    }
}

#test
{
    var generator: Random.Generator'MaxRandomSource
    generator.seedU32(1)

    let value32 = generator.nextF32(1'f32, 2'f32)
    let value64 = generator.nextF64(1'f64, 2'f64)
    Swag.require(value32 >= 1 and value32 < 2)
    Swag.require(value64 >= 1 and value64 < 2)

    let wide32 = generator.nextF32(-Swag.F32.Max, Swag.F32.Max)
    let wide64 = generator.nextF64(-Swag.F64.Max, Swag.F64.Max)
    Swag.require(Math.isFinite(wide32) and wide32 >= -Swag.F32.Max and wide32 < Swag.F32.Max)
    Swag.require(Math.isFinite(wide64) and wide64 >= -Swag.F64.Max and wide64 < Swag.F64.Max)

    let invalid32 = Swag.catchPanic(func|&generator|()
    {
        discard generator.nextF32(0'f32, Swag.F32.Inf)
    })
    let nan32 = Swag.catchPanic(func|&generator|()
    {
        discard generator.nextF32(0'f32, Swag.F32.NaN)
    })
    let invalid64 = Swag.catchPanic(func|&generator|()
    {
        discard generator.nextF64(0'f64, Swag.F64.Inf)
    })
    let nan64 = Swag.catchPanic(func|&generator|()
    {
        discard generator.nextF64(0'f64, Swag.F64.NaN)
    })
    Swag.require(invalid32.raised and invalid32.message() == "bounds must be finite")
    Swag.require(nan32.raised and nan32.message() == "bounds must be finite")
    Swag.require(invalid64.raised and invalid64.message() == "bounds must be finite")
    Swag.require(nan64.raised and nan64.message() == "bounds must be finite")
}

#test
{
    var generator: Random.Generator'MaxRandomSource
    let min32 = 1'f32
    let max32 = cast #bit (f32, 0x3F800001'u32)
    let min64 = 1'f64
    let max64 = cast #bit (f64, 0x3FF0000000000001'u64)

    Swag.require(generator.nextF32(min32, max32) == min32)
    Swag.require(generator.nextF64(min64, max64) == min64)
}

#test
{
    var generator: Random.Generator'MaxRandomSource
    generator.seedU32(1)

    Swag.require(generator.nextU32(0, 8) == 7)
    Swag.require(generator.nextU64(0, 16) == 15)
    Swag.require(generator.nextS32(-4, 4) == 3)
    Swag.require(generator.nextS64(-8, 8) == 7)
}

#test
{
    var generator: Random.Generator
    generator.seedU32(98765)

    for 4096
    {
        let power32  = generator.nextU32(0, 8)
        let power64  = generator.nextU64(0, 16)
        let signed32 = generator.nextS32(-4, 4)
        let signed64 = generator.nextS64(-8, 8)
        Swag.require(power32 < 8)
        Swag.require(power64 < 16)
        Swag.require(signed32 >= -4 and signed32 < 4)
        Swag.require(signed64 >= -8 and signed64 < 8)
    }
}

#test
{
    var generator: Random.Generator
    generator.seedU32(12345)

    var values: [8] u32 = [0, 1, 2, 3, 4, 5, 6, 7]
    generator.shuffle(values)

    var found: [8] bool
    for value in values
    {
        Swag.require(value < found.count)
        Swag.require(not found[value])
        found[value] = true
    }

    for present in found do
        Swag.require(present)
}
