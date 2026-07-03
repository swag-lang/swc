#global #if #command == Swag.CompilerCommand.Test
#global private
using Swag

#test
{
    var rng: Random.MWC

    @assert(rng.w == 521288629'u32)
    @assert(rng.z == 362436069'u32)

    @assert(rng.nextU32() == 0x30ed45a2'u32)
    @assert(rng.w == 0x106645a2'u32)
    @assert(rng.z == 0x30742087'u32)

    @assert(rng.nextU32() == 0x8af31f06'u32)
    @assert(rng.w == 0x13201f06'u32)
    @assert(rng.z == 0x125977d3'u32)

    @assert(rng.nextU32() == 0xf0696900'u32)
    @assert(rng.nextU32() == 0xbcf1d885'u32)
}

#test
{
    var rng: Random.MWC
    rng.seedU32(123456789'u32)

    @assert(rng.w == 123456789'u32)
    @assert(rng.z == 362436069'u32)
    @assert(rng.nextU32() == 0x58dadbeb'u32)
    @assert(rng.nextU32() == 0xb43a33c3'u32)
    @assert(rng.nextU32() == 0xf61bbb57'u32)
    @assert(rng.nextU32() == 0xd38f6367'u32)
}

#test
{
    var rng: Random.MWC
    rng.seedU32(1'u32, 2'u32)

    @assert(rng.w == 1'u32)
    @assert(rng.z == 2'u32)
    @assert(rng.nextU32() == 0x20d24650'u32)
    @assert(rng.nextU32() == 0xa972d900'u32)
    @assert(rng.nextU32() == 0x9277e34f'u32)
    @assert(rng.nextU32() == 0x142dde49'u32)
}

#test
{
    var rng: Random.MWC

    rng.seedU32(0'u32)
    @assert(rng.w == 521288629'u32)
    @assert(rng.z == 362436069'u32)
    @assert(rng.nextU32() == 0x30ed45a2'u32)

    rng.seedU32(0'u32, 0'u32)
    @assert(rng.w == 521288629'u32)
    @assert(rng.z == 362436069'u32)
    @assert(rng.nextU32() == 0x30ed45a2'u32)

    rng.seedU32(0'u32, 2'u32)
    @assert(rng.w == 521288629'u32)
    @assert(rng.z == 2'u32)
    @assert(rng.nextU32() == 0x313845a2'u32)

    rng.seedU32(1'u32, 0'u32)
    @assert(rng.w == 1'u32)
    @assert(rng.z == 362436069'u32)
    @assert(rng.nextU32() == 0x20874650'u32)
}
