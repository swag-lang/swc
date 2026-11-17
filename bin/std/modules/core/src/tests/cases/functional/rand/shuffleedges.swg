#global if #command == Swag.CompilerCommand.Test
#global private

using Swag

struct NoDrawRandomSource {}
var RandomDrawCount: u32

internal impl NoDrawRandomSource
{
    mtd seedU32(_: u32) {}

    mtd nextU32()->u32
    {
        RandomDrawCount += 1
        return Swag.U32.Max
    }
}

#test
{
    var generator: Random.Generator'NoDrawRandomSource
    generator.seedU32(1)
    RandomDrawCount = 0

    var empty:  Array'u32
    var single: [1] u32 = [42]
    generator.shuffle(empty.toSlice())
    generator.shuffle(single)

    Swag.require(RandomDrawCount == 0)
    Swag.require(single[0] == 42)
}
