#global #if #command == Swag.CompilerCommand.Test
#global private
using Swag

#[Swag.Safety(.Overflow, false)]
func jenkinsReference(value: u32)->u32
{
    var key = (value + 0x7ed55d16'u32) + (value << 12)
    key = (key ^ 0xc761c23c'u32) ^ (key >> 19)
    key = (key + 0x165667b1'u32) + (key << 5)
    key = (key + 0xd3a2646c'u32) ^ (key << 9)
    key = (key + 0xfd7046c5'u32) + (key << 3)
    key = (key ^ 0xb55a4f09'u32) ^ (key >> 16)
    return key
}

#[Swag.Safety(.Overflow, false)]
func jenkinsReference(value: u64)->u64
{
    var key = (value ^ (value >> 30)) * 0xbf58_476d_1ce4_e5b9'u64
    key = (key ^ (key >> 27)) * 0x94d0_49bb_1331_11eb'u64
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
    @assert(Hash.jenkins(0'u32) == 0x6b4ed927'u32)
    @assert(Hash.jenkins(1'u32) == 0xb48681b6'u32)
    @assert(Hash.jenkins(0x12345678'u32) == 0x027c5489'u32)
    @assert(Hash.jenkins(0xffffffff'u32) == 0xfe64c182'u32)

    @assert(Hash.jenkins(0'u64) == 0'u64)
    @assert(Hash.jenkins(1'u64) == 0x5692_161d_100b_05e5'u64)
    @assert(Hash.jenkins(0x1234_5678_9abc_def0'u64) == 0x9629_f58e_8ec5_b906'u64)
    @assert(Hash.jenkins(0xffff_ffff_ffff_ffff'u64) == 0xb4d0_55fc_f2cb_bd7b'u64)

    for value in 65536
    {
        assertJenkins(cast(u32) value)
        assertJenkins(cast(u64) value)
    }

    assertJenkins(0x0001_0000'u32)
    assertJenkins(0x7fff_ffff'u32)
    assertJenkins(0x8000_0000'u32)
    assertJenkins(0xffff_ffff'u32)

    assertJenkins(0x0000_0001_0000_0000'u64)
    assertJenkins(0x7fff_ffff_ffff_ffff'u64)
    assertJenkins(0x8000_0000_0000_0000'u64)
    assertJenkins(0xffff_ffff_ffff_ffff'u64)
}
