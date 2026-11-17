#global if #command == Swag.CompilerCommand.Test
#global private

using Swag

struct ZeroRandomSource {}

internal impl ZeroRandomSource
{
    mtd seedU32(_: u32) {}
    mtd nextU32()->u32 => 0
}

struct MaxRandomSource {}

internal impl MaxRandomSource
{
    mtd seedU32(_: u32) {}
    mtd nextU32()->u32 => Swag.U32.Max
}

#test
{
    var zero: Random.Generator'ZeroRandomSource
    zero.seedU32(1)
    Swag.require(not zero.nextBool())
    Swag.require(zero.nextS32() == 0)
    Swag.require(zero.nextS64() == 0)

    var maximum: Random.Generator'MaxRandomSource
    maximum.seedU32(1)
    Swag.require(maximum.nextBool())
    Swag.require(maximum.nextS32() == -1)
    Swag.require(maximum.nextS64() == -1)
}
