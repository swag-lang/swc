#global if #command == Swag.CompilerCommand.Test
#global private

using Swag

#test
{
    var generator: Random.Generator
    generator.seedU32(12345)

    for 10_000
    {
        let unsigned32 = generator.nextU32(10, 37)
        Swag.assert(unsigned32 >= 10 and unsigned32 < 37)

        let unsigned64 = generator.nextU64(100, 10_000)
        Swag.assert(unsigned64 >= 100 and unsigned64 < 10_000)

        let signed32 = generator.nextS32(Swag.S32.Min, Swag.S32.Max)
        Swag.assert(signed32 >= Swag.S32.Min and signed32 < Swag.S32.Max)

        let signed64 = generator.nextS64(Swag.S64.Min, Swag.S64.Max)
        Swag.assert(signed64 >= Swag.S64.Min and signed64 < Swag.S64.Max)

        let unit32 = generator.nextF32()
        Swag.assert(unit32 >= 0 and unit32 < 1)

        let unit64 = generator.nextF64()
        Swag.assert(unit64 >= 0 and unit64 < 1)
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
        Swag.assert(value < found.count)
        Swag.assert(!found[value])
        found[value] = true
    }

    for present in found do
        Swag.assert(present)
}
