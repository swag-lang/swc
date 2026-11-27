#global if #command == Swag.CompilerCommand.Test
#global private

using Swag

#test
{
    var rng: Random.MultiplyWithCarry32

    Swag.require(rng.w == 521288629_u32)
    Swag.require(rng.z == 362436069_u32)

    Swag.require(rng.nextU32() == 0x30ED45A2_u32)
    Swag.require(rng.w == 0x106645A2_u32)
    Swag.require(rng.z == 0x30742087_u32)

    Swag.require(rng.nextU32() == 0x8AF31F06_u32)
    Swag.require(rng.w == 0x13201F06_u32)
    Swag.require(rng.z == 0x125977D3_u32)

    Swag.require(rng.nextU32() == 0xF0696900_u32)
    Swag.require(rng.nextU32() == 0xBCF1D885_u32)
}

#test
{
    var rng: Random.MultiplyWithCarry32
    rng.seedU32(123456789_u32)

    Swag.require(rng.w == 123456789_u32)
    Swag.require(rng.z == 362436069_u32)
    Swag.require(rng.nextU32() == 0x58DADBEB_u32)
    Swag.require(rng.nextU32() == 0xB43A33C3_u32)
    Swag.require(rng.nextU32() == 0xF61BBB57_u32)
    Swag.require(rng.nextU32() == 0xD38F6367_u32)
}

#test
{
    var rng: Random.MultiplyWithCarry32
    rng.seedU32(1_u32, 2_u32)

    Swag.require(rng.w == 1_u32)
    Swag.require(rng.z == 2_u32)
    Swag.require(rng.nextU32() == 0x20D24650_u32)
    Swag.require(rng.nextU32() == 0xA972D900_u32)
    Swag.require(rng.nextU32() == 0x9277E34F_u32)
    Swag.require(rng.nextU32() == 0x142DDE49_u32)
}

#test
{
    var rng: Random.MultiplyWithCarry32

    rng.seedU32(0_u32)
    Swag.require(rng.w == 521288629_u32)
    Swag.require(rng.z == 362436069_u32)
    Swag.require(rng.nextU32() == 0x30ED45A2_u32)

    rng.seedU32(0_u32, 0_u32)
    Swag.require(rng.w == 521288629_u32)
    Swag.require(rng.z == 362436069_u32)
    Swag.require(rng.nextU32() == 0x30ED45A2_u32)

    rng.seedU32(0_u32, 2_u32)
    Swag.require(rng.w == 521288629_u32)
    Swag.require(rng.z == 2_u32)
    Swag.require(rng.nextU32() == 0x313845A2_u32)

    rng.seedU32(1_u32, 0_u32)
    Swag.require(rng.w == 1_u32)
    Swag.require(rng.z == 362436069_u32)
    Swag.require(rng.nextU32() == 0x20874650_u32)
}
