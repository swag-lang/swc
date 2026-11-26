#global if #command == Swag.CompilerCommand.Test
#global private

using Swag

#[Swag.Safety(.Overflow, false)]
func jenkinsReference(value: u32)->u32
{
    var key = (value + 0x7ED55D16_u32) + (value << 12)
    key = (key ^ 0xC761C23C_u32) ^ (key >> 19)
    key = (key + 0x165667B1_u32) + (key << 5)
    key = (key + 0xD3A2646C_u32) ^ (key << 9)
    key = (key + 0xFD7046C5_u32) + (key << 3)
    key = (key ^ 0xB55A4F09_u32) ^ (key >> 16)
    return key
}

#[Swag.Safety(.Overflow, false)]
func jenkinsReference(value: u64)->u64
{
    var key = (value ^ (value >> 30)) * 0xBF58_476D_1CE4_E5B9_u64
    key = (key ^ (key >> 27)) * 0x94D0_49BB_1331_11EB_u64
    key = key ^ (key >> 31)
    return key
}

func assertJenkins(value: u32)
{
    Swag.require(Hash.jenkins(value) == jenkinsReference(value))
}

func assertJenkins(value: u64)
{
    Swag.require(Hash.jenkins(value) == jenkinsReference(value))
}

#test
{
    Swag.require(Hash.jenkins(0_u32) == 0x6B4ED927_u32)
    Swag.require(Hash.jenkins(1_u32) == 0xB48681B6_u32)
    Swag.require(Hash.jenkins(0x12345678_u32) == 0x027C5489_u32)
    Swag.require(Hash.jenkins(0xFFFFFFFF_u32) == 0xFE64C182_u32)

    Swag.require(Hash.jenkins(0_u64) == 0_u64)
    Swag.require(Hash.jenkins(1_u64) == 0x5692_161D_100B_05E5_u64)
    Swag.require(Hash.jenkins(0x1234_5678_9ABC_DEF0_u64) == 0x9629_F58E_8EC5_B906_u64)
    Swag.require(Hash.jenkins(0xFFFF_FFFF_FFFF_FFFF_u64) == 0xB4D0_55FC_F2CB_BD7B_u64)

    for value in 65536
    {
        assertJenkins(cast(u32, value))
        assertJenkins(cast(u64, value))
    }

    assertJenkins(0x0001_0000_u32)
    assertJenkins(0x7FFF_FFFF_u32)
    assertJenkins(0x8000_0000_u32)
    assertJenkins(0xFFFF_FFFF_u32)

    assertJenkins(0x0000_0001_0000_0000_u64)
    assertJenkins(0x7FFF_FFFF_FFFF_FFFF_u64)
    assertJenkins(0x8000_0000_0000_0000_u64)
    assertJenkins(0xFFFF_FFFF_FFFF_FFFF_u64)
}
