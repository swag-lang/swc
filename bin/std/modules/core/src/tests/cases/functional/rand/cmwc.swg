#global if #command == Swag.CompilerCommand.Test
#global private

using Swag

#test
{
    var rng: Random.ComplementaryMultiplyWithCarry4096

    Swag.require(rng.index == 4096)
    Swag.require(rng.carry == 0)

    Swag.require(rng.nextU32() == 0xC2B9C7E2_u32)
    Swag.require(rng.nextU32() == 0x9B459F2F_u32)
    Swag.require(rng.nextU32() == 0x53116140_u32)
    Swag.require(rng.nextU32() == 0x549DF40D_u32)
    Swag.require(rng.nextU32() == 0x1D84A0A8_u32)
}

#test
{
    var rng: Random.ComplementaryMultiplyWithCarry4096
    rng.seedU32(362436)

    Swag.require(rng.index == 4095)
    Swag.require(rng.carry == 362436)
    Swag.require(rng.state[0] == 0x45D10545_u32)
    Swag.require(rng.state[1] == 0x7945A8DA_u32)
    Swag.require(rng.state[4095] == 0xF7A65156_u32)

    Swag.require(rng.nextU32() == 0xC2B9C7E2_u32)
    Swag.require(rng.nextU32() == 0x9B459F2F_u32)
    Swag.require(rng.nextU32() == 0x53116140_u32)
    Swag.require(rng.nextU32() == 0x549DF40D_u32)
    Swag.require(rng.nextU32() == 0x1D84A0A8_u32)
}

#test
{
    var rng: Random.ComplementaryMultiplyWithCarry4096
    rng.seedU32(123456789)

    Swag.require(rng.index == 4095)
    Swag.require(rng.carry == 123456789 % 809430660)
    Swag.require(rng.state[0] == 0x58DADBEB_u32)
    Swag.require(rng.state[1] == 0xB43A33C3_u32)
    Swag.require(rng.state[4095] == 0xC6A605B4_u32)

    Swag.require(rng.nextU32() == 0xEF915628_u32)
    Swag.require(rng.nextU32() == 0x39DE1647_u32)
    Swag.require(rng.nextU32() == 0xB964ECDE_u32)
    Swag.require(rng.nextU32() == 0x6E009E03_u32)
    Swag.require(rng.nextU32() == 0xFA519A6A_u32)
}

#test
{
    var rng: Random.ComplementaryMultiplyWithCarry4096
    rng.seedU32(0)

    Swag.require(rng.index == 4095)
    Swag.require(rng.carry == 0)
    Swag.require(rng.state[0] == 0x30ED45A2_u32)
    Swag.require(rng.state[1] == 0x8AF31F06_u32)
    Swag.require(rng.state[4095] == 0xEF8BEF6E_u32)

    Swag.require(rng.nextU32() == 0x60052E7D_u32)
    Swag.require(rng.nextU32() == 0xA6E1AFF3_u32)
    Swag.require(rng.nextU32() == 0xAA5A0546_u32)
    Swag.require(rng.nextU32() == 0xA874171C_u32)
    Swag.require(rng.nextU32() == 0xFC852A71_u32)
}

#test
{
    // The low-word addition can overflow even though the 64-bit sum cannot.
    var rng: Random.ComplementaryMultiplyWithCarry4096
    rng.state[0] = 0x0207E7CB_u32
    rng.carry    = 0_u32
    rng.index    = 4095

    Swag.require(rng.nextU32() == 0xFFFFFFDF_u32)
    Swag.require(rng.carry == 0x95_u32)
    Swag.require(rng.nextU32() == 0xFFFFFF69_u32)
}
