#global #if #command == Swag.CompilerCommand.Test
#global private

using Swag

#test
{
    var rng: Random.MWC

    @assert(rng.w == 521288629'u32)
    @assert(rng.z == 362436069'u32)

    @assert(rng.nextU32() == 0x30ED45A2'u32)
    @assert(rng.w == 0x106645A2'u32)
    @assert(rng.z == 0x30742087'u32)

    @assert(rng.nextU32() == 0x8AF31F06'u32)
    @assert(rng.w == 0x13201F06'u32)
    @assert(rng.z == 0x125977D3'u32)

    @assert(rng.nextU32() == 0xF0696900'u32)
    @assert(rng.nextU32() == 0xBCF1D885'u32)
}

#test
{
    var rng: Random.MWC
    rng.seedU32(123456789'u32)

    @assert(rng.w == 123456789'u32)
    @assert(rng.z == 362436069'u32)
    @assert(rng.nextU32() == 0x58DADBEB'u32)
    @assert(rng.nextU32() == 0xB43A33C3'u32)
    @assert(rng.nextU32() == 0xF61BBB57'u32)
    @assert(rng.nextU32() == 0xD38F6367'u32)
}

#test
{
    var rng: Random.MWC
    rng.seedU32(1'u32, 2'u32)

    @assert(rng.w == 1'u32)
    @assert(rng.z == 2'u32)
    @assert(rng.nextU32() == 0x20D24650'u32)
    @assert(rng.nextU32() == 0xA972D900'u32)
    @assert(rng.nextU32() == 0x9277E34F'u32)
    @assert(rng.nextU32() == 0x142DDE49'u32)
}

#test
{
    var rng: Random.MWC

    rng.seedU32(0'u32)
    @assert(rng.w == 521288629'u32)
    @assert(rng.z == 362436069'u32)
    @assert(rng.nextU32() == 0x30ED45A2'u32)

    rng.seedU32(0'u32, 0'u32)
    @assert(rng.w == 521288629'u32)
    @assert(rng.z == 362436069'u32)
    @assert(rng.nextU32() == 0x30ED45A2'u32)

    rng.seedU32(0'u32, 2'u32)
    @assert(rng.w == 521288629'u32)
    @assert(rng.z == 2'u32)
    @assert(rng.nextU32() == 0x313845A2'u32)

    rng.seedU32(1'u32, 0'u32)
    @assert(rng.w == 1'u32)
    @assert(rng.z == 362436069'u32)
    @assert(rng.nextU32() == 0x20874650'u32)
}
