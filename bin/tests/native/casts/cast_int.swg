#global fileprivate // swc-option suite-test

func takes_u32(v: u32) {}
func takes_u8(v: u8) {}
func takes_s32(v: s32) {}






#test
{
    const A: u64 = 255
    const B: u8 = A
    #assert(B == 255'u8)
}



#test
{
    var a: u16 = 10
    takes_u32(a)
}

#test
{
    var a: u16 = 10
    var b: u32 = 0
    b = a
    var c: u8 = 0
}







#test
{
    const A: s32 = 42
    const B: u8 = A
    #assert(B == 42'u8)
}

