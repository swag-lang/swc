#global #if #command == Swag.CompilerCommand.Test
#global private

using Swag

#[Swag.Safety(.Overflow, false)]
func jenkinsReference(value: u32)->u32
{
    var key = (value + 0x7ED55D16'u32) + (value << 12)
    key = (key ^ 0xC761C23C'u32) ^ (key >> 19)
    key = (key + 0x165667B1'u32) + (key << 5)
    key = (key + 0xD3A2646C'u32) ^ (key << 9)
    key = (key + 0xFD7046C5'u32) + (key << 3)
    key = (key ^ 0xB55A4F09'u32) ^ (key >> 16)
    return key
}

#[Swag.Safety(.Overflow, false)]
func jenkinsReference(value: u64)->u64
{
    var key = (value ^ (value >> 30)) * 0xBF58_476D_1CE4_E5B9'u64
    key = (key ^ (key >> 27)) * 0x94D0_49BB_1331_11EB'u64
    key = key ^ (key >> 31)
    return key
}

func assertJenkins(value: u32)
{
    @assert(Hash.jenkins(value) == jenkinsReference(value))
}

func assertJenkins(value: u64)
{
    @assert(Hash.jenkins(value) == jenkinsReference(value))
}

#test
{
    @assert(Hash.jenkins(0'u32) == 0x6B4ED927'u32)
    @assert(Hash.jenkins(1'u32) == 0xB48681B6'u32)
    @assert(Hash.jenkins(0x12345678'u32) == 0x027C5489'u32)
    @assert(Hash.jenkins(0xFFFFFFFF'u32) == 0xFE64C182'u32)

    @assert(Hash.jenkins(0'u64) == 0'u64)
    @assert(Hash.jenkins(1'u64) == 0x5692_161D_100B_05E5'u64)
    @assert(Hash.jenkins(0x1234_5678_9ABC_DEF0'u64) == 0x9629_F58E_8EC5_B906'u64)
    @assert(Hash.jenkins(0xFFFF_FFFF_FFFF_FFFF'u64) == 0xB4D0_55FC_F2CB_BD7B'u64)

    for value in 65536
    {
        assertJenkins(cast(u32) value)
        assertJenkins(cast(u64) value)
    }

    assertJenkins(0x0001_0000'u32)
    assertJenkins(0x7FFF_FFFF'u32)
    assertJenkins(0x8000_0000'u32)
    assertJenkins(0xFFFF_FFFF'u32)

    assertJenkins(0x0000_0001_0000_0000'u64)
    assertJenkins(0x7FFF_FFFF_FFFF_FFFF'u64)
    assertJenkins(0x8000_0000_0000_0000'u64)
    assertJenkins(0xFFFF_FFFF_FFFF_FFFF'u64)
}
