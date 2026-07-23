#global #if #command == Swag.CompilerCommand.Test
#global private

using Swag

#test
{
    var rng: Random.CMWC4096

    @assert(rng.i == 4096)
    @assert(rng.c == 0)

    @assert(rng.nextU32() == 0xC2B9C7E2'u32)
    @assert(rng.nextU32() == 0x9B459F2F'u32)
    @assert(rng.nextU32() == 0x53116140'u32)
    @assert(rng.nextU32() == 0x549DF40D'u32)
    @assert(rng.nextU32() == 0x1D84A0A8'u32)
}

#test
{
    var rng: Random.CMWC4096
    rng.seedU32(362436)

    @assert(rng.i == 4095)
    @assert(rng.c == 362436)
    @assert(rng.q[0] == 0x45D10545'u32)
    @assert(rng.q[1] == 0x7945A8DA'u32)
    @assert(rng.q[4095] == 0xF7A65156'u32)

    @assert(rng.nextU32() == 0xC2B9C7E2'u32)
    @assert(rng.nextU32() == 0x9B459F2F'u32)
    @assert(rng.nextU32() == 0x53116140'u32)
    @assert(rng.nextU32() == 0x549DF40D'u32)
    @assert(rng.nextU32() == 0x1D84A0A8'u32)
}

#test
{
    var rng: Random.CMWC4096
    rng.seedU32(123456789)

    @assert(rng.i == 4095)
    @assert(rng.c == 123456789 % 809430660)
    @assert(rng.q[0] == 0x58DADBEB'u32)
    @assert(rng.q[1] == 0xB43A33C3'u32)
    @assert(rng.q[4095] == 0xC6A605B4'u32)

    @assert(rng.nextU32() == 0xEF915628'u32)
    @assert(rng.nextU32() == 0x39DE1647'u32)
    @assert(rng.nextU32() == 0xB964ECDE'u32)
    @assert(rng.nextU32() == 0x6E009E03'u32)
    @assert(rng.nextU32() == 0xFA519A6A'u32)
}

#test
{
    var rng: Random.CMWC4096
    rng.seedU32(0)

    @assert(rng.i == 4095)
    @assert(rng.c == 0)
    @assert(rng.q[0] == 0x30ED45A2'u32)
    @assert(rng.q[1] == 0x8AF31F06'u32)
    @assert(rng.q[4095] == 0xEF8BEF6E'u32)

    @assert(rng.nextU32() == 0x60052E7D'u32)
    @assert(rng.nextU32() == 0xA6E1AFF3'u32)
    @assert(rng.nextU32() == 0xAA5A0546'u32)
    @assert(rng.nextU32() == 0xA874171C'u32)
    @assert(rng.nextU32() == 0xFC852A71'u32)
}
