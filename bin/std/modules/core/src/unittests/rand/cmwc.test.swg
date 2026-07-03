#global #if #command == Swag.CompilerCommand.Test
#global private
using Swag

#test
{
    var rng: Random.CMWC4096

    @assert(rng.i == 4096)
    @assert(rng.c == 0)

    @assert(rng.nextU32() == 0xc2b9c7e2'u32)
    @assert(rng.nextU32() == 0x9b459f2f'u32)
    @assert(rng.nextU32() == 0x53116140'u32)
    @assert(rng.nextU32() == 0x549df40d'u32)
    @assert(rng.nextU32() == 0x1d84a0a8'u32)
}

#test
{
    var rng: Random.CMWC4096
    rng.seedU32(362436)

    @assert(rng.i == 4095)
    @assert(rng.c == 362436)
    @assert(rng.q[0] == 0x45d10545'u32)
    @assert(rng.q[1] == 0x7945a8da'u32)
    @assert(rng.q[4095] == 0xf7a65156'u32)

    @assert(rng.nextU32() == 0xc2b9c7e2'u32)
    @assert(rng.nextU32() == 0x9b459f2f'u32)
    @assert(rng.nextU32() == 0x53116140'u32)
    @assert(rng.nextU32() == 0x549df40d'u32)
    @assert(rng.nextU32() == 0x1d84a0a8'u32)
}

#test
{
    var rng: Random.CMWC4096
    rng.seedU32(123456789)

    @assert(rng.i == 4095)
    @assert(rng.c == 123456789 % 809430660)
    @assert(rng.q[0] == 0x58dadbeb'u32)
    @assert(rng.q[1] == 0xb43a33c3'u32)
    @assert(rng.q[4095] == 0xc6a605b4'u32)

    @assert(rng.nextU32() == 0xef915628'u32)
    @assert(rng.nextU32() == 0x39de1647'u32)
    @assert(rng.nextU32() == 0xb964ecde'u32)
    @assert(rng.nextU32() == 0x6e009e03'u32)
    @assert(rng.nextU32() == 0xfa519a6a'u32)
}

#test
{
    var rng: Random.CMWC4096
    rng.seedU32(0)

    @assert(rng.i == 4095)
    @assert(rng.c == 0)
    @assert(rng.q[0] == 0x30ed45a2'u32)
    @assert(rng.q[1] == 0x8af31f06'u32)
    @assert(rng.q[4095] == 0xef8bef6e'u32)

    @assert(rng.nextU32() == 0x60052e7d'u32)
    @assert(rng.nextU32() == 0xa6e1aff3'u32)
    @assert(rng.nextU32() == 0xaa5a0546'u32)
    @assert(rng.nextU32() == 0xa874171c'u32)
    @assert(rng.nextU32() == 0xfc852a71'u32)
}
