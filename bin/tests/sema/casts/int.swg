#global fileprivate

func takes_u32(v: u32) {}
func takes_u8(v: u8) {}
func takes_s32(v: s32) {}

#test
{
    var a: u8 = 10
    var b: u16 = a
    var c: u32 = b
    var d: u64 = c
}

#test
{
    var a: s8 = -10
    var b: s16 = a
    var c: s32 = b
    var d: s64 = c
}

#test
{
    var a: u32 = 10
    var b: s32 = a
    var c: u32 = b
}

#test
{
    const A: u64 = 255
    const B: u8 = A
    #assert(B == 255'u8)
}

#test
{
    var a: u16 = 10
    var b: s32 = a
    var c: u32 = b
}

#test
{
    const A: s32 = 42
    const B: u8 = A
    #assert(B == 42'u8)
}
